"""Exercise the real service loop with a hung device, without microphone access."""
from pathlib import Path
import sys
import threading

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "worker"))
import backend


class HungCloseBackend(backend.Backend):
    def __init__(self, path):
        super().__init__(path, fake_engine=True)
        # Keep inference in flight so restart must preserve its recovery PCM.
        self.store.complete = lambda *args, **kwargs: threading.Event().wait(30)
        recorder = self.recorder
        class Device:
            def stop(self):
                # Advance the watchdog clock instead of spending eight seconds.
                recorder.stop_started -= 9
                threading.Event().wait(30)
            def close(self):
                pass
        note = self.store.create("Hung device test")
        recorder.note_id, recorder.rate, recorder.stream = note, 16000, Device()
        self.store.update(note, status="recording")
        recorder.thread = threading.Thread(target=recorder.write_loop, daemon=True)
        recorder.thread.start()
        recorder.frames.put(b"\x00\x20" * 4000)


backend.Backend = HungCloseBackend
raise SystemExit(backend.main())
