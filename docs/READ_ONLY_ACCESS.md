# Read Fieldnotes notes from an LLM or automation

Use the standard-library Python reader. It opens SQLite with `mode=ro` and
`query_only=ON`; it cannot create or migrate a database, edit notes, start
recording or launch transcription. It does not load audio or ML dependencies.
The app can remain open. Pages are fetched and the connection closed before
output, so a slow pipe/model consumer does not keep a recording writer locked.

From this checkout:

```sh
./scripts/notes schema
./scripts/notes catalog
./scripts/notes search --workspace Personal --category 'HCI tests' --text 'cursor' --all --format jsonl
./scripts/notes search --workspace Personal --unfiled --all --format jsonl
./scripts/notes search --since 2026-10-01 --until 2026-11-01 --all
./scripts/notes show 'NOTE-UUID'
```

From the installed app, without the checkout or virtual environment:

```sh
python3 /Applications/Fieldnotes.app/Contents/Resources/worker/notes_reader.py catalog
python3 /Applications/Fieldnotes.app/Contents/Resources/worker/notes_reader.py search --workspace Personal --category 'Debugging runs' --all --format jsonl
```

Python 3.9+ is sufficient. The default database is
`~/Library/Application Support/Fieldnotes/notes.sqlite3`. Use
`--database '/absolute/path/notes.sqlite3'` **before** the command to select
another database. `FIELDNOTES_DATA_DIR` also selects the data folder.

`catalog` gives workspace names/IDs, category names and active note counts,
including empty categories and the Unfiled group (`category: ""`). Names can be
supplied verbatim; a workspace UUID also works. `search` returns **full edited
transcripts**, not snippets, ordered by creation date. The default limit is 100;
use `--all` for a complete category. Search text is a literal substring, so `%`
and `_` have no wildcard meaning. SQLite LIKE is case-insensitive for ASCII,
and case-sensitive for non-ASCII characters. Date filters use creation time,
with inclusive `--since` and exclusive `--until`; dates without a zone mean UTC.

JSON has a `fieldnotes.notes/v1` envelope. JSONL has one note object per line.
`schema` documents every field and needs no database. Stable note IDs connect
results to the app. `transcript` is the authoritative saved text, including user
edits; do not use internal segment text as a substitute. `[HH:MM:SS]` markers are
relative to the recording, while `created_at`/`updated_at` are UTC ISO timestamps.
`unfinished_chunks`/`failed_chunks` identify potentially incomplete transcripts.
Trash is excluded unless `--include-trash` is supplied. No audio is exposed.

Each page is a short consistent read. A long `--all` run may see edits between
pages; it is not a frozen snapshot. Errors go to stderr with a nonzero exit code;
consumers should only accept an export that exits successfully. Missing databases
are never created. A busy database can be retried after a short pause.

## Direct SQLite access

The app publishes the `notes_readonly` view on startup. It includes the same
fields and joins workspace names to notes; **it includes Trash**, so filter
`trashed=0` unless explicitly asked to inspect deleted notes. The reader also
works with earlier Fieldnotes databases that lack the view.

```sh
sqlite3 -readonly "$HOME/Library/Application Support/Fieldnotes/notes.sqlite3" \
  "SELECT id,title,workspace,category,transcript FROM notes_readonly WHERE trashed=0 AND workspace='Personal' AND category='HCI tests';"
```

For agents: use the reader or a read-only SQLite connection. Never import
`worker/store.py` for read access: that class owns schema migration and writes.
Never change journal settings or use `immutable=1` on the live database.
