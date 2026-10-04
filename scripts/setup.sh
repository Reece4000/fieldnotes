#!/bin/zsh
set -euo pipefail
task_root="${0:A:h:h}"
cd "$task_root"
if ! command -v brew >/dev/null; then
  printf 'Install Homebrew, then run this script again.\n' >&2
  exit 1
fi
brew install qt cmake python@3.12
"$(brew --prefix python@3.12)/bin/python3.12" -m venv .venv
.venv/bin/python -m pip install -r requirements.txt
./scripts/build.sh
