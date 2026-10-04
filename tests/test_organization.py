import sqlite3
import sys
import tempfile
from pathlib import Path
import unittest
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'worker'))
from store import Store


class OrganizationTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.path = Path(self.temp.name) / 'notes.db'
        self.store = Store(self.path)

    def tearDown(self):
        self.store.close()
        self.temp.cleanup()

    def test_auto_title_tracks_first_sentence_and_respects_manual_rename(self):
        note = self.store.create()
        segment = self.store.segment(note, 0, 16000)
        self.store.append(segment, b'\0\0' * 16000, 1)
        self.store.complete(segment, 'This is a test recording. More text follows.')
        self.assertEqual(self.store.note(note)['title'], 'This is a test recording.')
        self.store.update(note, body='[00:00:00] Corrected first sentence! Extra text.')
        self.assertEqual(self.store.note(note)['title'], 'Corrected first sentence!')
        self.store.update(note, title='Participant 7')
        self.store.update(note, body='New wording.')
        self.assertEqual(self.store.note(note)['title'], 'Participant 7')

    def test_empty_categories_and_workspaces_persist_and_notes_can_move(self):
        workspace = self.store.create_workspace('HCI tests')
        self.store.create_category(workspace, 'Participant sessions')
        note = self.store.create(collection='Debugging')
        self.store.update(note, workspace=workspace, collection='Participant sessions')
        self.assertEqual(self.store.browse(workspace=workspace, collection='Participant sessions')[1], 1)
        self.assertEqual(self.store.browse(workspace='inbox')[1], 0)
        self.store.create_category(workspace, 'Empty category')
        self.store.close(); self.store = Store(self.path)
        workspaces, categories = self.store.catalog()
        self.assertIn('HCI tests', [n['name'] for n in workspaces])
        self.assertIn({'workspace': workspace, 'name': 'Empty category', 'count': 0}, categories)
        self.store.update(note, deleted=1)
        self.assertEqual(self.store.browse(workspace=workspace)[1], 0)
        self.assertEqual(self.store.browse(workspace=workspace, trash=True)[1], 1)

    def test_database_search_pages_metadata_without_loading_transcripts(self):
        for i in range(115):
            note = self.store.create(f'Note {i}')
            self.store.update(note, body=f'Needle {i}. This is a transcript.')
        rows, count = self.store.browse(search='transcript')
        self.assertEqual(count, 115); self.assertEqual(len(rows), 100)
        self.assertNotIn('body', rows[0])
        self.assertEqual(len(self.store.browse(limit=200)[0]), 115)
        self.assertEqual(self.store.browse(search='%')[1], 0)
        self.assertEqual(self.store.browse(search='Needle 114')[1], 1)

    def test_legacy_migration_keeps_body_and_custom_titles(self):
        self.store.close()
        self.path.unlink()
        db = sqlite3.connect(self.path)
        db.execute('''CREATE TABLE notes(id TEXT PRIMARY KEY,title TEXT NOT NULL,collection TEXT NOT NULL DEFAULT '',
            body TEXT NOT NULL DEFAULT '',created REAL NOT NULL,updated REAL NOT NULL,duration REAL NOT NULL DEFAULT 0,
            status TEXT NOT NULL DEFAULT 'ready',deleted INTEGER NOT NULL DEFAULT 0)''')
        body = '[00:00:00] First sentence.\n\n[00:00:04] Existing transcript.'
        db.execute('INSERT INTO notes(id,title,collection,body,created,updated) VALUES(?,?,?,?,?,?)', ('auto','Recording · 04 Oct, 11:21','Debugging',body,1,1))
        db.execute('INSERT INTO notes(id,title,collection,body,created,updated) VALUES(?,?,?,?,?,?)', ('manual','User title','Debugging',body,2,2))
        db.commit(); db.close()
        self.store = Store(self.path)
        self.assertEqual(self.store.note('auto')['title'], 'First sentence.')
        self.assertEqual(self.store.note('auto')['body'], body)
        self.assertEqual(self.store.note('manual')['title'], 'User title')
        self.assertEqual(self.store.catalog()[1][0]['name'], 'Debugging')

    def test_backend_acknowledges_edits_to_notes_outside_the_current_page(self):
        from backend import Backend
        events = []
        backend = Backend(Path(self.temp.name) / 'backend.db', emit=events.append, fake_engine=True)
        try:
            first = backend.store.create()
            second = backend.store.create()
            backend.command({'action': 'select', 'id': second})
            backend.command({'action': 'update', 'id': first, 'body': 'Saved while another note is selected.'})
            saved = [event for event in events if event['event'] == 'saved'][-1]
            self.assertEqual(saved['id'], first)
            self.assertEqual(saved['fields']['body'], backend.store.note(first)['body'])
            state = [event for event in events if event['event'] == 'state'][-1]
            self.assertEqual(state['document']['id'], second)
            self.assertTrue(all('body' not in note for note in state['notes']))
            workspace = backend.store.create_workspace('Empty notebook')
            backend.command({'action': 'query', 'workspace': workspace})
            self.assertEqual([event for event in events if event['event'] == 'state'][-1]['document'], {})
        finally:
            backend.shutdown()


if __name__ == '__main__': unittest.main()
