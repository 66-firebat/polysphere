import QtQuick

// Simple resolution scaler — scales UI elements proportionally to screen width.
// Reference width 1920px = scale factor 1.0
QtObject {
    id: root

    property real currentWidth: 1920
    readonly property real baseWidth: 1920
    readonly property real factor: Math.max(0.5, Math.min(2.0, currentWidth / baseWidth))

    function s(val) {
        return val * root.factor;
    }
}
