import os
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import threading
import time
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "worker"))
from store import Store
from recorder import Recorder
from backend import clean_overlap


class RecoveryTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.path = Path(self.temp.name) / "notes.sqlite3"
        self.store = Store(self.path)
        self.note = self.store.create("Debugging run", "HCI")

    def tearDown(self):
        self.store.close()
        self.temp.cleanup()

    def test_stop_does_not_leave_capture_feedback_running_while_device_closes(self):
        from backend import Backend
        events, closing, release = [], threading.Event(), threading.Event()
        backend = Backend(Path(self.temp.name) / "stop.sqlite3", emit=events.append, fake_engine=True)
        class SlowDevice:
            def stop(self):
                closing.set()
                release.wait(2)
            def close(self):
                pass
        try:
            note = backend.store.create()
            backend.recorder.note_id = note
            backend.recorder.stream = SlowDevice()
            backend.store.update(note, status="recording")
            started = time.monotonic()
            backend.command({"action": "stop"})
            self.assertLess(time.monotonic() - started, .15, "Stop blocked on the audio device; button/reel cannot update")
            self.assertTrue(closing.wait(1))
            state = [e for e in events if e["event"] == "state"][-1]
            self.assertTrue(state.get("stopping"), "The UI still reports normal capture after Stop")
            backend.command({"action": "query"})
            release.set()
            backend.recorder.stop_thread.join(1)
            backend.check_capture()
            state = [e for e in events if e["event"] == "state"][-1]
            self.assertEqual(state["active"], "")
            self.assertFalse(state["stopping"])
        finally:
            release.set()
            backend.shutdown()

    def test_hung_device_restarts_only_after_the_capture_journal_is_sealed(self):
        from backend import Backend
        events, closing, release = [], threading.Event(), threading.Event()
        backend = Backend(Path(self.temp.name) / "hung-stop.sqlite3", emit=events.append, fake_engine=True)
        class HungDevice:
            def stop(self):
                closing.set()
                release.wait(3)
            def close(self):
                pass
        try:
            note = backend.store.create()
            recorder = backend.recorder
            recorder.note_id, recorder.rate, recorder.stream = note, 16000, HungDevice()
            backend.store.update(note, status="recording")
            recorder.thread = threading.Thread(target=recorder.write_loop)
            recorder.thread.start()
            recorder.frames.put(b"\x00\x20" * 4000)
            recorder.fault = "The microphone stopped delivering audio."
            backend.command({"action": "stop"})
            self.assertTrue(closing.wait(1), "The device close must follow journal sealing")
            self.assertFalse(recorder.thread.is_alive())
            self.assertEqual(backend.store.note(note)["duration"], .25)
            self.assertEqual(backend.store.note(note)["status"], "ready")
            self.assertEqual(backend.store.counts(note).get("open", 0), 0)
            recorder.callback(b"\x00\x20" * 4000, 4000, None, None)
            self.assertTrue(recorder.frames.empty(), "Capture continued after Stop")
            recorder.stop_started -= 9
            backend.check_capture()
            self.assertTrue(backend.restarting)
            self.assertEqual(sum(e["event"] == "restart" for e in events), 1)
        finally:
            release.set()
            backend.shutdown()

    def test_hung_close_exits_the_real_service_and_keeps_inflight_audio_recoverable(self):
        path = Path(self.temp.name) / "stop-process.sqlite3"
        result = subprocess.run([sys.executable, str(Path(__file__).with_name("stop_backend.py")), "--data", str(path)],
                                input='{"action":"stop"}\n', text=True, capture_output=True, timeout=5)
        self.assertEqual(result.returncode, 0, result.stderr)
        events = [json.loads(line) for line in result.stdout.splitlines()]
        self.assertTrue(any(e["event"] == "state" and e.get("stopping") for e in events))
        self.assertEqual(sum(e["event"] == "restart" for e in events), 1)
        recovered = Store(path)
        try:
            recovered.recover()
            note = recovered.db.execute("SELECT id,duration FROM notes").fetchone()
            self.assertEqual(note[1], .25)
            self.assertEqual(recovered.counts(note[0]).get("pending"), 1)
            self.assertGreater(recovered.db.execute("SELECT count(*) FROM blocks").fetchone()[0], 0)
        finally:
            recovered.close()

    def test_sidebar_copy_returns_full_note_without_changing_selection(self):
        from backend import Backend
        events = []
        backend = Backend(Path(self.temp.name) / "copy.sqlite3", emit=events.append, fake_engine=True)
        try:
            opened = backend.store.create("Open note")
            other = backend.store.create("Other note")
            transcript = "[00:00:00] Other note.\n\n" + "Full edited transcript. " * 500
            backend.store.update(other, body=transcript)
            backend.selected = opened
            backend.command({"action": "copy", "id": other})
            copies = [e for e in events if e.get("event") == "copy"]
            self.assertEqual(copies, [{"event": "copy", "id": other, "text": transcript}])
            self.assertEqual(backend.selected, opened)
            self.assertEqual(backend.store.note(other)["body"], transcript)
            with self.assertRaisesRegex(ValueError, "no longer available"):
                backend.command({"action": "copy", "id": "missing"})
        finally:
            backend.shutdown()

    def test_normal_shutdown_keeps_inflight_audio_ready_for_automatic_recovery(self):
        from backend import Backend
        path = Path(self.temp.name) / "closing.sqlite3"
        started, release = threading.Event(), threading.Event()
        backend = Backend(path, emit=lambda _: None, fake_engine=True)
        def interrupted_decode(*args, **kwargs):
            started.set()
            if not release.wait(5):
                raise RuntimeError("Test did not release inference")
            raise RuntimeError("The transcription process closed its output")
        backend.store.complete = interrupted_decode
        try:
            note = backend.store.create()
            segment = backend.store.segment(note, 0, 16000)
            backend.store.append(segment, b"\x00\x20" * 16000, 1)
            backend.store.close_segment(segment)
            backend.wake.set()
            self.assertTrue(started.wait(3))
            backend.command({"action": "shutdown"})
        finally:
            release.set()
            backend.shutdown()
        recovered = Store(path)
        try:
            recovered.recover()
            self.assertEqual(recovered.counts(note).get("error", 0), 0)
            self.assertEqual(recovered.counts(note).get("pending", 0), 1)
            self.assertEqual(recovered.db.execute("SELECT count(*) FROM blocks").fetchone()[0], 1)
        finally:
            recovered.close()
        completed = threading.Event()
        def on_state(event):
            if event.get("document", {}).get("body"):
                completed.set()
        resumed = Backend(path, emit=on_state, fake_engine=True)
        try:
            self.assertTrue(completed.wait(3))
            self.assertIn("A recovered test recording.", resumed.store.note(note)["body"])
            self.assertEqual(resumed.store.db.execute("SELECT count(*) FROM blocks").fetchone()[0], 0)
        finally:
            resumed.shutdown()

    def segment(self, pcm=b"recover-me-unique-audio-sentinel" * 100):
        segment = self.store.segment(self.note, 0, 16000)
        self.store.append(segment, pcm, 20)
        self.store.close_segment(segment)
        return segment

    def test_failed_inference_keeps_audio_and_retry_order(self):
        first = self.segment()
        second = self.segment()
        self.assertEqual(self.store.next_segment()["id"], first)
        self.store.fail(first, "engine crashed")
        self.assertIsNone(self.store.next_segment())
        self.assertGreater(self.store.db.execute("SELECT count(*) FROM blocks").fetchone()[0], 0)
        self.store.retry(self.note)
        self.assertEqual(self.store.next_segment()["id"], first)
        self.store.complete(first, "First section.")
        self.assertEqual(self.store.next_segment()["id"], second)

    def test_transcript_and_audio_delete_are_one_transaction(self):
        segment = self.segment()
        self.store.next_segment()
        self.store.db.execute("CREATE TRIGGER block_failure BEFORE DELETE ON blocks BEGIN SELECT RAISE(ABORT,'simulated disk failure'); END")
        with self.assertRaises(Exception):
            self.store.complete(segment, "This must not partially commit.")
        self.assertEqual(self.store.note(self.note)["body"], "")
        self.assertEqual(self.store.counts()["processing"], 1)
        self.assertGreater(self.store.db.execute("SELECT count(*) FROM blocks").fetchone()[0], 0)

    def test_completion_erases_audio_and_is_idempotent(self):
        segment = self.segment()
        self.store.complete(segment, "Session saved.")
        self.store.complete(segment, "Session saved.")
        self.assertEqual(self.store.note(self.note)["body"].count("Session saved."), 1)
        self.assertEqual(self.store.db.execute("SELECT count(*) FROM blocks").fetchone()[0], 0)
        self.assertNotIn(b"recover-me-unique-audio-sentinel", self.path.read_bytes())
        self.assertFalse(Path(str(self.path) + "-wal").exists())
        self.assertFalse(Path(str(self.path) + "-journal").exists())

    def test_real_process_crash_recovers_open_audio(self):
        code = """
from store import Store
import os, sys
s=Store(sys.argv[1]); n=s.create('Interrupted test')
s.update(n,status='recording')
c=s.segment(n,0,16000); s.append(c,b'captured-before-crash',19)
os._exit(23)
"""
        env = {**os.environ, "PYTHONPATH": str(Path(__file__).resolve().parents[1] / "worker")}
        result = subprocess.run([sys.executable, "-c", code, str(self.path)], env=env)
        self.assertEqual(result.returncode, 23)
        self.store.recover()
        recovered = self.store.next_segment()
        self.assertEqual(recovered["pcm"], b"captured-before-crash")
        self.assertEqual(self.store.note(recovered["note_id"])["status"], "interrupted")

    def test_edits_collections_and_trash_persist(self):
        self.store.update(self.note, body="Edited text", collection="Session 3", title="Participant 7")
        self.store.update(self.note, deleted=1)
        self.assertEqual(self.store.notes(), [])
        self.store.update(self.note, deleted=0)
        reopened = Store(self.path)
        self.assertEqual(reopened.note(self.note)["body"], "Edited text")
        reopened.close()

    def test_three_minutes_have_no_recording_cap_and_bounded_chunks(self):
        recorder = Recorder(self.store, lambda _: None, threading.Event())
        recorder.note_id = self.note
        recorder.rate = 16000
        thread = threading.Thread(target=recorder.write_loop)
        thread.start()
        # Continuous speech-like PCM forces maximum-window splitting.
        pcm = b"\x00\x20" * 4000
        for _ in range(720):
            recorder.frames.put(pcm)
        recorder.frames.put(None)
        thread.join(timeout=30)
        self.assertFalse(thread.is_alive())
        self.assertEqual(self.store.note(self.note)["duration"], 180)
        rows = self.store.db.execute("SELECT * FROM segments ORDER BY id").fetchall()
        self.assertGreater(len(rows), 8)
        for row in rows:
            self.assertLessEqual(row["end"] - row["start"], 20.25)
        self.assertEqual(rows[-1]["end"], 180)
        self.assertEqual(recorder.fault, "")

    def test_overlap_uses_word_midpoints(self):
        result = {"text": "old boundary new words", "words": [
            {"text": "old", "start": 0, "end": .2},
            {"text": "boundary", "start": .6, "end": .85},
            {"text": "new", "start": .8, "end": 1.0},
            {"text": "words", "start": 1, "end": 1.2}]}
        self.assertEqual(clean_overlap(result, {"start": 19.25, "trim": 20}), "new words")

    def test_overlap_removes_a_shifted_duplicate_boundary_word(self):
        result = {"text": "test. Hello, this is a test.", "words": [
            {"text": "test.", "start": .7, "end": 1.0},
            {"text": "Hello,", "start": 1.2, "end": 1.5},
            {"text": "this", "start": 1.5, "end": 1.7},
            {"text": "is", "start": 1.7, "end": 1.8},
            {"text": "a", "start": 1.8, "end": 1.9},
            {"text": "test.", "start": 1.9, "end": 2.2}]}
        self.assertEqual(clean_overlap(result, {"start": 8.25, "trim": 9}, "Hello, this is a test."), "Hello, this is a test.")

    def test_cropped_speech_keeps_its_original_recording_timestamp(self):
        text, start = clean_overlap({"text": "Spoken after silence.", "words": [
            {"text": "Spoken", "start": 3.1, "end": 3.3}]}, {"start": 20, "trim": 20}, with_start=True)
        segment = self.segment()
        self.store.complete(segment, text, start=start)
        self.assertTrue(self.store.note(self.note)["body"].startswith("[00:00:23]"))

    def test_22050_hz_overlap_remains_sample_aligned(self):
        recorder = Recorder(self.store, lambda _: None, threading.Event())
        recorder.note_id, recorder.rate = self.note, 22050
        thread = threading.Thread(target=recorder.write_loop)
        thread.start()
        for _ in range(85):
            recorder.frames.put(b"\x00\x20" * 5512)
        recorder.frames.put(None)
        thread.join(timeout=20)
        self.assertFalse(thread.is_alive())
        self.assertEqual(recorder.fault, "")
        for row in self.store.db.execute("SELECT LENGTH(pcm) FROM blocks"):
            self.assertEqual(row[0] % 2, 0)

    def test_waveform_meter_is_bounded_and_reports_durably_captured_audio(self):
        events = []
        def notify(event):
            # The meter is a capture receipt, not fabricated animation.
            self.assertEqual(self.store.note(self.note)["duration"], event["seconds"])
            events.append(event)
        recorder = Recorder(self.store, notify, threading.Event())
        recorder.note_id, recorder.rate = self.note, 16000
        recorder.frames.put(b"\0\0" * 4000)
        recorder.frames.put(b"\x00\x20" * 4000)
        recorder.frames.put(None)
        recorder.write_loop()
        self.assertEqual(len(events), 2)
        self.assertEqual(len(events[-1]["waveform"]), 160)
        self.assertEqual(events[0]["level"], 0)
        self.assertGreater(events[1]["level"], .6)
        self.assertGreater(max(events[-1]["waveform"]), .5)
        self.assertEqual(events[-1]["seconds"], .5)

    def test_quiet_captured_input_still_registers_on_the_meter(self):
        events = []
        recorder = Recorder(self.store, events.append, threading.Event())
        recorder.note_id, recorder.rate = self.note, 16000
        recorder.frames.put(b"\x10\x00" * 4000)
        recorder.frames.put(None)
        recorder.write_loop()
        self.assertLess(events[0]["db"], -60)
        self.assertGreater(events[0]["level"], 0)
        self.assertGreater(max(events[0]["waveform"]), 0)
        self.assertEqual(self.store.note(self.note)["duration"], .25)

    def test_a_blocked_ui_pipe_does_not_block_audio_saves(self):
        code = """
from backend import Backend
from recorder import Recorder
import os, sys, threading, time
b=Backend(sys.argv[1],fake_engine=True)
b.emit({'event':'state','huge_payload':'x'*1000000})
time.sleep(.1)
n=b.store.create('Blocked UI test')
r=Recorder(b.store,b.emit,b.wake); r.note_id=n; r.rate=16000
t=threading.Thread(target=r.write_loop); t.start()
for _ in range(12): r.frames.put(b'\\x00\\x20'*4000)
r.frames.put(None);t.join(timeout=5)
if t.is_alive():os._exit(42)
assert b.store.note(n)['duration']==3
os._exit(0)
"""
        env = {**os.environ, "PYTHONPATH": str(Path(__file__).resolve().parents[1] / "worker")}
        process = subprocess.Popen([sys.executable, "-c", code, str(self.path)], env=env, stdout=subprocess.PIPE)
        try:
            self.assertEqual(process.wait(timeout=10), 0)
        finally:
            if process.poll() is None:
                process.kill()
                process.wait()
            process.stdout.close()


if __name__ == "__main__":
    unittest.main()
