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

    def test_markdown_heading_titles_preserve_source_and_manual_names(self):
        note = self.store.create()
        body = '## Typed note\n\nA new **idea** worth keeping.\n\n- First action\n- Second action'
        self.store.update(note, body=body)
        self.assertEqual(self.store.note(note)['title'], 'Typed note')
        self.assertEqual(self.store.note(note)['body'], body)
        self.store.update(note, body='# Revised heading ###\n\nMore text.')
        self.assertEqual(self.store.note(note)['title'], 'Revised heading')
        self.store.update(note, title='My own title')
        self.store.update(note, body=body)
        self.assertEqual(self.store.note(note)['title'], 'My own title')
        self.assertEqual(self.store.note(note)['body'], body)

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

    def test_bulk_move_is_atomic_and_preserves_content_and_capture(self):
        first = self.store.create(collection='Source')
        second = self.store.create('Manual title', collection='Source')
        self.store.update(first, body='Captured thought.', status='recording')
        self.store.update(second, body='Edited transcript.')
        self.store.create_category('inbox', 'Destination')
        originals = [self.store.note(n) for n in (first, second)]
        self.assertEqual(self.store.move_notes([first, second, first], 'inbox', 'Destination'), 2)
        self.store.close(); self.store = Store(self.path)
        for before in originals:
            after = self.store.note(before['id'])
            self.assertEqual(after['collection'], 'Destination')
            for key in ('body', 'title', 'status', 'workspace', 'created', 'auto_title'):
                self.assertEqual(after[key], before[key])
        self.assertEqual(self.store.browse(collection='Source')[1], 0)
        self.assertEqual(self.store.browse(collection='Destination')[1], 2)
        for invalid in ('missing', second):
            if invalid == second:
                self.store.update(second, deleted=1)
            with self.assertRaises(ValueError):
                self.store.move_notes([first, invalid], 'inbox', '')
            self.assertEqual(self.store.note(first)['collection'], 'Destination')
        with self.assertRaises(ValueError):
            self.store.move_notes([first], 'inbox', 'Not a category')
        other = self.store.create_workspace('Other')
        with self.assertRaises(ValueError):
            self.store.move_notes([first], other, '')
        self.store.move_notes([first], 'inbox', '')
        self.assertEqual(self.store.note(first)['collection'], '')

    def test_category_management_preserves_live_and_trashed_notes(self):
        live = self.store.create(collection='Drafts')
        trashed = self.store.create(collection='Drafts')
        self.store.update(trashed, deleted=1)
        self.store.create_category('inbox', 'Ideas')
        self.store.rename_category('inbox', 'Drafts', 'Fieldwork')
        for note in (live, trashed):
            self.assertEqual(self.store.note(note)['collection'], 'Fieldwork')
        with self.assertRaisesRegex(ValueError, 'already exists'):
            self.store.rename_category('inbox', 'Fieldwork', 'Ideas')
        self.assertEqual(self.store.note(live)['collection'], 'Fieldwork')
        self.store.reorder_categories('inbox', ['Ideas', 'Fieldwork'])
        self.store.close(); self.store = Store(self.path)
        self.assertEqual([c['name'] for c in self.store.catalog()[1]], ['Ideas', 'Fieldwork'])
        with self.assertRaises(ValueError):
            self.store.reorder_categories('inbox', ['Ideas', 'Ideas'])
        self.store.remove_category('inbox', 'Fieldwork')
        for note in (live, trashed):
            self.assertEqual(self.store.note(note)['collection'], '')
        self.assertTrue(self.store.note(trashed)['deleted'])
        self.assertFalse(self.store.note(live)['deleted'])
        self.assertEqual(len(self.store.notes(include_deleted=True)), 2)

    def test_organise_query_includes_every_note_and_bulk_move_keeps_open_document(self):
        from backend import Backend
        events = []
        backend = Backend(Path(self.temp.name) / 'organise.db', emit=events.append, fake_engine=True)
        try:
            ids = [backend.store.create(f'Note {i}', collection='Source') for i in range(115)]
            backend.store.create_category('inbox', 'Destination')
            backend.selected = ids[0]
            backend.command({'action': 'query', 'workspace': 'inbox', 'all': True})
            state = [e for e in events if e['event'] == 'state'][-1]
            self.assertEqual(len(state['notes']), 115)
            backend.command({'action': 'move', 'ids': ids[1:], 'workspace': 'inbox', 'collection': 'Destination'})
            self.assertEqual(backend.selected, ids[0])
            self.assertEqual(backend.store.browse(collection='Destination')[1], 114)
            self.assertIn({'event': 'moved', 'count': 114, 'collection': 'Destination'}, events)
        finally:
            backend.shutdown()

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

    def test_recording_floor_defaults_to_72_and_accepts_90(self):
        from backend import Backend
        from unittest.mock import patch
        backend = Backend(Path(self.temp.name) / 'floors.db', emit=lambda _: None, fake_engine=True)
        try:
            with patch.object(backend.recorder, 'start'):
                for requested, expected in ((None, -72), (-72, -72), (-90, -90), (-100, -90), (0, -20)):
                    command = {'action': 'record'}
                    if requested is not None:
                        command['voiceDb'] = requested
                    backend.command(command)
                    self.assertEqual(backend.store.note(backend.selected)['voice_db'], expected)
        finally:
            backend.shutdown()

    def test_targeted_trash_is_reversible_and_preserves_the_open_document(self):
        from backend import Backend
        events = []
        backend = Backend(Path(self.temp.name) / 'trash.db', emit=events.append, fake_engine=True)
        try:
            opened = backend.store.create('Open note')
            target = backend.store.create('Context-menu target')
            backend.store.update(target, body='Text to retain after restoring.')
            backend.selected = opened
            backend.command({'action': 'delete', 'id': target})
            self.assertEqual(backend.selected, opened)
            self.assertTrue(backend.store.note(target)['deleted'])
            self.assertIn({'event': 'deleted', 'id': target}, events)
            self.assertEqual([e for e in events if e['event'] == 'state'][-1]['document']['id'], opened)
            backend.command({'action': 'restore', 'id': target})
            self.assertFalse(backend.store.note(target)['deleted'])
            self.assertEqual(backend.store.note(target)['body'], 'Text to retain after restoring.')
            backend.recorder.note_id = target
            with self.assertRaisesRegex(RuntimeError, 'Stop recording'):
                backend.command({'action': 'delete', 'id': target})
            backend.recorder.note_id = None
        finally:
            backend.shutdown()

    def test_empty_notes_are_discarded_and_kept_notes_are_not(self):
        empty = self.store.create('Untitled note')
        typed = self.store.create('Untitled note'); self.store.update(typed, body='Something')
        named = self.store.create('Untitled note'); self.store.update(named, title='Kept title')
        heard = self.store.create()
        segment = self.store.segment(heard, 0, 16000); self.store.append(segment, b'\0\0' * 160, 0.01)
        blank = self.store.create('Untitled note'); self.store.update(blank, body='  \n ')
        self.assertTrue(self.store.discard_if_empty(empty))
        for note in (typed, named, heard):
            self.assertFalse(self.store.discard_if_empty(note))
            self.assertIsNotNone(self.store.note(note))
        self.assertEqual(self.store.discard_empty(keep=[blank]), 0)
        self.assertEqual(self.store.discard_empty(), 1)
        self.assertIsNone(self.store.note(blank))

    def test_leaving_an_empty_note_discards_it_and_notes_trash_together(self):
        from backend import Backend
        events = []
        backend = Backend(Path(self.temp.name) / 'leave.sqlite3', emit=events.append, fake_engine=True)
        try:
            backend.command({'action': 'new', 'workspace': 'inbox'})
            first = backend.selected
            backend.command({'action': 'new', 'workspace': 'inbox'})
            self.assertIsNone(backend.store.note(first))
            second = backend.selected
            backend.command({'action': 'update', 'id': second, 'body': 'Kept'})
            backend.command({'action': 'new', 'workspace': 'inbox'})
            self.assertIsNotNone(backend.store.note(second))
            third = backend.selected
            backend.command({'action': 'discard', 'id': third})
            self.assertIsNone(backend.store.note(third))
            self.assertEqual(backend.selected, second)
            other = backend.store.create('Another'); backend.store.update(other, body='Also kept')
            backend.command({'action': 'delete', 'id': second, 'ids': [second, other]})
            self.assertTrue(all(backend.store.note(n)['deleted'] for n in (second, other)))
            self.assertIn({'event': 'deleted', 'id': second, 'ids': [second, other]}, events)
            backend.command({'action': 'restore', 'id': second, 'ids': [second, other]})
            self.assertFalse(any(backend.store.note(n)['deleted'] for n in (second, other)))
        finally:
            backend.shutdown()

    def test_query_keeps_the_open_note_or_reopens_a_remembered_one(self):
        from backend import Backend
        events = []
        backend = Backend(Path(self.temp.name) / 'keep.sqlite3', emit=events.append, fake_engine=True)
        try:
            work = backend.store.create('Work note', 'Work'); backend.store.update(work, body='w')
            home = backend.store.create('Home note', 'Home'); backend.store.update(home, body='h')
            backend.command({'action': 'query', 'workspace': 'inbox', 'collection': 'Work'})
            self.assertEqual(backend.selected, work)
            # The open note is still listed under all notes, so it stays open.
            backend.command({'action': 'query', 'workspace': 'inbox'})
            self.assertEqual(backend.selected, work)
            backend.command({'action': 'select', 'id': home})
            # A page coming back asks for its remembered note.
            backend.command({'action': 'query', 'workspace': 'inbox', 'select': work})
            self.assertEqual(backend.selected, work)
            # Not listed: the first note opens instead.
            backend.command({'action': 'query', 'workspace': 'inbox', 'collection': 'Home', 'select': work})
            self.assertEqual(backend.selected, home)
        finally:
            backend.shutdown()


if __name__ == '__main__': unittest.main()
