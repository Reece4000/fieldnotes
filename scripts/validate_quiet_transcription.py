"""Real-model regression: quiet short notes through the capture journal and ASR."""
import json
from math import gcd
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import threading
import time

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "worker"))
from backend import Backend
from recorder import Recorder


def word_errors(reference, actual):
    expected = re.findall(r"[a-z]+", reference.lower())
    actual = re.findall(r"[a-z]+", re.sub(r"\[\d+:\d+:\d+\]", "", actual.lower()))
    costs = list(range(len(actual) + 1))
    for i, word in enumerate(expected, 1):
        following = [i]
        for j, other in enumerate(actual, 1):
            following.append(min(following[-1] + 1, costs[j] + 1, costs[j - 1] + (word != other)))
        costs = following
    return costs[-1] / len(expected)


def main():
    import numpy as np
    import soundfile as sf
    from scipy.signal import resample_poly
    phrase = "Test, test, testing. This is a test voice note."
    with tempfile.TemporaryDirectory(prefix="fieldnotes-quiet-validation-") as folder:
        folder = Path(folder)
        audio_file = folder / "speech.aiff"
        subprocess.run(["say", "-v", "Daniel", "-o", str(audio_file), phrase], check=True)
        speech, source_rate = sf.read(audio_file, dtype="float32")
        audio_file.unlink()
        backend = Backend(folder / "notes.sqlite3", emit=lambda _: None)
        try:
            for target_db, floor, rate in ((-62, -72, 16000), (-82, -90, 44100)):
                divisor = gcd(source_rate, rate)
                audio = resample_poly(speech, rate // divisor, source_rate // divisor)
                audio *= 10 ** (target_db / 20) / np.sqrt(np.mean(audio * audio))
                pcm = (np.clip(np.concatenate((np.zeros(rate * 14), audio, np.zeros(rate))), -1, 1) * 32767).astype("<i2")
                # Exercise the default for ordinary quiet recordings.
                note = backend.store.create() if floor == -72 else backend.store.create(voice_db=floor)
                assert backend.store.note(note)["voice_db"] == floor
                capture = Recorder(backend.store, lambda _: None, backend.wake)
                capture.note_id, capture.rate = note, rate
                writer = threading.Thread(target=capture.write_loop)
                writer.start()
                for offset in range(0, len(pcm), rate // 4):
                    capture.frames.put(pcm[offset:offset + rate // 4].tobytes())
                capture.frames.put(None)
                writer.join(timeout=20)
                assert not writer.is_alive() and not capture.fault, capture.fault
                backend.wake.set()
                deadline = time.monotonic() + 180
                while time.monotonic() < deadline:
                    counts = backend.store.counts(note)
                    if counts.get("error") or backend.engine_status == "error":
                        raise AssertionError(backend.engine_error)
                    if counts and set(counts) == {"done"}:
                        break
                    time.sleep(.1)
                body = backend.store.note(note)["body"]
                error_rate = word_errors(phrase, body)
                print(json.dumps({"speech_db": target_db, "floor": floor, "rate": rate,
                                  "transcript": body, "word_error_rate": error_rate}), flush=True)
                assert error_rate <= .2, "Opening words or most of the phrase were lost: " + body
                assert "[00:00:14]" in body, "Speech timestamp moved: " + body
                assert backend.store.db.execute("SELECT COUNT(*) FROM blocks").fetchone()[0] == 0
        finally:
            backend.shutdown()


if __name__ == "__main__":
    main()
