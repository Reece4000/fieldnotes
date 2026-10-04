# Third-party components

- **Phonon-2**, Fermion Research: [model and attribution/NOTICE](https://huggingface.co/FermionResearch/Phonon-2). Model weights are CC BY 4.0, derived from NVIDIA's [Parakeet TDT 0.6B v3](https://huggingface.co/nvidia/parakeet-tdt-0.6b-v3). We use the model for local speech recognition without changing its weights.
- **fermion-research 0.2.7**: [source](https://github.com/fermionresearch/phonon), Apache 2.0. The adapter calls its internal speech API; its version is pinned because that API can change.
- **Silero VAD 6.2.3**, [official source](https://github.com/snakers4/silero-vad/tree/5cd7945676eb32225748052e2e6a0580e4686a08), MIT. The unmodified `silero_vad.onnx` model and its license are bundled in `worker/models/`; our NumPy ONNX adapter follows the upstream input/state protocol. Runs locally with [ONNX Runtime](https://github.com/microsoft/onnxruntime), MIT.
- **Qt 6**: [licensing](https://doc.qt.io/qt-6/licensing.html), dynamically linked from the Homebrew installation. The modules used here are available under LGPLv3/GPL/commercial terms. The local build script bundles Qt libraries for this machine; review redistribution obligations before distributing the app.
- **MLX / MLX Audio / MLX LM**: [MLX](https://github.com/ml-explore/mlx), [MLX Audio](https://github.com/Blaizzy/mlx-audio), [MLX LM](https://github.com/ml-explore/mlx-lm). Each retains its upstream license.
- **python-sounddevice / PortAudio**: [python-sounddevice](https://github.com/spatialaudio/python-sounddevice), [PortAudio](https://www.portaudio.com/license.html), MIT.
- Python, NumPy, SciPy, SoundFile/libsndfile, and other installed dependencies retain their own upstream licenses, included in the virtual environment's package metadata.

The model is cached separately by Fermion's verified downloader; it is not included in this repository or app bundle.
