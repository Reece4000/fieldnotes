"""Small protocol peer for the native controller tests; no audio/model runtime."""
import json
import os
import sys
import time

notes = {
    key: {"id": key, "title": key, "body": "Original " + key,
          "workspace": "inbox", "collection": "", "editable": True,
          "deleted": False, "pending": 0, "errors": 0, "status": "complete"}
    for key in ("first", "second")
}
selected = "first"


def emit(event):
    print(json.dumps(event), flush=True)


def state():
    emit({"event": "state", "document": notes[selected],
          "notes": list(notes.values()), "workspaces": [], "categories": [],
          "total": 2, "active": "", "capture": {}, "engine": "ready"})


state()
for line in sys.stdin:
    command = json.loads(line)
    with open(os.environ["FIELDNOTES_TEST_COMMANDS"], "a") as log:
        log.write(json.dumps(command) + "\n")
    if command["action"] == "update":
        fields = {key: command[key] for key in ("title", "body", "workspace", "collection") if key in command}
        notes[command["id"]].update(fields)
        time.sleep(float(os.environ.get("FIELDNOTES_TEST_ACK_DELAY", "0")))
        emit({"event": "saved", "id": command["id"], "fields": fields})
        state()
    elif command["action"] == "select":
        selected = command["id"]
        state()
    elif command["action"] == "shutdown":
        break
