cmake_minimum_required(VERSION 3.24)
project(Fieldnotes VERSION 0.3.0 LANGUAGES CXX OBJCXX)
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_OSX_DEPLOYMENT_TARGET "15.0" CACHE STRING "Minimum macOS")
find_package(Qt6 6.9 REQUIRED COMPONENTS Core Gui Quick QuickControls2)
qt_standard_project_setup(REQUIRES 6.9)
qt_policy(SET QTP0004 NEW)
set(FIELDNOTES_PYTHON "${CMAKE_SOURCE_DIR}/.venv/bin/python" CACHE FILEPATH "Speech runtime Python")
qt_add_executable(Fieldnotes MACOSX_BUNDLE src/main.cpp src/controller.cpp src/controller.h src/note_model.cpp src/note_model.h src/platform.mm)
set(FIELDNOTES_ICON "${CMAKE_SOURCE_DIR}/assets/Fieldnotes.icns")
set_source_files_properties("${FIELDNOTES_ICON}" PROPERTIES MACOSX_PACKAGE_LOCATION "Resources")
target_sources(Fieldnotes PRIVATE "${FIELDNOTES_ICON}")
qt_add_qml_module(Fieldnotes URI Fieldnotes VERSION 1.0
  QML_FILES qml/Main.qml qml/Theme.js qml/ThemePalette.qml qml/OrganiseView.qml qml/NoteEditor.qml qml/PixelScroll.qml qml/TextContextMenu.qml
    qml/ActionButton.qml qml/BandKey.qml qml/CopyButton.qml qml/FieldCheck.qml qml/FieldCombo.qml qml/FieldDialog.qml
    qml/FieldMenu.qml qml/FieldMenuGap.qml qml/FieldMenuItem.qml qml/FieldScrollBar.qml qml/FieldSlider.qml qml/FieldText.qml
    qml/Readout.qml qml/RecordingConsole.qml qml/Waveform.qml
  RESOURCES assets/fonts/Geist-Regular.ttf assets/fonts/Geist-Medium.ttf assets/fonts/GeistMono-Regular.ttf assets/fonts/DSEG14Modern-Regular.ttf)
target_link_libraries(Fieldnotes PRIVATE Qt6::Core Qt6::Gui Qt6::Quick Qt6::QuickControls2 "-framework AppKit")
set_target_properties(Fieldnotes PROPERTIES
  MACOSX_BUNDLE_INFO_PLIST "${CMAKE_SOURCE_DIR}/src/Info.plist.in"
  MACOSX_BUNDLE_BUNDLE_NAME "Fieldnotes"
  MACOSX_BUNDLE_ICON_FILE "Fieldnotes.icns"
  MACOSX_BUNDLE_GUI_IDENTIFIER "dev.reecemitchell.fieldnotes"
  MACOSX_BUNDLE_SHORT_VERSION_STRING "${PROJECT_VERSION}")
configure_file(src/runtime.json.in runtime.json @ONLY)
include(CTest)
if(BUILD_TESTING)
  find_package(Qt6 REQUIRED COMPONENTS Test QuickTest)
  qt_add_executable(FieldnotesSaveTest tests/test_save_debounce.cpp src/controller.cpp src/controller.h src/note_model.cpp src/note_model.h)
  target_include_directories(FieldnotesSaveTest PRIVATE src)
  target_link_libraries(FieldnotesSaveTest PRIVATE Qt6::Core Qt6::Gui Qt6::Test)
  set_target_properties(FieldnotesSaveTest PROPERTIES RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/tests/save/Contents/MacOS")
  file(MAKE_DIRECTORY "${CMAKE_BINARY_DIR}/tests/save/Contents/Resources/worker")
  configure_file(tests/save_backend.py "${CMAKE_BINARY_DIR}/tests/save/Contents/Resources/worker/backend.py" COPYONLY)
  configure_file(src/runtime.json.in "${CMAKE_BINARY_DIR}/tests/save/Contents/Resources/runtime.json" @ONLY)
  add_test(NAME save_debounce COMMAND FieldnotesSaveTest)
  qt_add_executable(FieldnotesEditorTest tests/test_editor.cpp)
  target_link_libraries(FieldnotesEditorTest PRIVATE Qt6::QuickTest Qt6::Quick)
  target_compile_definitions(FieldnotesEditorTest PRIVATE QUICK_TEST_SOURCE_DIR="${CMAKE_SOURCE_DIR}/tests/qml")
  add_test(NAME note_editor COMMAND FieldnotesEditorTest)
  set_tests_properties(note_editor PROPERTIES ENVIRONMENT "QT_QPA_PLATFORM=offscreen;QT_QUICK_CONTROLS_STYLE=Basic")
endif()
add_custom_target(FieldnotesRuntime ALL DEPENDS Fieldnotes
  COMMAND ${CMAKE_COMMAND} -E make_directory "$<TARGET_BUNDLE_DIR:Fieldnotes>/Contents/Resources"
  COMMAND ${CMAKE_COMMAND} -E copy_directory "${CMAKE_SOURCE_DIR}/worker" "$<TARGET_BUNDLE_DIR:Fieldnotes>/Contents/Resources/worker"
  COMMAND ${CMAKE_COMMAND} -E rm -rf "$<TARGET_BUNDLE_DIR:Fieldnotes>/Contents/Resources/worker/__pycache__"
  COMMAND ${CMAKE_COMMAND} -E copy "${CMAKE_BINARY_DIR}/runtime.json" "$<TARGET_BUNDLE_DIR:Fieldnotes>/Contents/Resources/runtime.json")
