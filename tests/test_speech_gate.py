"""Exercise the actual engine protocol; rejected audio must never reach ASR."""
import base64
import io
import json
from pathlib import Path
import sys
from types import SimpleNamespace
import subprocess
import tempfile
import unittest
from unittest.mock import patch
import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "worker"))
import engine


class GateTests(unittest.TestCase):
    def test_quiet_noise_is_never_decoded(self):
        from fermion._speech import backends
        class Decoder:
            calls = 0
            def transcribe_array_detailed(self, audio):
                self.calls += 1
                return SimpleNamespace(text="Imagined sentence.", words=[], truncated=False)
        decoder = Decoder()
        noise = np.random.default_rng(4).normal(0, .001, 16000 * 8)
        pcm = (noise * 32768).astype("<i2").tobytes()
        request = {"id": 1, "rate": 16000, "pcm": base64.b64encode(pcm).decode()}
        with patch.object(backends, "load", return_value=decoder), \
             patch("engine.sys.stdin", io.StringIO(json.dumps(request) + "\n")), \
             patch("engine.sys.stdout", new_callable=io.StringIO) as output:
            engine.main()
            reply = json.loads(output.getvalue().splitlines()[-1])
        self.assertEqual(reply["text"], "")
        self.assertEqual(decoder.calls, 1)  # only the model warmup

    def test_speech_detector_rejects_loud_noise_and_retains_speech_with_original_timing(self):
        from speech_gate import SpeechGate
        from scipy.signal import resample_poly
        from math import gcd
        import soundfile as sf
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "fixture.aiff"
            subprocess.run(["say", "-v", "Daniel", "-o", str(path), "This is a test recording."], check=True)
            speech, rate = sf.read(path, dtype="float32")
        speech = resample_poly(speech, 16000 // gcd(rate, 16000), rate // gcd(rate, 16000))
        gate = SpeechGate()
        noise = np.random.default_rng(4).normal(0, .02, 16000 * 8).astype(np.float32)
        self.assertEqual(gate.spans(noise), [])
        self.assertEqual(gate.spans(np.zeros(16000, dtype=np.float32)), [])
        self.assertEqual(gate.spans(speech * .003), [])
        offset = 16000 * 3
        spans = gate.spans(np.concatenate((np.zeros(offset, dtype=np.float32), speech, np.zeros(16000, dtype=np.float32))))
        self.assertEqual(len(spans), 1)
        self.assertGreaterEqual(spans[0][0], offset - 3200)
        self.assertGreater(spans[0][1], offset + len(speech) - 6000)


if __name__ == "__main__":
    unittest.main()
