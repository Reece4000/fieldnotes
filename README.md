# Fieldnotes

Fieldnotes is a lightweight QtQuick desktop notebook for speaking through debugging runs and HCI tests, then organising and editing the resulting transcripts. It records the microphone and transcribes locally with Phonon-2 on Apple silicon Macs running **macOS Sequoia 15 or later**.

The app grew out of a recurring problem: spending many minutes recording a debugging session in an IDE, only to lose the recording or transcript. Capturing the session reliably comes first; transcription and the interface run separately from audio capture.

## Requirements and current behaviour

| Original requirement | Current implementation |
| --- | --- |
| Lightweight QtQuick app; JUCE unnecessary | Native C++/QtQuick UI, without JUCE. The separate Python/MLX speech runtime is larger than the UI. |
| Reasonably accurate transcription on Sequoia | Local Phonon-2 transcription for English on Apple silicon. Speech detection and an adjustable voice-level filter reduce silence/noise hallucinations. Technical vocabulary and recognition errors still need review. |
| Easy organisation and copying | Workspaces, categories, searchable note lists, first-sentence titles, small copy icons on sidebar rows, and copy/export actions for the open note. |
| Easy editing of recorded notes | Editable transcripts and titles with automatic saving. A note becomes editable when its recording and queued transcription finish. |
| Long recordings and transcription | No application time limit. Audio is split at pauses or into chunks of up to 20 seconds, with overlap and timestamp-based deduplication. |
| No WAVs retained; discard audio after transcription | No WAV files are created during recording. Temporary recovery PCM is stored in SQLite until its transcript is committed, then deleted in the same transaction. |
| Reliability during many-minute sessions | Capture has its own writer thread and durable recovery journal. Saved chunks resume after interruption; failed chunks retain audio for retry. Recovery cannot restore samples that never reached disk. |
| See transcription while recording, if practical | Completed sections arrive incrementally while capture continues. This is chunked transcription, not immediate word-by-word text; latency depends on speech pauses and inference speed. |

Microphone-only capture is intentional for this first version. System audio and speaker diarization are outside its scope.

## Use

Open `build/Fieldnotes.app` (or the installed app in Applications).

- **Record a session** / **⌘R** starts a new note. The same button/shortcut stops it.
- **Pause / Resume** / **⌘⇧P** pauses capture without losing the session.
- Transcribed sections arrive during recording, normally after a pause once 2 seconds have accumulated, or every 20 seconds during continuous speech. This is incremental transcription, not a changing word-by-word hypothesis.
- Notes take their title from the first transcript sentence. You can rename them manually; a manual name is preserved when text changes. Use the sidebar + buttons to create workspaces and categories. Move notes with the two dropdowns under the title. Search covers titles, categories and note text within the current workspace; note rows load in pages of 100.
- Finished transcripts are directly editable. Title/text edits autosave after 750 ms without typing; switching notes or closing the app flushes pending edits immediately. While a note is recording or has active/pending transcription, its text stays read-only to protect it from concurrent changes; other notes remain editable.
- **Copy** / **⌘⇧C** copies text without timestamps. Each sidebar note row also has a small copy icon that copies that note without opening it. The note menu offers copying with timestamps.
- **Export** / **⌘E** saves Markdown or plain text with timestamps.
- **⌘N** creates a text note. **⌘F** searches the open transcript; **⌘⇧F** searches the workspace. Use the arrows beside transcript search to move between highlighted matches.
- Deleted notes go to **Trash**, with immediate undo and later restoration from the note menu.

The microphone permission is requested only on the first recording. Select an input device in the recording console. If denied, enable Fieldnotes in System Settings → Privacy & Security → Microphone.

## Recording feedback and speech filtering

A small tape reel beside the input meter rotates during capture and freezes when paused or inactive. A rolling four-second waveform and dBFS input level update from audio that has reached the recovery journal, independently of transcription. Copy confirms with an animated tick in a reserved space beside the button. Status messages and errors occupy a fixed strip and never change the document layout. Scroll views stop at their bounds without overshoot; the sidebar keeps its width when the window resizes.

Silero VAD runs locally in the isolated inference process before Phonon-2. Only sustained speech spans above the minimum voice level are decoded; quiet/noise spans complete without transcript text and their recovery PCM is erased. Cropped speech retains its original timestamps. **Voice filter** adjusts the minimum level for new recordings (default −44 dBFS). Move towards Nearby voices to suppress faint background speech; towards Quiet voices if your own speech is being missed. This is a speech/volume gate, not speaker identification: loud background speech may still be transcribed, and no gate eliminates every recognition error. macOS Reduce Motion and the app's Reduce motion checkbox freeze the reel and remove tick scaling.

## Recovery and audio lifecycle

