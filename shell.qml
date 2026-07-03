import QtQuick
import Quickshell
import Quickshell.Wayland

// Wrapper to run polysphere as a standalone overlay window.
// PanelWindow stays always on the Overlay layer so keyboard events
// (Escape, Alt release) still reach the QML engine.
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
        id: loader
        anchors.fill: parent
        source: "polysphere.qml"
        onItemChanged: {
            // Give polysphere.qml a reference to this PanelWindow so it can
            // directly control visibility (for click-through when closed).
            if (loader.item) {
                loader.item.panelWindow = root;
            }
        }
    }

    // Click outside to close the overlay (does NOT quit the process)
    MouseArea {
        id: clickCatcher
        anchors.fill: parent
        z: -1
        enabled: loader.item ? loader.item.visible : false
        onClicked: {
            var poly = loader.item;
            if (poly && poly.closeOverlay) {
                poly.closeOverlay();
            }
        }
    }
}
