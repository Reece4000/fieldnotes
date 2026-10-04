"""One durable transaction commits the transcript and erases its recovery audio."""
import os
import re
from pathlib import Path
import sqlite3
import threading
import time
import uuid


def timestamp(seconds):
    seconds = int(seconds)
    return f"{seconds // 3600:02d}:{seconds // 60 % 60:02d}:{seconds % 60:02d}"


def first_sentence(body):
    text = re.sub(r"\[\d+:\d+:\d+\]\s*", "", body).strip()
    text = re.sub(r"\s+", " ", text)
    match = re.search(r"[.!?](?=\s|$)", text)
    return text[:match.end()] if match else text


class Store:
    def __init__(self, path):
        path = Path(path)
        path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
        self.lock = threading.RLock()
        self.db = sqlite3.connect(path, check_same_thread=False, timeout=10)
        os.chmod(path, 0o600)
        self.db.row_factory = sqlite3.Row
        # DELETE journals leave no WAL containing deleted audio. FULL fsync and
        # secure_delete apply to recovery PCM and ordinary note transactions.
        self.db.executescript("""
          PRAGMA journal_mode=DELETE;
          PRAGMA synchronous=FULL;
          PRAGMA fullfsync=ON;
          PRAGMA secure_delete=ON;
          PRAGMA foreign_keys=ON;
          CREATE TABLE IF NOT EXISTS notes (
            id TEXT PRIMARY KEY, title TEXT NOT NULL, collection TEXT NOT NULL DEFAULT '',
            body TEXT NOT NULL DEFAULT '', created REAL NOT NULL, updated REAL NOT NULL,
            duration REAL NOT NULL DEFAULT 0, status TEXT NOT NULL DEFAULT 'ready',
            deleted INTEGER NOT NULL DEFAULT 0);
          CREATE TABLE IF NOT EXISTS segments (
            id INTEGER PRIMARY KEY, note_id TEXT NOT NULL REFERENCES notes(id),
            start REAL NOT NULL, end REAL NOT NULL, trim REAL NOT NULL DEFAULT 0,
            rate INTEGER NOT NULL, state TEXT NOT NULL DEFAULT 'open',
            text TEXT NOT NULL DEFAULT '', error TEXT NOT NULL DEFAULT '');
          CREATE TABLE IF NOT EXISTS blocks (
            id INTEGER PRIMARY KEY, segment_id INTEGER NOT NULL REFERENCES segments(id),
            pcm BLOB NOT NULL);
          CREATE INDEX IF NOT EXISTS blocks_segment ON blocks(segment_id);
          CREATE INDEX IF NOT EXISTS segments_state ON segments(state, id);
          CREATE INDEX IF NOT EXISTS segments_note ON segments(note_id, state, id);
          CREATE TABLE IF NOT EXISTS workspaces (id TEXT PRIMARY KEY, name TEXT NOT NULL COLLATE NOCASE UNIQUE);
          INSERT OR IGNORE INTO workspaces VALUES('inbox','Personal');
          CREATE TABLE IF NOT EXISTS categories (
            workspace TEXT NOT NULL REFERENCES workspaces(id), name TEXT NOT NULL COLLATE NOCASE,
            PRIMARY KEY(workspace,name));
        """)
        columns = {row[1] for row in self.db.execute("PRAGMA table_info(notes)")}
        with self.db:
            if "workspace" not in columns:
                self.db.execute("ALTER TABLE notes ADD COLUMN workspace TEXT NOT NULL DEFAULT 'inbox'")
            if "voice_db" not in columns:
                self.db.execute("ALTER TABLE notes ADD COLUMN voice_db REAL NOT NULL DEFAULT -44")
            if "auto_title" not in columns:
                self.db.execute("ALTER TABLE notes ADD COLUMN auto_title INTEGER NOT NULL DEFAULT 1")
                self.db.execute("UPDATE notes SET auto_title=0 WHERE title NOT LIKE 'Recording · %' AND title NOT IN ('Untitled note','Untitled')")
                for row in self.db.execute("SELECT id,body FROM notes WHERE auto_title=1 AND body!=''").fetchall():
                    self.db.execute("UPDATE notes SET title=? WHERE id=?", (first_sentence(row["body"]), row["id"]))
            self.db.execute("INSERT OR IGNORE INTO categories SELECT DISTINCT workspace,collection FROM notes WHERE collection!=''")
            self.db.execute("CREATE INDEX IF NOT EXISTS notes_workspace ON notes(workspace,deleted,created DESC)")
            from notes_reader import VIEW_SQL
            self.db.execute("CREATE VIEW IF NOT EXISTS notes_readonly AS " + VIEW_SQL)

    def create(self, title=None, collection="", workspace="inbox", voice_db=-44):
        note_id = str(uuid.uuid4())
        now = time.time()
        with self.lock, self.db:
            self._check_workspace(workspace)
            if collection:
                self.db.execute("INSERT OR IGNORE INTO categories VALUES(?,?)", (workspace, collection))
            self.db.execute("INSERT INTO notes(id,title,collection,created,updated,workspace,voice_db,auto_title) VALUES(?,?,?,?,?,?,?,?)",
                            (note_id, title or "New recording", collection, now, now, workspace, voice_db,
                             int(title in (None, "Untitled note", "Untitled"))))
        return note_id

    def note(self, note_id):
        with self.lock:
            row = self.db.execute("SELECT * FROM notes WHERE id=?", (note_id,)).fetchone()
            return dict(row) if row else None

    def notes(self, include_deleted=False):
        with self.lock:
            where = "" if include_deleted else "WHERE deleted=0"
            return [dict(row) for row in self.db.execute(f"SELECT * FROM notes {where} ORDER BY created DESC")]

    def update(self, note_id, **fields):
        allowed = {"title", "collection", "body", "status", "deleted", "workspace"}
        if not fields or not fields.keys() <= allowed:
            raise ValueError("Invalid note fields")
        fields["updated"] = time.time()
        with self.lock, self.db:
            note = self.note(note_id)
            if not note:
                raise ValueError("This note no longer exists")
            workspace = fields.get("workspace", note["workspace"])
            self._check_workspace(workspace)
            collection = fields.get("collection", note["collection"])
            if collection:
                self.db.execute("INSERT OR IGNORE INTO categories VALUES(?,?)", (workspace, collection))
            if "title" in fields:
                fields["auto_title"] = 0
            elif "body" in fields and note["auto_title"]:
                fields["title"] = first_sentence(fields["body"]) or "Untitled note"
            self.db.execute("UPDATE notes SET " + ",".join(f"{key}=?" for key in fields) + " WHERE id=?",
                            (*fields.values(), note_id))

    def _check_workspace(self, workspace):
        if not self.db.execute("SELECT 1 FROM workspaces WHERE id=?", (workspace,)).fetchone():
            raise ValueError("Choose an existing workspace")

    def create_workspace(self, name):
        name = name.strip()
        if not name:
            raise ValueError("Give the workspace a name")
        workspace = str(uuid.uuid4())
        with self.lock, self.db:
            try:
                self.db.execute("INSERT INTO workspaces VALUES(?,?)", (workspace, name))
            except sqlite3.IntegrityError as exc:
                raise ValueError("A workspace with this name already exists") from exc
        return workspace

    def create_category(self, workspace, name):
        name = name.strip()
        if not name:
            raise ValueError("Give the category a name")
        with self.lock, self.db:
            self._check_workspace(workspace)
            self.db.execute("INSERT OR IGNORE INTO categories VALUES(?,?)", (workspace, name))

    def catalog(self):
        with self.lock:
            workspaces = [dict(row) for row in self.db.execute("SELECT * FROM workspaces ORDER BY name COLLATE NOCASE")]
            categories = [dict(row) for row in self.db.execute("""SELECT c.*, COUNT(n.id) AS count FROM categories c
                LEFT JOIN notes n ON n.workspace=c.workspace AND n.collection=c.name AND n.deleted=0
                GROUP BY c.workspace,c.name ORDER BY c.name COLLATE NOCASE""")]
            return workspaces, categories

    def browse(self, workspace="inbox", collection=None, search="", trash=False, limit=100):
        clauses, args = ["n.workspace=?", "n.deleted=?"], [workspace, int(trash)]
        if collection is not None:
            clauses.append("n.collection=?")
            args.append(collection)
        if search:
            clauses.append("(n.title LIKE ? ESCAPE '\\' OR n.body LIKE ? ESCAPE '\\' OR n.collection LIKE ? ESCAPE '\\')")
            needle = "%" + search.replace("\\", "\\\\").replace("%", "\\%").replace("_", "\\_") + "%"
            args.extend([needle] * 3)
        where = " AND ".join(clauses)
        with self.lock:
            total = self.db.execute(f"SELECT COUNT(*) FROM notes n WHERE {where}", args).fetchone()[0]
            rows = self.db.execute(f"""SELECT n.id,n.title,n.collection,n.workspace,n.created,n.duration,n.status,n.deleted,
                (SELECT COUNT(*) FROM segments s WHERE s.note_id=n.id AND s.state!='done') AS pending,
                (SELECT COUNT(*) FROM segments s WHERE s.note_id=n.id AND s.state='error') AS errors
                FROM notes n WHERE {where} ORDER BY n.created DESC LIMIT ?""", (*args, max(100, limit)))
            return [dict(row) for row in rows], total

    def document(self, note_id):
        note = self.note(note_id)
        if note:
            counts = self.counts(note_id)
            note["pending"] = sum(counts.get(s, 0) for s in ("open", "pending", "processing", "error"))
            note["errors"] = counts.get("error", 0)
            note["editable"] = self.can_edit(note_id)
        return note or {}

    def segment(self, note_id, start, rate, trim=0):
        with self.lock, self.db:
            return self.db.execute("INSERT INTO segments(note_id,start,end,rate,trim) VALUES(?,?,?,?,?)",
                                   (note_id, start, start, rate, trim)).lastrowid

    def append(self, segment_id, pcm, end):
        with self.lock, self.db:
            self.db.execute("INSERT INTO blocks(segment_id,pcm) VALUES(?,?)", (segment_id, pcm))
            self.db.execute("UPDATE segments SET end=? WHERE id=?", (end, segment_id))
            self.db.execute("UPDATE notes SET duration=MAX(duration,?) WHERE id=(SELECT note_id FROM segments WHERE id=?)",
                            (end, segment_id))

    def close_segment(self, segment_id):
        with self.lock, self.db:
            count = self.db.execute("SELECT COUNT(*) FROM blocks WHERE segment_id=?", (segment_id,)).fetchone()[0]
            if count:
                self.db.execute("UPDATE segments SET state='pending' WHERE id=?", (segment_id,))
            else:
                self.db.execute("DELETE FROM segments WHERE id=?", (segment_id,))

    def recover(self):
        with self.lock, self.db:
            self.db.execute("UPDATE notes SET status='interrupted' WHERE status IN ('recording','paused')")
            self.db.execute("UPDATE segments SET state='pending' WHERE state IN ('open','processing')")
            self.db.execute("DELETE FROM segments WHERE state='pending' AND id NOT IN (SELECT segment_id FROM blocks)")

    def retry(self, note_id=None):
        with self.lock, self.db:
            if note_id:
                self.db.execute("UPDATE segments SET state='pending',error='' WHERE state='error' AND note_id=?", (note_id,))
            else:
                self.db.execute("UPDATE segments SET state='pending',error='' WHERE state='error'")

    def next_segment(self):
        with self.lock, self.db:
            # An earlier failed chunk blocks later ones in its note, preserving order.
            row = self.db.execute("""SELECT s.*,n.voice_db FROM segments s JOIN notes n ON n.id=s.note_id WHERE s.state='pending'
                AND NOT EXISTS (SELECT 1 FROM segments earlier WHERE earlier.note_id=s.note_id
                  AND earlier.id<s.id AND earlier.state!='done') ORDER BY s.id LIMIT 1""").fetchone()
            if not row:
                return None
            self.db.execute("UPDATE segments SET state='processing' WHERE id=?", (row["id"],))
            result = dict(row)
            result["pcm"] = b"".join(row[0] for row in self.db.execute("SELECT pcm FROM blocks WHERE segment_id=? ORDER BY id", (row["id"],)))
            return result

    def complete(self, segment_id, text, start=None):
        with self.lock, self.db:
            row = self.db.execute("SELECT * FROM segments WHERE id=?", (segment_id,)).fetchone()
            if not row or row["state"] == "done":
                return
            if text.strip():
                line = f"[{timestamp(max(row['start'], row['trim'], start if start is not None else 0))}] {text.strip()}"
                self.db.execute("UPDATE notes SET body=CASE WHEN body='' THEN ? ELSE body||char(10)||char(10)||? END,updated=? WHERE id=?",
                                (line, line, time.time(), row["note_id"]))
                note = self.note(row["note_id"])
                if note["auto_title"]:
                    self.db.execute("UPDATE notes SET title=? WHERE id=?", (first_sentence(note["body"]), row["note_id"]))
            self.db.execute("UPDATE segments SET state='done',text=?,error='' WHERE id=?", (text, segment_id))
            self.db.execute("DELETE FROM blocks WHERE segment_id=?", (segment_id,))

    def previous_text(self, segment_id, note_id):
        with self.lock:
            row = self.db.execute("SELECT text FROM segments WHERE note_id=? AND id<? AND state='done' ORDER BY id DESC LIMIT 1",
                                  (note_id, segment_id)).fetchone()
            return row[0] if row else ""

    def fail(self, segment_id, message):
        with self.lock, self.db:
            self.db.execute("UPDATE segments SET state='error',error=? WHERE id=?", (message, segment_id))

    def counts(self, note_id=None):
        where, args = ("WHERE note_id=?", (note_id,)) if note_id else ("", ())
        with self.lock:
            rows = self.db.execute(f"SELECT state,COUNT(*) FROM segments {where} GROUP BY state", args)
            return {row[0]: row[1] for row in rows}

    def can_edit(self, note_id):
        counts = self.counts(note_id)
        note = self.note(note_id)
        return note and note["status"] not in ("recording", "paused") and not any(counts.get(s, 0) for s in ("open", "pending", "processing"))

    def close(self):
        with self.lock:
            self.db.close()
