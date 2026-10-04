"""Isolated Phonon-2 process. PCM enters through stdin; no audio files are created."""
import base64
import contextlib
import json
import math
import os
import sys


def emit(value):
    print(json.dumps(value, ensure_ascii=False), flush=True)


def main():
    # Keep the protocol uncontaminated by dependency progress output.
    with contextlib.redirect_stdout(sys.stderr):
        import numpy as np
        from scipy.signal import resample_poly
        from fermion.transcribe import _resolve
        from fermion._speech import backends, fetch
        from speech_gate import SpeechGate, normalise_speech
        gate = SpeechGate()
        repo, key, pin, local = _resolve("phonon-2")
        path = local or fetch.ensure(repo, key, pin)
        # Packed weights save memory. The package default densifies the encoder.
        os.environ.setdefault("FERMION_P2_FAST", "tdt16")
        speech = backends.load("mlx", path, profile=key, backend=pin["backend"], quiet=True)
        speech.transcribe_array_detailed(np.zeros(16000, dtype=np.float32))
    emit({"event": "ready"})
    for line in sys.stdin:
        try:
            request = json.loads(line)
            with contextlib.redirect_stdout(sys.stderr):
                audio = np.frombuffer(base64.b64decode(request["pcm"]), dtype="<i2").astype(np.float32) / 32768
                rate = int(request["rate"])
                if rate != 16000:
                    divisor = math.gcd(rate, 16000)
                    audio = resample_poly(audio, 16000 // divisor, rate // divisor)
                words, texts = [], []
                for start, end in gate.spans(audio, request.get("voiceDb", -72)):
                    result = speech.transcribe_array_detailed(normalise_speech(audio[start:end]))
                    if result.truncated:
                        raise RuntimeError("The model returned an incomplete segment")
                    if result.text.strip() and not result.words:
                        raise RuntimeError("Word timestamps were missing. Audio retained for retry.")
                    texts.append(result.text.strip())
                    words.extend({**word, "start": word["start"] + start / 16000,
                                  "end": word["end"] + start / 16000} for word in result.words)
            emit({"event": "result", "id": request["id"], "text": " ".join(texts), "words": words})
        except Exception as exc:
            emit({"event": "error", "message": str(exc)})


if __name__ == "__main__":
    try:
        main()
    except BaseException as exc:
        emit({"event": "error", "message": str(exc)})
        sys.exit(1)
