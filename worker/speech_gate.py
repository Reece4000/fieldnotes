"""Local speech detection. Runs in the inference process, never the audio callback."""
from pathlib import Path
import numpy as np


class SpeechGate:
    def __init__(self):
        import onnxruntime as ort
        options = ort.SessionOptions()
        options.intra_op_num_threads = options.inter_op_num_threads = 1
        self.session = ort.InferenceSession(str(Path(__file__).parent / "models" / "silero_vad.onnx"),
                                           sess_options=options, providers=["CPUExecutionProvider"])

    def spans(self, audio, minimum_db=-44):
        """16 kHz float PCM -> padded speech spans in samples, with original timing."""
        state = np.zeros((2, 1, 128), dtype=np.float32)
        context = np.zeros((1, 64), dtype=np.float32)
        floor = 10 ** (minimum_db / 20)
        flags = []
        for offset in range(0, len(audio), 512):
            frame = audio[offset:offset + 512]
            frame = np.pad(frame, (0, 512 - len(frame))).reshape(1, 512)
            inputs = np.concatenate((context, frame), axis=1)
            probability, state = self.session.run(None, {"input": inputs, "state": state,
                                                         "sr": np.array(16000, dtype=np.int64)})
            context = inputs[:, -64:]
            rms = float(np.sqrt(np.mean(frame * frame)))
            flags.append(float(probability.item()) >= .65 and rms >= floor)
        # Bridge short syllable gaps, but require sustained evidence before
        # allowing ASR. A single noise impulse must not open the decoder.
        runs = []
        start = last = None
        evidence = 0
        for index, voice in enumerate(flags + [False] * 18):
            if voice:
                if start is None:
                    start, evidence = index, 0
                last = index
                evidence += 1
            elif start is not None and index - last >= 17:
                if evidence >= 4:
                    runs.append((max(0, start * 512 - 3200), min(len(audio), (last + 1) * 512 + 3200)))
                start = last = None
        merged = []
        for start, end in runs:
            if merged and start <= merged[-1][1]:
                merged[-1] = (merged[-1][0], end)
            else:
                merged.append((start, end))
        return merged
