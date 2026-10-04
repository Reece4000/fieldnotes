import QtQuick
Item {
    id: icon
    property string name: "folder"
    property color tint: "#426354"
    readonly property var paths: ({
        folder: '<path d="M3 7h7l2 2h9v11H3z"/><path d="M3 7V4h7l2 3h9v2"/>',
        workspace: '<rect x="3" y="5" width="18" height="15" rx="2"/><path d="M8 5V3h8v2M3 10h18M10 10v3h4v-3"/>',
        document: '<path d="M6 3h8l4 4v14H6zM14 3v5h4M9 12h6M9 16h6"/>',
        copy: '<rect x="8" y="3" width="12" height="15" rx="2"/><path d="M6 7H4v14h12v-1"/>',
        export: '<path d="M12 15V3M8 7l4-4 4 4M5 12v8h14v-8"/>',
        search: '<circle cx="10" cy="10" r="6"/><path d="m15 15 6 6"/>',
        microphone: '<rect x="9" y="2" width="6" height="13" rx="3"/><path d="M5 10v2a7 7 0 0 0 14 0v-2M12 19v3M8 22h8"/>',
        trash: '<path d="M4 6h16M9 6V3h6v3M6 6l1 15h10l1-15M10 10v7M14 10v7"/>',
        flask: '<path d="M9 3h6M10 3v7L4 20h16l-6-10V3M7 15h10"/>',
        idea: '<path d="M9 19h6M10 22h4M9 16c0-3-4-3-4-7a7 7 0 0 1 14 0c0 4-4 4-4 7z"/>',
        gear: '<circle cx="12" cy="12" r="4"/><path d="M12 2v3M12 19v3M2 12h3M19 12h3M5 5l2 2M17 17l2 2M5 19l2-2M17 7l2-2"/><circle cx="12" cy="12" r="8"/>',
        waveform: '<path d="M3 10v4M7 6v12M12 2v20M17 6v12M21 10v4"/>'
    })
    implicitWidth: 20; implicitHeight: 20
    Image {
    anchors.fill: parent
    sourceSize: Qt.size(40, 40)
    source: "data:image/svg+xml," + encodeURIComponent('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="' + icon.tint + '" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round">' + (icon.paths[icon.name] || icon.paths.folder) + '</svg>')
    fillMode: Image.PreserveAspectFit
    }
    Accessible.ignored: true
}
