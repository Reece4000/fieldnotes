# Fieldnotes

Fieldnotes is a QtQuick desktop app for recording spoken notes and transcribing them locally. It supports long debugging sessions, HCI tests and other work where recording observations is easier than typing them.

The project focuses on reliable long-form capture, editable transcripts and organised notes. Microphone capture runs independently of the interface and transcription engine, with audio saved to a recovery journal as it arrives.

## Features

- Local English transcription with Phonon-2 on Apple silicon Macs running macOS Sequoia 15 or later.
- Recordings without an application duration limit, split into short chunks for transcription.
- Incremental transcripts, a live waveform and microphone level display.
- Workspaces, categories and searchable notes with automatic first-sentence titles.
- A dedicated Organise view with previews, drag-and-drop filing, bulk moves and an editor drawer.
- A custom Markdown notes editor with formatting tools, a preview toggle, focused writing and automatic saving.
- Clipboard copying, Markdown/text export, context menus and recoverable Trash.
- Nine themes, light and dark, shared with TapeTop. See [DESIGN.md](DESIGN.md) for the design system.
- Recovery of saved audio after interruption, with retry for failed transcription.
- Automatic removal of temporary audio after its transcript is committed.
- Read-only access to saved notes for scripts and LLM tools.

System-audio capture and speaker diarization are not supported. Transcription accuracy varies with vocabulary, accents, microphone placement and background speech.

## Build and run

Requires macOS Sequoia 15 or later on Apple silicon, Qt 6.9+, CMake 3.24+ and Python 3.12. Runtime dependencies are pinned in [requirements.txt](requirements.txt).

With Homebrew installed, set up dependencies and build:

```sh
./scripts/setup.sh
open build/Fieldnotes.app
```

To rebuild an existing setup:

```sh
./scripts/build.sh
```

The app bundles Qt libraries and worker scripts, but references the checkout's `.venv` through `Contents/Resources/runtime.json`. Keep the checkout and virtual environment in place. Builds are ad-hoc signed development bundles, not notarized distributables.

Use `scripts/build.sh` for runnable bundles: after linking, Qt's deployment step must refresh the executable's library paths before signing. A bare `cmake --build build` can leave a previously packaged app loading both bundled and Homebrew Qt libraries. The build script verifies the signature and briefly launches the finished app with temporary test data to catch packaging failures. Run that launch check separately with `python3 scripts/check_app.py`.

The model downloads on first launch if it is not cached. Recording and transcription run offline once the model is available. Microphone permission is requested on the first recording; permissions can be changed in System Settings → Privacy & Security → Microphone.

`FIELDNOTES_PYTHON` overrides the runtime Python path. `FIELDNOTES_DATA_DIR` selects a separate data folder for testing.

## Using Fieldnotes

| Action | Shortcut |
| --- | --- |
| Start or stop recording | ⌘R |
| Pause or resume recording | ⌘⇧P |
| Create a text note | ⌘N |
| Copy the open transcript without timestamps | ⌘⇧C |
| Export the open note | ⌘E |
| Find in the open note | ⌘F |
| Bold / italic / insert link in the editor | ⌘B / ⌘I / ⌘K |
| Toggle Write / Markdown preview while editing | ⌘⇧M |
| Search the workspace | ⌘⇧F |

Choose a microphone and recording destination in the recording pane. Transcribed sections appear after speech pauses or approximately every 20 seconds during continuous speech; latency depends on inference speed.

Use the sidebar to create workspaces and categories. Notes are titled from their first transcript sentence unless manually renamed. Click the workspace / category location beside a note's title to move it; the popover labels both levels. Workspace search includes titles, categories and transcript text.

Click **Select** above the sidebar notes to choose several notes, then **Move…** to file them together. You can also use ⌘-click to toggle notes, Shift-click to select a range, or ⌘A while the note list has focus. Right-click any note for **Move to category…**. Selection clears when changing workspace, category or search; the sidebar's Select all applies to loaded notes and labels that limit when more are available.

The window has three sections: **notes**, **organise** and **trash** (⌘1, ⌘2, ⌘3, or click the titles). The recorder runs along the foot of the window in every section: the clock, **rec** (⌘R) and **pause** (⌘⇧P), the live input, and the microphone, voice filter and destination.

Open **organise** for a full collection view, including notes beyond the sidebar's first page. The workspace picker is labelled explicitly; categories stay in a separate sidebar while the notes scroll. Click a category to filter, or drag a note or selected group onto it to move them. Click a note to open its editor. Use **Select**, ⌘-click or Shift-click for multi-selection, then **Move…** or drag to a category. Search full transcripts and use **View** for sorting and filters. Category menus offer rename, reorder and remove; removing a category makes its notes Unfiled, including notes in Trash, without deleting them. Recording can continue while organising.