There is no application recording-duration cap. Microphone capture is independent of model inference and the Qt UI. Captured PCM is journaled into a private SQLite database in roughly 250 ms blocks. Short chunks are cut at pauses or a 20 second limit, with a 750 ms overlap and word-timestamp deduplication at boundaries.

No WAV files are created. **Temporary recovery PCM remains on disk until the corresponding transcript is successfully committed.** Transcript insertion, chunk completion, and audio deletion occur in one SQLite transaction. `synchronous=FULL`, macOS `fullfsync`, and `secure_delete` are enabled; DELETE journals avoid retaining deleted audio in a WAL file. The database can retain allocated space after deleting audio, but the deleted PCM pages are zeroed by SQLite. This is not a forensic-erasure guarantee for filesystem snapshots or storage hardware.

Closing the app stops recording and flushes captured audio. A crash or forced termination recovers saved chunks on the next launch. An interrupted session is labeled as recovered. A transcription failure retains audio and exposes **Retry**. The app prevents idle sleep while recording and visibly stops if the input stalls or reports an overflow.

Manual text edits are batched after a 750 ms typing pause. Normal note switches and app closure flush them immediately; forced termination can lose edits still within that debounce window. Audio journaling runs independently of this text-edit timer.

Recovery cannot reconstruct samples that never reached storage: an abrupt backend/OS crash can lose the newest callback or uncommitted buffers (normally around a quarter-second, longer during a disk stall). Disk exhaustion, hardware failure, lid closure, or disconnecting the microphone can interrupt capture. An already saved transcript survives transcription failures. No artificial time limit does not mean unlimited disk space.

Data: `~/Library/Application Support/Fieldnotes/notes.sqlite3`. Model diagnostics: `engine.log` in the same folder. Audio/transcripts are not logged. Setup downloads public dependencies; the first launch downloads the 164 MB model from its publisher if it is not cached. Recording and transcription use no network once the model is available. The native UI is small; the separate Python/MLX speech runtime and its dependencies are substantially larger.

## Read notes from models and automation

Use `./scripts/notes catalog` to discover workspaces/categories, then `./scripts/notes search --workspace Personal --category 'HCI tests' --text 'cursor' --all --format jsonl`. This standard-library-only reader opens SQLite read-only and returns full edited transcripts. It releases database locks before output, excludes Trash by default, and exposes incomplete-transcript flags. No audio or transcription runtime is loaded. The installed app bundles the reader too. See [read-only access](docs/READ_ONLY_ACCESS.md) for the schema, commands, and direct SQL view.

## Build

Dependencies: Qt 6.9+ (developed with Homebrew Qt 6.11), CMake 3.24+, Python 3.12, and the pinned runtime packages in `requirements.txt`.

```sh
./scripts/setup.sh
```

For an existing setup:

```sh
./scripts/build.sh
open build/Fieldnotes.app
```

The app bundles its Qt libraries and worker scripts. It references **this checkout's `.venv`** in `Contents/Resources/runtime.json`, so keep the checkout and virtual environment in place. It is a local development install, ad-hoc signed, not a notarized distributable. `FIELDNOTES_PYTHON` overrides the Python path; `FIELDNOTES_DATA_DIR` isolates data for testing.

## Verify

For native UI changes, also check title-bar dragging, resizing to the minimum
window size, and copying a sidebar note while a different transcript is open.
Sidebar copying should leave selection unchanged and show its tick in place.

```sh
ctest --test-dir build --output-on-failure
.venv/bin/python -m unittest discover -s tests -v
.venv/bin/python scripts/validate_transcription.py
```

The native controller tests verify edit batching after a 750 ms quiet period, combined title/body updates, immediate flushing on note switches and shutdown, immediate organisation changes, and preservation of newer text when an older save acknowledgement arrives.

The unit suite tests process-crash recovery, transaction rollback, audio deletion, retry ordering, sample-aligned overlaps, journal-driven waveform telemetry, quiet/noise rejection through the actual engine protocol, faint/normal speech detection, legacy database migration, automatic/manual titles, workspaces/categories, paged search, persistent edits/trash, and a simulated three-minute recording. The opt-in integration check synthesizes over three minutes of speech with macOS `say`, passes it through the actual chunk writer and local model, checks repeated content survived, and verifies all temporary recovery audio was deleted. Its temporary audio and database are removed automatically.

## Implementation

`src/` is the native C++ QtQuick bridge; `qml/` is the notebook UI. `worker/backend.py` owns notes and recording; `worker/recorder.py` journals audio on its own thread. A separate `worker/engine.py` process loads Phonon-2 once and receives in-memory PCM through private pipes. There is no listening server port.

Transcription is English only in this version. Phonon-2 is reasonably accurate on general English but technical names, accents, overlapping voices, and distant microphones still need review. Speaker diarization and system-audio capture are outside this version.

Fieldnotes source is MIT licensed. See [THIRD_PARTY.md](THIRD_PARTY.md) for model/runtime attribution and licensing.
