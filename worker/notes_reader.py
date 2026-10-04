#!/usr/bin/env python3
"""Fieldnotes' standard-library-only, read-only interface for people and agents."""
import argparse
from contextlib import contextmanager
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import sqlite3
import sys

FORMAT = "fieldnotes.notes/v1"
DEFAULT_DATABASE = Path(os.environ.get("FIELDNOTES_DATA_DIR", str(Path.home() / "Library/Application Support/Fieldnotes"))) / "notes.sqlite3"
# Kept here so the app can publish the same SQL view without importing its
# writable Store in this reader. body (including user edits) is authoritative.
VIEW_SQL = """
SELECT n.id, n.title, w.id AS workspace_id, w.name AS workspace,
       n.collection AS category, n.body AS transcript,
       strftime('%Y-%m-%dT%H:%M:%fZ', n.created, 'unixepoch') AS created_at,
       strftime('%Y-%m-%dT%H:%M:%fZ', n.updated, 'unixepoch') AS updated_at,
       n.duration AS duration_seconds, n.status,
       n.deleted AS trashed, n.auto_title AS automatic_title,
       (SELECT count(*) FROM segments s WHERE s.note_id=n.id AND s.state!='done') AS unfinished_chunks,
       (SELECT count(*) FROM segments s WHERE s.note_id=n.id AND s.state='error') AS failed_chunks,
       n.created AS created_epoch
FROM notes n JOIN workspaces w ON w.id=n.workspace
"""
SCHEMA = {
    "format": FORMAT,
    "access": "read-only; no audio, inference dependencies, or app process required",
    "database": str(DEFAULT_DATABASE),
    "sqlite_view": "notes_readonly",
    "commands": ["catalog", "search", "show", "schema"],
    "note_fields": {
        "id": "Stable UUID", "title": "First sentence unless manually renamed",
        "workspace_id": "Stable workspace ID", "workspace": "Workspace name",
        "category": "Category name; empty string means Unfiled",
        "transcript": "Authoritative editable text; [HH:MM:SS] markers are recording-relative",
        "created_at": "UTC ISO 8601", "updated_at": "UTC ISO 8601",
        "duration_seconds": "Captured duration in seconds", "status": "ready, recording, paused, or interrupted",
        "trashed": "Boolean; excluded by default", "automatic_title": "Boolean",
        "unfinished_chunks": "Includes failed chunks; transcript may be partial",
        "failed_chunks": "Audio awaiting retry", "created_epoch": "Unix seconds; pagination ordering",
    },
    "ordering": "created_epoch descending, then id descending",
    "consistency": "Each page is a short read. --all may observe edits between pages; it is not a frozen snapshot.",
}

@contextmanager
def connection(path):
    # mode=ro also prevents accidentally creating a missing database. Do not use
    # immutable=1: the live app changes this file. Never set journal pragmas.
    db = sqlite3.connect(Path(path).expanduser().resolve().as_uri() + "?mode=ro", uri=True, timeout=2)
    db.row_factory = sqlite3.Row
    try:
        db.execute("PRAGMA query_only=ON")
        yield db
    finally:
        db.close()


def literal_like(text):
    return "%" + text.replace("\\", "\\\\").replace("%", "\\%").replace("_", "\\_") + "%"


def note_dict(row):
    result = dict(row)
    result["trashed"] = bool(result["trashed"])
    result["automatic_title"] = bool(result["automatic_title"])
    return result


def notes(path, *, workspace=None, category=None, text="", include_trash=False,
          since=None, until=None, limit=100, note_id=None):
    """Yield after closing each read connection, so slow consumers hold no locks."""
    clauses, values = [], []
    if not include_trash:
        clauses.append("trashed=0")
    if workspace is not None:
        clauses.append("(workspace_id=? OR workspace=? COLLATE NOCASE)")
        values.extend([workspace, workspace])
    if category is not None:
        clauses.append("category=? COLLATE NOCASE")
        values.append(category)
    if text:
        clauses.append("(title LIKE ? ESCAPE '\\' OR transcript LIKE ? ESCAPE '\\' OR category LIKE ? ESCAPE '\\')")
        values.extend([literal_like(text)] * 3)
    if since is not None:
        clauses.append("created_epoch>=?"); values.append(since)
    if until is not None:
        clauses.append("created_epoch<?"); values.append(until)
    if note_id:
        clauses.append("id=?"); values.append(note_id)
    cursor = None
    yielded = 0
    while limit is None or yielded < limit:
        page_clauses = clauses[:]
        page_values = values[:]
        if cursor:
            page_clauses.append("(created_epoch<? OR (created_epoch=? AND id<?))")
            page_values.extend([cursor[0], cursor[0], cursor[1]])
        amount = min(100, limit - yielded) if limit is not None else 100
        query = "SELECT * FROM (" + VIEW_SQL + ")"
        if page_clauses:
            query += " WHERE " + " AND ".join(page_clauses)
        query += " ORDER BY created_epoch DESC,id DESC LIMIT ?"
        with connection(path) as db:
            rows = db.execute(query, page_values + [amount]).fetchall()
        if not rows:
            return
        cursor = (rows[-1]["created_epoch"], rows[-1]["id"])
        for row in rows:
            yielded += 1
            yield note_dict(row)
        if len(rows) < amount:
            return


