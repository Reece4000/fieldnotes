---
name: Fieldnotes
description: A voice notebook as a flat, type-led instrument. A field for the notes, a band of the opposite tone for the recorder, in nine themes.
colors:
  ground: "#0c0d10"
  panel: "#16181c"
  cell: "#1f2227"
  ink: "#eceef2"
  muted: "#7d838f"
  dim: "#4a4f58"
  band: "#c6c8ce"
  band-ink: "#111216"
  band-muted: "#4d5159"
  band-key: "#aeb1b8"
  chip: "#121418"
  accent: "#34c6cc"
  amber: "#f0a33a"
  magenta: "#f2477f"
  record: "#e5483d"
  readout: "#e8fa42"
typography:
  section: { fontFamily: Geist, fontSize: "26px" }
  label: { fontFamily: Geist, fontSize: "13–14px" }
  value: { fontFamily: Geist Mono, fontSize: "11–12px" }
  menu: { fontFamily: Geist Mono, fontSize: "12px" }
  readout: { fontFamily: DSEG14 Modern, fontSize: "24–30px" }
layout:
  corners: "square everywhere"
  margin: "24"
  rail: "296"
---

# Design System: Fieldnotes

## North star

Fieldnotes is a voice notebook in the house instrument style of Macro OSC, Lodo and TapeTop. It is flat, square and led by type. The notes sit on a field above, and the recorder is the band across the foot of the window, because the recorder is the surface you play. The band always takes the opposite tone to the field: silver under a dark field, dark under a light one.

## Colour

Colour is data, and each colour has one meaning. The front matter shows the instrument theme. All themes live in `qml/ThemePalette.qml`, reached as `T.p.<token>` through `qml/Theme.js`. They are TapeTop's device themes, so the instruments share one vocabulary:

- **Light:** instrument light (the default), paper, studio and sand.
- **Dark:** instrument, graphite, night, carbon and lodo.

In each theme, the theme's track 4 is the amber role and track 2 the magenta role.

The colour meanings:

- **Accent (turquoise in instrument):** where the cursor is. A focused field or row floods with the accent and its ink turns to the accent's own ink. The note text is bare content, so it gets an accent frame instead.
- **Amber:** transcription work still to do (pending audio, the model loading).
- **Magenta:** something failed and needs you: needs retry, errors, the top of the level meter.
- **Red:** recording, and nothing else. The rec key floods red while recording.
- **Readout:** the clock, and nothing else. It is yellow-green in instrument. The readout window is the ground tone, so dark themes show a dark window on a silver band and light themes an LCD-like light window on a dark band.

Everything else is greyscale. The current choice inverts: an ink cell with ground-tone text.

## Type

- **Geist:** labels and note text. Section titles (notes, organise, trash) are 26px; the current one is ink, the others dim.
- **Geist Mono:** values, counts, dates, key legends and menus.
- **DSEG14 Modern:** the clock, with the unlit segments faintly behind.

Every label is lowercase. User content (note titles, category, workspace and device names) keeps its own case.

## Layout

1. **Header:** the section titles on the left; the workspace, and the engine status as a small square, on the right.
2. **Notes section:**
   - **Rail on the panel tone:** new note, search, categories, notes.
   - **Document on the ground:** title, location, copy, the editor and its footer.
3. **Organise section:** the categories rail and the note table.
4. **Silver band:** across the full width. It holds:
   - the readout and its status;
   - the rec and pause keys;
   - the live input waveform (the hero visual, on a dot grid) and the level meter;
   - input, filter and save-to.

There are no dividers, boxes, radii or shadows. Space and tone steps separate everything.

## Components

- **Keys** (`ActionButton`, `BandKey`): flat squares with their key legend in mono (⌘N, ⌘R).
- **Quiet keys:** bare words that light on hover.
- **Fields** (`FieldText`, `FieldCombo`): cells with a mono value; they flood turquoise while focused.
- **Slider** (`FieldSlider`): a label–value pair over a 6-unit track with a 2 × 12 tick.
- **Status squares:** 6–8px squares for state. Notes, the engine and toasts use them; no icons.

## Do and don't

- **Do** keep the recorder on the band and the clock in the readout.
- **Do** say a note's state as a word with its coloured square.
- **Don't** add icons, rounded corners, shadows, outlines, dividers or explanatory captions.
- **Don't** use red outside recording, or yellow-green outside the readout.
