"""Private JSON-lines backend: durable notes/capture and isolated local inference."""
import argparse
import base64
from collections import deque
import fcntl
import json
import os
from pathlib import Path
import queue
import re
import select
import signal
import subprocess
import sys
import threading
import time

from recorder import Recorder
from store import Store


def clean_overlap(result, segment, previous="", with_start=False):
    cutoff = segment["trim"] - segment["start"]
    if cutoff <= 0:
        words = result.get("words") or []
        text = result["text"].strip()
        start = segment["start"] + (words[0]["start"] if words else 0)
        return (text, start) if with_start else text
    words = result.get("words") or []
    if not words and result["text"].strip():
        raise RuntimeError("Word timestamps were missing. Audio retained for retry.")
    kept = [w for w in words if (w["start"] + w["end"]) / 2 >= cutoff]
    # Token timings can shift between independent windows. Remove matching
    # boundary words only in the overlap neighborhood, never an entire repeat.
    if previous and kept:
        normalize = lambda text: re.sub(r"[^\w]", "", text).casefold()
        before = [normalize(w) for w in previous.split()][-12:]
        after = [normalize(w["text"]) for w in kept]
        for size in range(min(len(before), len(after)), 0, -1):
            if before[-size:] == after[:size] and kept[size - 1]["start"] <= cutoff + 0.75:
                kept = kept[size:]
                break
    text = " ".join(w["text"] for w in kept).strip()
    start = segment["start"] + (kept[0]["start"] if kept else cutoff)
    return (text, start) if with_start else text


