"""Microphone callback never waits for inference, UI, or disk transactions."""
import math
from collections import deque
import queue
import subprocess
import threading
import time


class Recorder:
    def __init__(self, store, notify, wake):
        self.store, self.notify, self.wake = store, notify, wake
        self.stream = None
        self.note_id = None
        self.paused = False
        self.frames = queue.Queue(maxsize=120)  # 30 seconds; overflow is a visible stop.
        self.thread = None
        self.guard = None
        self.fault = ""
        self.last_frame = time.monotonic()
        self.stopping = False
        self.stop_thread = None
        self.stop_started = 0
        self.stop_error = ""
        self.stop_error_reported = False
        self.journal_sealed = False
        self.capture_lock = threading.Lock()

    def devices(self):
        import sounddevice as sd
        return [{"id": i, "name": d["name"]} for i, d in enumerate(sd.query_devices()) if d["max_input_channels"] > 0]

    def start(self, note_id, device=None):
        import sounddevice as sd
        if self.note_id:
            raise RuntimeError("A recording is already running")
        self.note_id = note_id
        self.paused = False
        self.stopping = False
        self.stop_error = ""
        self.stop_error_reported = False
        self.journal_sealed = False
        self.fault = ""
        self.frames = queue.Queue(maxsize=120)
        self.last_frame = time.monotonic()
        try:
            rate = 16000
            try:
                sd.check_input_settings(device=device, channels=1, dtype="int16", samplerate=rate)
            except sd.PortAudioError:
                rate = int(sd.query_devices(device, "input")["default_samplerate"])
            self.rate = rate
            self.stream = sd.RawInputStream(device=device, samplerate=rate, channels=1,
                                           dtype="int16", blocksize=rate // 4, callback=self.callback)
            self.store.update(note_id, status="recording")
            self.thread = threading.Thread(target=self.write_loop, name="audio-journal", daemon=True)
            self.thread.start()
            self.stream.start()
            self.guard = subprocess.Popen(["/usr/bin/caffeinate", "-i", "-w", str(__import__('os').getpid())])
        except BaseException:
            if self.stream:
                self.stream.close()
            if self.thread and self.thread.is_alive():
                self.frames.put(None)
                self.thread.join()
            self.stream = self.thread = None
            self.store.update(note_id, status="interrupted")
            self.note_id = None
            raise

    def callback(self, data, frames, time_info, status):
        self.last_frame = time.monotonic()
        if status:
            self.fault = f"The microphone reported {status}. Recording stopped; captured audio is recoverable."
        with self.capture_lock:
            if self.paused or self.stopping or self.fault:
                return
            try:
                self.frames.put_nowait(bytes(data))
            except queue.Full:
                self.fault = "Audio could not be saved fast enough. Recording stopped; saved chunks are recoverable."

    def write_loop(self):
        import numpy as np
        elapsed = float(self.store.note(self.note_id)["duration"])
        segment_id = None
        start = elapsed
        tail = b""
        silence = 0.0
        waveform = deque([0.0] * 160, maxlen=160)
        voice_floor = 10 ** (self.store.note(self.note_id).get("voice_db", -72) / 20)
        try:
            while True:
                pcm = self.frames.get()
                if pcm is None:
                    if segment_id:
                        self.store.close_segment(segment_id)
                    self.journal_sealed = True
                    self.wake.set()
                    return
                if pcm == "boundary":
                    if segment_id:
                        self.store.close_segment(segment_id)
                        segment_id = None
                    tail = b""
                    silence = 0
                    self.wake.set()
                    continue
                if segment_id is None:
                    overlap = len(tail) / (self.rate * 2)
                    start = max(0, elapsed - overlap)
                    segment_id = self.store.segment(self.note_id, start, self.rate, trim=elapsed)
                    if tail:
                        self.store.append(segment_id, tail, elapsed)
                elapsed += len(pcm) / (self.rate * 2)
                self.store.append(segment_id, pcm, elapsed)
                samples = np.frombuffer(pcm, dtype="<i2").astype(np.float32) / 32768
                rms = math.sqrt(float(np.mean(samples * samples)))
                silence = silence + len(pcm) / (self.rate * 2) if rms < voice_floor else 0
                # Round in samples before converting to bytes (22.05 kHz has
                # an odd byte count at exactly .75 s).
                tail = (tail + pcm)[-(int(self.rate * 0.75) * 2):]
                db = max(-90, 20 * math.log10(max(rms, 1e-6)))
                for frame in np.array_split(samples, 10):
                    amplitude = float(np.sqrt(np.mean(frame * frame))) if len(frame) else 0
                    waveform.append(min(1, math.sqrt(amplitude * 8)))
                self.notify({"event": "meter", "seconds": elapsed, "level": max(0, min(1, (db + 90) / 90)),
                             "db": db, "waveform": list(waveform)})
                if elapsed - start >= 20 or (elapsed - start >= 2 and silence >= 0.75):
                    self.store.close_segment(segment_id)
                    segment_id = None
                    self.wake.set()
        except BaseException as exc:
            self.fault = "Recovery audio could not be saved. Recording stopped: " + str(exc)
            if segment_id:
                try:
                    self.store.close_segment(segment_id)
                except Exception:
                    pass
            self.wake.set()

    def pause(self):
        if self.stopping:
            return
        self.paused = not self.paused
        if self.paused:
            self.frames.put("boundary")
        self.store.update(self.note_id, status="paused" if self.paused else "recording")

    def request_stop(self, interrupted=False):
        if not self.note_id or self.stopping:
            return
        with self.capture_lock:
            self.stopping = True
        self.stop_started = time.monotonic()
        def finish():
            try:
                self.stop(interrupted)
            except Exception as exc:
                self.stop_error = str(exc)
        self.stop_thread = threading.Thread(target=finish, name="microphone-stop", daemon=True)
        self.stop_thread.start()

    def stop(self, interrupted=False):
        if self.stop_thread and self.stop_thread.is_alive() and threading.current_thread() is not self.stop_thread:
            self.stop_thread.join(timeout=10)
            if self.stop_thread.is_alive():
                raise RuntimeError("The microphone is still closing; captured audio has been saved.")
        if not self.note_id:
            return
        with self.capture_lock:
            self.stopping = True
        note_id = self.note_id
        # Seal durable audio before touching CoreAudio: device shutdown can hang.
        if self.thread and self.thread.is_alive():
            self.frames.put(None, timeout=10)
            self.thread.join(timeout=10)
            if self.thread.is_alive():
                raise RuntimeError("Audio is still being saved. Keep the app open and retry stopping.")
        elif not self.thread:
            self.journal_sealed = True
        if self.guard:
            self.guard.terminate()
            try:
                self.guard.wait(timeout=2)
            except subprocess.TimeoutExpired:
                self.guard.kill()
                self.guard.wait()
        self.store.update(note_id, status="interrupted" if interrupted else "ready")
        if self.stream:
            self.stream.stop()
            self.stream.close()
        self.stream = self.thread = self.guard = None
        self.note_id = None
        self.paused = False
        self.stopping = False

    def check(self):
        if not self.note_id:
            return
        if self.stopping:
            if self.stop_error and not self.stop_error_reported:
                self.stop_error_reported = True
                self.notify({"event": "error", "message": self.stop_error})
            return
        if self.fault:
            message = self.fault
            self.request_stop(interrupted=True)
            self.notify({"event": "error", "message": message})
        elif not self.paused and time.monotonic() - self.last_frame > 6:
            self.fault = "The microphone stopped delivering audio. Recording stopped; saved chunks are recoverable."
            self.check()
