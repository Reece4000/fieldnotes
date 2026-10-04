"""Opt-in real-model integration check, using generated speech rather than a mic."""
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import threading
import time

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "worker"))
from backend import Backend
from recorder import Recorder


def main():
    import numpy as np
    import soundfile as sf
    with tempfile.TemporaryDirectory(prefix="fieldnotes-validation-") as directory:
        directory = Path(directory)
        speech_file = directory / "speech.aiff"
        script = ("Start the debugging session. The record button should stay active while transcription runs. "
                  "We found a race condition when the user closes the window. "
                  "Keep the captured audio until the transcript is safely saved. End the test.")
        subprocess.run(["say", "-v", "Daniel", "-o", str(speech_file), script], check=True)
        audio, rate = sf.read(speech_file, dtype="int16")
        if audio.ndim > 1:
            audio = audio[:, 0]
        speech_file.unlink()
        # Over three minutes, through the actual chunk writer and local model.
        repeats = max(12, int(185 * rate / len(audio)) + 1)
        audio = np.tile(audio, repeats).astype("<i2")
        events = []
        backend = Backend(directory / "notes.sqlite3", emit=events.append)
        try:
            note = backend.store.create("Long debugging test", "Validation")
            recorder = Recorder(backend.store, lambda _: None, backend.wake)
            recorder.note_id = note
            recorder.rate = rate
            backend.store.update(note, status="recording")
            thread = threading.Thread(target=recorder.write_loop)
            thread.start()
            size = rate // 4
            for index in range(0, len(audio), size):
                recorder.frames.put(audio[index:index + size].tobytes())
            recorder.frames.put(None)
            thread.join(timeout=30)
            assert not thread.is_alive() and not recorder.fault, recorder.fault
            backend.store.update(note, status="ready")
            backend.wake.set()
            deadline = time.monotonic() + 180
            while time.monotonic() < deadline:
                counts = backend.store.counts(note)
                if counts.get("error") or backend.engine_status == "error":
                    raise AssertionError(backend.engine_error)
                if not any(counts.get(s, 0) for s in ("open", "processing", "pending")):
                    break
                time.sleep(.25)
            counts = backend.store.counts(note)
            assert counts.get("done", 0) > 8 and set(counts) == {"done"}, counts
            result = backend.store.note(note)
            text = result["body"].lower()
            assert text.count("debugging session") >= repeats - 2, text
            assert text.count("safely saved") >= repeats - 2, text
            assert backend.store.db.execute("SELECT COUNT(*) FROM blocks").fetchone()[0] == 0
            print(json.dumps({"seconds": round(result["duration"], 1), "chunks": counts["done"],
                              "repeated_passages": repeats, "debugging_passages_found": text.count("debugging session"),
                              "audio_blocks_remaining": 0, "result": "passed"}, indent=2))
            # Reproduce the user's pattern: one utterance, then noise and a
            # faint unrelated voice. Real VAD + ASR must save only the utterance.
            subprocess.run(["say", "-v", "Daniel", "-o", str(speech_file), "This is a test recording."], check=True)
            utterance, utterance_rate = sf.read(speech_file, dtype="float32")
            speech_file.unlink()
            from scipy.signal import resample_poly
            from math import gcd
            divisor = gcd(utterance_rate, 16000)
            utterance = resample_poly(utterance, 16000 // divisor, utterance_rate // divisor)
            # Reuse the previous long phrase as unrelated background speech.
            background = audio[:rate * 14].astype(np.float32) / 32768
            divisor = gcd(rate, 16000)
            background = resample_poly(background, 16000 // divisor, rate // divisor) * .003
            fixture = np.concatenate((np.zeros(16000 * 3), utterance, np.zeros(16000 * 8),
                                      np.random.default_rng(4).normal(0, .02, 16000 * 12), background,
                                      np.zeros(16000 * 5)))
            fixture = (np.clip(fixture, -1, 1) * 32767).astype("<i2")
            gate_note = backend.store.create()
            capture = Recorder(backend.store, lambda _: None, backend.wake)
            capture.note_id, capture.rate = gate_note, 16000
            writer = threading.Thread(target=capture.write_loop)
            writer.start()
            for index in range(0, len(fixture), 4000): capture.frames.put(fixture[index:index + 4000].tobytes())
            capture.frames.put(None); writer.join(timeout=30)
            assert not writer.is_alive() and not capture.fault, capture.fault
            backend.wake.set()
            deadline = time.monotonic() + 120
            while time.monotonic() < deadline:
                counts = backend.store.counts(gate_note)
                if not any(counts.get(s, 0) for s in ("open", "pending", "processing", "error")): break
                if counts.get("error"): raise AssertionError(backend.engine_error)
                time.sleep(.25)
            gated = backend.store.note(gate_note)
            assert gated["body"].count("[") == 1, gated["body"]
            assert "this is a test recording" in gated["body"].lower(), gated["body"]
            assert gated["body"].startswith("[00:00:03]"), gated["body"]
            assert backend.store.db.execute("SELECT COUNT(*) FROM blocks").fetchone()[0] == 0
            print(json.dumps({"speech_then_background_seconds": round(gated["duration"], 1),
                              "saved_entries": 1, "transcript": gated["body"], "audio_blocks_remaining": 0,
                              "result": "passed"}, indent=2))
        finally:
            backend.shutdown()


if __name__ == "__main__":
    main()
