import QtQuick
import QtTest

// An endless animation keeps the window drawing every frame (120 fps on a
// 120 Hz screen), even when what it moves is hidden. While nothing changes,
// a view must leave the window still.
TestCase {
    id: test
    name: "IdleAnimations"
    visible: true
    when: windowShown
    width: 600
    height: 200

    readonly property int idleMs: 1000
    /** A still window draws a frame or two after the last change; a running animation draws dozens. */
    readonly property int maxIdleFrames: 5

    property int frames: 0

    Connections {
        target: test.Window.window
        function onFrameSwapped() { test.frames++ }
    }

    /** Frames drawn in idleMs once the view had time to settle. */
    function idleFrames() {
        wait(500)
        frames = 0
        wait(idleMs)
        return frames
    }

    function sparkline(masks) {
        const c = Qt.createComponent(Qt.resolvedUrl("../../contents/ui/DaySparkline.qml"))
        verify(c.status === Component.Ready, c.errorString())
        return createTemporaryObject(c, this, { width: 600, masksRender: masks, showArcs: true, flyoutOpen: true })
    }

    // With the GPU the mask draws the sun, the spinning icon stays hidden.
    function test_sparklineMasked() {
        sparkline(true)
        const n = idleFrames()
        verify(n <= maxIdleFrames, "frames while idle: " + n)
    }
}
