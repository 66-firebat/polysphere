import QtQuick
import Quickshell
import Quickshell.Wayland

// Wrapper to run polysphere as a standalone overlay window
PanelWindow {
    id: root

    WlrLayershell.namespace: "polysphere"
    WlrLayershell.layer: WlrLayer.Overlay

    focusable: true
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"

    implicitWidth: root.screen.width
    implicitHeight: root.screen.height

    Loader {
        anchors.fill: parent
        source: "polysphere.qml"
    }

    // Click outside to close
    MouseArea {
        anchors.fill: parent
        z: -1
        onClicked: Qt.quit()
    }

    Shortcut {
        sequence: "Escape"
        onActivated: Qt.quit()
    }
}
