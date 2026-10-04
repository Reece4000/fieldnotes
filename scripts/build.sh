#!/bin/zsh
set -euo pipefail
task_root="${0:A:h:h}"
cd "$task_root"
qt_prefix="$(brew --prefix qt)"
cmake -S . -B build -DCMAKE_BUILD_TYPE=Release -DCMAKE_PREFIX_PATH="$qt_prefix"
cmake --build build -j 8
"$qt_prefix/bin/qmllint" qml/*.qml
"$qt_prefix/bin/macdeployqt" build/Fieldnotes.app -qmldir="$task_root/qml" -libpath="$qt_prefix/lib" -always-overwrite -no-codesign
codesign --force --deep --sign - build/Fieldnotes.app
printf 'Built: %s/build/Fieldnotes.app\n' "$task_root"
