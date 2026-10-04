import hashlib
import json
from pathlib import Path
import sqlite3
import subprocess
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "worker"))
from store import Store
from notes_reader import catalog, connection, main, notes


class ReaderTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.path = Path(self.temp.name) / "notes ? & ü.sqlite3"
        self.store = Store(self.path)
        self.workspace = self.store.create_workspace("Research")
        self.store.create_category(self.workspace, "Empty")
        self.note = self.store.create(collection="HCI tests", workspace=self.workspace)
        self.store.update(self.note, body="[00:00:03] Cursor issue.\n\n50%_ literal ü and 'quotes'.")

    def tearDown(self):
        self.store.close()
        self.temp.cleanup()

    def digest(self):
        return hashlib.sha256(self.path.read_bytes()).hexdigest()

    def test_full_edited_text_filters_catalog_and_no_mutations(self):
        before = self.digest()
        self.assertEqual(list(notes(self.path, workspace="research", category="hci TESTS", text="50%_"))[0]["transcript"], self.store.note(self.note)["body"])
        self.assertEqual(list(notes(self.path, text="%_x")), [])
        self.assertEqual(list(notes(self.path, text="' OR 1=1 --")), [])
        self.assertEqual(list(notes(self.path, text="ü"))[0]["id"], self.note)
        self.assertTrue(any(c["category"] == "Empty" and c["notes"] == 0 for c in catalog(self.path)["categories"]))
        self.assertEqual(self.digest(), before)
        with connection(self.path) as db:
            self.assertEqual(db.execute("SELECT transcript FROM notes_readonly WHERE id=?", (self.note,)).fetchone()[0], self.store.note(self.note)["body"])
            with self.assertRaises(sqlite3.OperationalError):
                db.execute("DELETE FROM notes")

    def test_paging_ties_trash_date_and_consumer_does_not_hold_read_lock(self):
        for i in range(205):
            note = self.store.create(collection="HCI tests", workspace=self.workspace)
            self.store.update(note, body=f"Run {i}.")
        with self.store.db:
            self.store.db.execute("UPDATE notes SET created=100")
        generator = notes(self.path, workspace=self.workspace, limit=None)
        first = next(generator)
        # A suspended/blocked stdout consumer must not lock the capture journal.
        with sqlite3.connect(self.path, timeout=0.01) as db:
            db.execute("UPDATE notes SET updated=updated+1 WHERE id=?", (first["id"],))
        result = [first] + list(generator)
        self.assertEqual(len(result), 206)
        self.assertEqual(len({r["id"] for r in result}), 206)
        self.assertEqual(len(list(notes(self.path, limit=7))), 7)
        self.assertEqual(list(notes(self.path, since=101)), [])
        self.assertEqual(len(list(notes(self.path, until=101, limit=None))), 206)
        self.store.update(self.note, deleted=1)
        self.assertEqual(list(notes(self.path, note_id=self.note)), [])
        self.assertTrue(list(notes(self.path, note_id=self.note, include_trash=True))[0]["trashed"])

    def test_missing_database_is_not_created_and_cli_is_stdlib_only(self):
        missing = Path(self.temp.name) / "missing.sqlite3"
        with self.assertRaises(sqlite3.OperationalError):
            list(notes(missing))
        self.assertFalse(missing.exists())
        before = self.digest()
        reader = Path(__file__).resolve().parents[1] / "worker/notes_reader.py"
        result = subprocess.run([sys.executable, "-S", str(reader), "--database", str(self.path), "search", "--all", "--format", "jsonl"], capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads(result.stdout)["id"], self.note)
        self.assertEqual(self.digest(), before)


if __name__ == "__main__":
    unittest.main()