class Backend:
    def __init__(self, path, emit=None, fake_engine=False):
        self.store = Store(path)
        self.store.recover()
        self.output_lock = threading.RLock()
        self.emit_override = emit
        self.output_wake = threading.Event()
        self.output_events = deque()
        self.latest_state = None
        self.latest_meter = None
        self.output_thread = None
        self.wake = threading.Event()
        self.retry_engine = threading.Event()
        self.quit = threading.Event()
        self.engine = None
        self.fake_engine = fake_engine
        self.engine_status = "loading"
        self.engine_error = ""
        self.current = None
        self.selected = ""
        self.query = {"workspace": "inbox", "collection": None, "search": "", "trash": False, "limit": 100}
        self.recorder = Recorder(self.store, self.emit, self.wake)
        if emit is None:
            self.output_thread = threading.Thread(target=self.write_output, name="ui-events", daemon=True)
            self.output_thread.start()
        self.thread = threading.Thread(target=self.transcribe, name="transcription", daemon=True)
        self.thread.start()

    def emit(self, event):
        with self.output_lock:
            if self.emit_override:
                self.emit_override(event)
            else:
                # A frozen UI must never block the audio journal. Coalesce
                # telemetry/snapshots while one dedicated writer owns the pipe.
                if event["event"] == "meter":
                    self.latest_meter = event
                elif event["event"] == "state":
                    self.latest_state = event
                else:
                    self.output_events.append(event)
                self.output_wake.set()

    def write_output(self):
        while not self.quit.is_set():
            self.output_wake.wait(.5)
            with self.output_lock:
                if self.output_events:
                    event = self.output_events.popleft()
                elif self.latest_state is not None:
                    event, self.latest_state = self.latest_state, None
                elif self.latest_meter is not None:
                    event, self.latest_meter = self.latest_meter, None
                else:
                    self.output_wake.clear()
                    continue
            try:
                print(json.dumps(event, ensure_ascii=False), flush=True)
            except BrokenPipeError:
                self.quit.set()
                return

    def state(self):
        with self.output_lock:
            self._state()

    def _state(self):
        notes, total = self.store.browse(**self.query)
        if not self.selected and notes:
            self.selected = notes[0]["id"]
        workspaces, categories = self.store.catalog()
        capture = self.store.note(self.recorder.note_id) if self.recorder.note_id else {}
        self.emit({"event": "state", "notes": notes, "active": self.recorder.note_id or "",
                   "document": self.store.document(self.selected), "total": total,
                   "workspaces": workspaces, "categories": categories,
                   "capture": {key: capture.get(key) for key in ("workspace", "collection")} if capture else {},
                   "paused": self.recorder.paused, "engine": self.engine_status,
                   "engineError": self.engine_error})

    def read_engine(self, timeout):
        # Binary, unbuffered pipe: select sees every line (no TextIO read-ahead).
        deadline = time.monotonic() + timeout
        data = bytearray()
        while time.monotonic() < deadline and not self.quit.is_set():
            if self.engine.poll() is not None:
                raise RuntimeError("The transcription process exited")
            ready, _, _ = select.select([self.engine.stdout], [], [], 0.25)
            if ready:
                char = os.read(self.engine.stdout.fileno(), 1)
                if not char:
                    raise RuntimeError("The transcription process closed its output")
                if char == b"\n":
                    message = json.loads(data)
                    if message["event"] == "error":
                        raise RuntimeError(message["message"])
                    return message
                data.extend(char)
        raise RuntimeError("Transcription timed out; audio has been kept for retry")

    def transcribe(self):
        while not self.quit.is_set():
            try:
                if self.engine_status != "ready":
                    if not self.fake_engine:
                        self.engine = subprocess.Popen([sys.executable, "-u", str(Path(__file__).with_name("engine.py"))],
                                                       stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=sys.stderr, bufsize=0)
                        reply = self.read_engine(600)
                        if reply["event"] != "ready":
                            raise RuntimeError("Unexpected engine response")
                    self.engine_status = "ready"
                    self.engine_error = ""
                    self.state()
                segment = self.store.next_segment()
                if segment is None:
                    self.wake.wait(0.25)
                    self.wake.clear()
                    continue
                self.current = segment
                if self.fake_engine:
                    result = {"text": "A recovered test recording.", "words": []}
                else:
                    payload = json.dumps({"id": segment["id"], "rate": segment["rate"], "voiceDb": segment["voice_db"],
                                          "pcm": base64.b64encode(segment["pcm"]).decode()}).encode() + b"\n"
                    # Writes can be large but only this inference thread waits.
                    view = memoryview(payload)
                    while view:
                        written = self.engine.stdin.write(view)
                        if not written:
                            raise RuntimeError("The transcription pipe closed")
                        view = view[written:]
                    result = self.read_engine(180)
                    if result.get("id") != segment["id"]:
                        raise RuntimeError("Unexpected transcription segment")
                text, start = clean_overlap(result, segment, self.store.previous_text(segment["id"], segment["note_id"]), with_start=True)
                self.store.complete(segment["id"], text, start=start)
                self.current = None
                self.state()
            except Exception as exc:
                if self.quit.is_set():
                    # Closing deliberately interrupts inference. Keep the chunk
                    # processing (and its PCM) for recover() on the next launch.
                    self.current = None
                    return
                if self.current:
                    self.store.fail(self.current["id"], str(exc))
                    self.current = None
                self.engine_status = "error"
                self.engine_error = str(exc)
                self.retry_engine.clear()
                if self.engine:
                    self.engine.kill()
                    self.engine.wait()
                    self.engine = None
                if self.quit.is_set():
                    return
                self.state()
                # Explicit retry; never consume endless resources in a crash loop.
                self.retry_engine.wait()

    def command(self, command):
        action = command["action"]
        note_id = command.get("id")
        if action == "copy":
            note = self.store.note(note_id)
            if not note:
                raise ValueError("This note is no longer available")
            self.emit({"event": "copy", "id": note_id, "text": note["body"]})
            return
        if action == "devices":
            self.emit({"event": "devices", "devices": self.recorder.devices()})
        elif action == "new":
            note_id = self.store.create("Untitled note", command.get("collection", ""), command.get("workspace", "inbox"))
            self.selected = note_id
            self.emit({"event": "select", "id": note_id})
        elif action == "record":
            note_id = self.store.create(collection=command.get("collection", ""), workspace=command.get("workspace", "inbox"),
                                        voice_db=max(-65, min(-20, command.get("voiceDb", -44))))
            self.selected = note_id
            self.emit({"event": "select", "id": note_id})
            try:
                self.recorder.start(note_id, command.get("device"))
            except Exception:
                self.state()
                raise
        elif action == "pause" and self.recorder.note_id:
            self.recorder.pause()
        elif action == "stop":
            self.recorder.stop()
        elif action == "update":
            fields = {key: command[key] for key in ("title", "collection", "body", "workspace") if key in command}
            if "body" in fields and not self.store.can_edit(note_id):
                raise RuntimeError("Finish transcription before editing this note")
            self.store.update(note_id, **fields)
            self.emit({"event": "saved", "id": note_id, "fields": fields})
        elif action in ("delete", "restore"):
            if action == "delete" and (note_id == self.recorder.note_id or self.store.counts(note_id).get("processing")):
                raise RuntimeError("Stop recording and finish transcription before deleting this note")
            self.store.update(note_id, deleted=int(action == "delete"))
        elif action == "select":
            self.selected = note_id
        elif action == "query":
            query = {"workspace": command.get("workspace", "inbox"), "collection": command.get("collection"),
                     "search": command.get("search", ""), "trash": command.get("trash", False), "limit": 100}
            if any(query[key] != self.query[key] for key in ("workspace", "collection", "trash")):
                rows, _ = self.store.browse(**query)
                self.selected = rows[0]["id"] if rows else ""
                self.emit({"event": "select", "id": self.selected})
            self.query = query
        elif action == "more":
            self.query["limit"] += 100
        elif action == "workspace":
            workspace = self.store.create_workspace(command["name"])
            self.emit({"event": "workspace", "id": workspace})
        elif action == "category":
            self.store.create_category(command["workspace"], command["name"])
            self.emit({"event": "category", "name": command["name"].strip()})
        elif action == "retry":
            self.store.retry(note_id)
            self.retry_engine.set()
            self.wake.set()
        elif action == "shutdown":
            self.recorder.stop()
            self.quit.set()
            self.retry_engine.set()
            self.wake.set()
        self.state()

    def shutdown(self):
        self.recorder.stop()
        self.quit.set()
        self.retry_engine.set()
        self.wake.set()
        engine = self.engine
        if engine:
            if engine.poll() is None:
                engine.kill()
            engine.wait(timeout=5)
        self.thread.join(timeout=5)
        if self.thread.is_alive():
            # Main process exits; sqlite transactions are recoverable on next launch.
            return
        self.store.close()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--data", required=True)
    args = parser.parse_args()
    os.umask(0o077)
    path = Path(args.data)
    path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    # Prevent a restarted UI and its old backend both touching the same recorder.
    lock = open(str(path) + ".lock", "a")
    try:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError:
        print(json.dumps({"event": "error", "message": "Another Fieldnotes window is still saving. Wait a moment and reopen."}), flush=True)
        return 1
    backend = Backend(path)
    commands = queue.Queue()

    def read_commands():
        try:
            for line in sys.stdin:
                try:
                    commands.put(json.loads(line))
                except ValueError:
                    backend.emit({"event": "error", "message": "An invalid app command was ignored"})
        finally:
            commands.put({"action": "shutdown"})

    threading.Thread(target=read_commands, name="commands", daemon=True).start()
    signal.signal(signal.SIGTERM, lambda *_: commands.put({"action": "shutdown"}))
    backend.state()
    try:
        while not backend.quit.is_set():
            try:
                command = commands.get(timeout=0.5)
                backend.command(command)
            except queue.Empty:
                active = backend.recorder.note_id
                backend.recorder.check()
                if active != backend.recorder.note_id:
                    backend.state()
            except Exception as exc:
                backend.emit({"event": "error", "message": str(exc)})
    finally:
        backend.shutdown()
    return 0


if __name__ == "__main__":
    sys.exit(main())