Click **new note** (⌘N) to type a note in the focused writing view. The **Write** tab keeps the original Markdown source; **Preview** renders headings, emphasis, lists, task lists, links, tables and code blocks without modifying the saved text. The formatting toolbar includes bold, italic, headings, lists and links, with every option also available under **Format** in compact windows. Formatting supports undo/redo; the editor also includes Find and a word count. The same editor is available in the Organise drawer. **Focus** hides the recorder and **Recorder** returns it, and an active recording keeps Pause and Stop available while writing.

Completed transcripts are editable. Text and title changes save after a 750 ms typing pause; switching notes or closing the app flushes pending edits. A transcript stays read-only while its recording or transcription is active.

Each note row shows **copy** when hovered or open. Right-click a note for copying, renaming, retrying unfinished transcription or moving it to Trash. A focused note row supports Delete/Backspace and Shift+F10; finished notes can also be dragged onto the **trash** title. Deleted notes can be restored through Undo or from Trash. Text editors provide standard right-click editing menus.

Copy omits timestamps by default; the note menu offers copying with timestamps. Export (in the note’s More menu, or ⌘E) preserves timestamps in Markdown or plain text.

### Voice filter

Silero VAD detects speech before transcription. The voice filter applies a minimum captured level, defaulting to −72 dBFS and adjustable down to −90 dBFS. Lower the threshold if quiet speech is missed; raise it to suppress distant voices. This filter does not identify speakers, so louder background speech may still be transcribed.

Quiet audio is amplified for inference while the filter and input meter use the original captured level. Speech timestamps retain their positions within the recording. Set the filter on the recorder or in **Settings** (⌘,).

### Themes

Choose a theme in **Settings** (⌘,) or **View → Theme**. Instrument light is the default; instrument, graphite, night, carbon and lodo are dark, and paper, studio and sand are light. Native menus, dialogs and the title bar follow the theme's appearance.

## Storage and recovery

Notes are stored in `~/Library/Application Support/Fieldnotes/notes.sqlite3`. Diagnostics are written to `engine.log` in the same folder; audio and transcripts are not logged.

Captured PCM is journaled in roughly 250 ms blocks. Transcription chunks use a pause boundary or approximately 20 seconds of audio, with a 750 ms overlap and word-timestamp deduplication.

No WAV files are created during recording. Temporary recovery audio remains in SQLite until its transcript is committed, then is deleted in the same transaction. Failed or interrupted chunks retain their audio for retry. SQLite uses `synchronous=FULL`, macOS `fullfsync` and `secure_delete`; this does not guarantee removal from filesystem snapshots or storage-device backups.

Stop freezes recording feedback immediately while queued audio is saved and the microphone closes. If native device closure hangs, the service restarts after the journal is sealed and resumes pending transcription. Saved chunks also recover after a crash or forced termination.

Recovery cannot restore audio that never reached storage. Abrupt failure can lose recent uncommitted buffers, and forced termination can lose text edits still inside the save debounce window. Available disk space and microphone/device failures can interrupt recording.

## Read-only access

The standard-library reader searches full saved transcripts without loading the audio or model runtime:

```sh
./scripts/notes catalog
./scripts/notes search --workspace Personal --category 'HCI tests' --text 'cursor' --all --format jsonl
```

It opens the database read-only, excludes Trash by default and reports incomplete transcripts. The reader is also bundled in the app. See [read-only access](docs/READ_ONLY_ACCESS.md) for commands, output fields and the SQLite view.

## Development and verification

`src/` contains the C++ QtQuick bridge and platform integration; `qml/` contains the interface. `worker/backend.py` manages notes and recording, and `worker/recorder.py` writes the capture journal. A separate `worker/engine.py` process loads Phonon-2 and receives PCM through private pipes. No server port is opened.

Run the native controller and Python tests after building:

```sh
ctest --test-dir build --output-on-failure
.venv/bin/python -m unittest discover -s tests -v
```

Optional integration checks exercise the capture journal and local model with synthesized speech:

```sh
.venv/bin/python scripts/validate_transcription.py
.venv/bin/python scripts/validate_quiet_transcription.py
```

Coverage includes recording recovery, hung device closure, transactional audio deletion, chunk overlap, quiet-speech detection, edit batching, note organisation and read-only access. Integration checks verify long and quiet recordings, timestamps and audio cleanup. For UI changes, also check minimum-window sizing, title-bar dragging, recording feedback and sidebar actions without changing another open note.

## License

Fieldnotes source is MIT licensed. See [THIRD_PARTY.md](THIRD_PARTY.md) for model and runtime attribution and licensing.
