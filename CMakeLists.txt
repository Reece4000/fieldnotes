cmake_minimum_required(VERSION 3.24)
project(Fieldnotes VERSION 0.3.0 LANGUAGES CXX OBJCXX)
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_OSX_DEPLOYMENT_TARGET "15.0" CACHE STRING "Minimum macOS")
find_package(Qt6 6.9 REQUIRED COMPONENTS Core Gui Quick QuickControls2)
qt_standard_project_setup(REQUIRES 6.9)
qt_policy(SET QTP0004 NEW)
set(FIELDNOTES_PYTHON "${CMAKE_SOURCE_DIR}/.venv/bin/python" CACHE FILEPATH "Speech runtime Python")
qt_add_executable(Fieldnotes MACOSX_BUNDLE src/main.cpp src/controller.cpp src/controller.h src/note_model.cpp src/note_model.h src/platform.mm)
qt_add_qml_module(Fieldnotes URI Fieldnotes VERSION 1.0 QML_FILES qml/Main.qml qml/TextContextMenu.qml qml/ActionButton.qml qml/FieldMenuItem.qml qml/FieldMenu.qml qml/FieldCombo.qml qml/CopyButton.qml qml/RecorderDeck.qml qml/RecordingConsole.qml qml/Waveform.qml qml/FieldDialog.qml qml/FieldIcon.qml qml/TapeReel.qml qml/Surface.qml)
target_link_libraries(Fieldnotes PRIVATE Qt6::Core Qt6::Gui Qt6::Quick Qt6::QuickControls2 "-framework AppKit")
set_target_properties(Fieldnotes PROPERTIES
  MACOSX_BUNDLE_INFO_PLIST "${CMAKE_SOURCE_DIR}/src/Info.plist.in"
  MACOSX_BUNDLE_BUNDLE_NAME "Fieldnotes"
  MACOSX_BUNDLE_GUI_IDENTIFIER "dev.reecemitchell.fieldnotes"
  MACOSX_BUNDLE_SHORT_VERSION_STRING "${PROJECT_VERSION}")
configure_file(src/runtime.json.in runtime.json @ONLY)
include(CTest)
if(BUILD_TESTING)
  find_package(Qt6 REQUIRED COMPONENTS Test)
  qt_add_executable(FieldnotesSaveTest tests/test_save_debounce.cpp src/controller.cpp src/controller.h src/note_model.cpp src/note_model.h)
  target_include_directories(FieldnotesSaveTest PRIVATE src)
  target_link_libraries(FieldnotesSaveTest PRIVATE Qt6::Core Qt6::Gui Qt6::Test)
  set_target_properties(FieldnotesSaveTest PROPERTIES RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/tests/save/Contents/MacOS")
  file(MAKE_DIRECTORY "${CMAKE_BINARY_DIR}/tests/save/Contents/Resources/worker")
  configure_file(tests/save_backend.py "${CMAKE_BINARY_DIR}/tests/save/Contents/Resources/worker/backend.py" COPYONLY)
  configure_file(src/runtime.json.in "${CMAKE_BINARY_DIR}/tests/save/Contents/Resources/runtime.json" @ONLY)
  add_test(NAME save_debounce COMMAND FieldnotesSaveTest)
endif()
add_custom_target(FieldnotesRuntime ALL DEPENDS Fieldnotes
  COMMAND ${CMAKE_COMMAND} -E make_directory "$<TARGET_BUNDLE_DIR:Fieldnotes>/Contents/Resources"
  COMMAND ${CMAKE_COMMAND} -E copy_directory "${CMAKE_SOURCE_DIR}/worker" "$<TARGET_BUNDLE_DIR:Fieldnotes>/Contents/Resources/worker"
  COMMAND ${CMAKE_COMMAND} -E rm -rf "$<TARGET_BUNDLE_DIR:Fieldnotes>/Contents/Resources/worker/__pycache__"
  COMMAND ${CMAKE_COMMAND} -E copy "${CMAKE_BINARY_DIR}/runtime.json" "$<TARGET_BUNDLE_DIR:Fieldnotes>/Contents/Resources/runtime.json")