def catalog(path):
    with connection(path) as db:
        workspaces = [dict(row) for row in db.execute("SELECT id,name FROM workspaces ORDER BY name COLLATE NOCASE").fetchall()]
        categories = [dict(row) for row in db.execute("""
            SELECT w.id AS workspace_id,w.name AS workspace,c.name AS category,
                   (SELECT count(*) FROM notes n WHERE n.workspace=w.id AND n.collection=c.name AND n.deleted=0) AS notes
            FROM workspaces w JOIN categories c ON c.workspace=w.id
            UNION ALL SELECT w.id,w.name,'',
                   (SELECT count(*) FROM notes n WHERE n.workspace=w.id AND n.collection='' AND n.deleted=0)
            FROM workspaces w ORDER BY workspace,category
        """).fetchall()]
    return {"format": FORMAT, "workspaces": workspaces, "categories": categories}


def timestamp(value):
    try:
        result = datetime.fromisoformat(value.replace("Z", "+00:00"))
        return result.replace(tzinfo=timezone.utc).timestamp() if result.tzinfo is None else result.timestamp()
    except ValueError:
        raise argparse.ArgumentTypeError("Use an ISO date or timestamp, e.g. 2026-10-04 or 2026-10-04T12:00:00Z")


def positive(value):
    result = int(value)
    if result < 1:
        raise argparse.ArgumentTypeError("Must be greater than zero")
    return result


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--database", type=Path, default=DEFAULT_DATABASE)
    sub = parser.add_subparsers(dest="command", required=True)
    sub.add_parser("schema", help="Describe the machine-readable format; needs no database")
    sub.add_parser("catalog", help="List workspaces and categories, including empty categories")
    search = sub.add_parser("search", help="Read matching notes with their full edited transcripts")
    search.add_argument("--workspace", help="Workspace name or ID")
    category = search.add_mutually_exclusive_group()
    category.add_argument("--category")
    category.add_argument("--unfiled", action="store_true")
    search.add_argument("--text", default="", help="Literal substring in title, transcript or category (SQLite LIKE casing)")
    search.add_argument("--since", type=timestamp, help="Inclusive creation date, UTC if no zone")
    search.add_argument("--until", type=timestamp, help="Exclusive creation date, UTC if no zone")
    amount = search.add_mutually_exclusive_group()
    amount.add_argument("--limit", type=positive, default=100)
    amount.add_argument("--all", action="store_true", help="Read every matching note in short pages")
    show = sub.add_parser("show", help="Read a note by stable UUID")
    show.add_argument("id")
    for command in (search, show):
        command.add_argument("--include-trash", action="store_true")
        command.add_argument("--format", choices=["json", "jsonl"], default="json")
    args = parser.parse_args(argv)
    try:
        if args.command == "schema":
            print(json.dumps(SCHEMA, ensure_ascii=False, indent=2)); return 0
        if args.command == "catalog":
            print(json.dumps(catalog(args.database), ensure_ascii=False, indent=2)); return 0
        if args.command == "show":
            rows = list(notes(args.database, note_id=args.id, limit=1, include_trash=args.include_trash))
            if not rows:
                print("Note not found (Trash is excluded unless --include-trash).", file=sys.stderr); return 1
            print(json.dumps(rows[0], ensure_ascii=False, indent=2 if args.format == "json" else None)); return 0
        rows = notes(args.database, workspace=args.workspace, category="" if args.unfiled else args.category,
                     text=args.text, include_trash=args.include_trash, since=args.since, until=args.until,
                     limit=None if args.all else args.limit)
        if args.format == "jsonl":
            for row in rows:
                print(json.dumps(row, ensure_ascii=False))
        else:
            # Stream the envelope too; do not collect every long transcript.
            print('{"format": ' + json.dumps(FORMAT) + ', "notes": [')
            first = True
            for row in rows:
                if not first:
                    print(",")
                print(json.dumps(row, ensure_ascii=False), end="")
                first = False
            print("\n]}")
        return 0
    except (sqlite3.Error, OSError) as error:
        print("Cannot read Fieldnotes database: " + str(error), file=sys.stderr)
        return 2


if __name__ == "__main__":
    try:
        sys.exit(main())
    except BrokenPipeError:
        sys.exit(0)
