import "../code/arcDraw.js" as Arc
import "../code/solar.js" as Solar
import QtQuick
import QtQuick.Effects
import org.kde.kirigami as Kirigami
import "Kante"

/**
 * Sun and moon over the day bar: their arcs with soft ribbons, rise/set chevrons and the
 * icons on the arcs. Soft holes under the header text come in through arcCutouts.
 */
Item {
    id: root

    /** Solar.daySkyModel of the day. */
    property var sky: ({})
    /** Part of the day shown, as day fractions [0,1]. */
    property real viewStart: 0
    property real viewSpan: 1
    /** Soft holes under header text: { x, y, w, h } in this item's coordinates. */
    property var arcCutouts: []
    property int iconSize: 18
    /** Height of the sun and moon arcs above the bottom edge. */
    property int peakSun: 12
    property int peakMoon: 12
    property bool lightBg: false
    /** False where Qt cannot draw masks (software renderer): the icon spins unmasked. */
    property bool masksRender: true
    /** Parent flyout open: the icon animator must not run while collapsed. */
    property bool flyoutOpen: true

    readonly property color sunStroke: Qt.rgba(1, 0.78, 0.28, lightBg ? 0.85 : 0.9)
    // Soft ribbons along arcs (not solid humps) so overlaps stay readable
    readonly property color sunRibbon: Qt.rgba(1, 0.78, 0.35, lightBg ? 0.28 : 0.35)
    readonly property color moonStroke: Qt.rgba(0.75, 0.82, 1, lightBg ? 0.75 : 0.85)
    readonly property color moonRibbon: Qt.rgba(0.6, 0.7, 1, lightBg ? 0.22 : 0.28)

    /** Map a day fraction [0,1] into the zoomed view [0,1] (may fall outside). */
    function mapX(dayFrac) {
        return (dayFrac - root.viewStart) / root.viewSpan
    }

    function inView(dayFrac, pad) {
        var p = (typeof pad === "number") ? pad : 0.02
        var x = root.mapX(dayFrac)
        return x >= -p && x <= 1 + p
    }

    // Draw sun/moon icons into a given canvas context (used so arc cutouts
    // can destination-out the icons when they overlap header text).
    function drawSunIconCanvas(ctx, cx, cy, s) {
        ctx.save()
        ctx.translate(cx, cy)

        // Background disc
        ctx.beginPath()
        ctx.arc(0, 0, s * 0.48, 0, Math.PI * 2)
        ctx.fillStyle = KanteStyle.tint(KanteStyle.backgroundColor, 0.94)
        ctx.fill()

        // Outline stroke
        ctx.strokeStyle = root.sunStroke
        ctx.lineWidth = Math.max(1.2, s * 0.06)
        ctx.lineCap = "round"
        ctx.stroke()

        // Rays
        ctx.strokeStyle = root.sunStroke
        ctx.fillStyle = root.sunStroke
        ctx.lineWidth = Math.max(1, s * 0.08)
        ctx.lineCap = "round"
        var i
        for (i = 0; i < 8; i++) {
            var a = i * Math.PI / 4
            ctx.beginPath()
            ctx.moveTo(Math.cos(a) * s * 0.22, Math.sin(a) * s * 0.22)
            ctx.lineTo(Math.cos(a) * s * 0.36, Math.sin(a) * s * 0.36)
            ctx.stroke()
        }

        // Inner disc
        ctx.beginPath()
        ctx.arc(0, 0, s * 0.16, 0, Math.PI * 2)
        ctx.fill()

        ctx.restore()
    }

    /** Soft destination-out holes so arcs vanish under header text. */
    function punchArcCutouts(ctx, cutouts) {
        if (!cutouts || !cutouts.length) {
            return
        }
        // Extra-wide soft falloff; vertical closeness comes from cutout height inset.
        var feather = Math.max(36, Math.round(Kirigami.Units.gridUnit * 2.1))
        var steps = Math.max(26, Math.round(feather * 1.1))
        ctx.save()
        ctx.globalCompositeOperation = "destination-out"
        var i
        var s
        for (i = 0; i < cutouts.length; i++) {
            var c = cutouts[i]
            if (!c || !(c.w > 0) || !(c.h > 0)) {
                continue
            }
            for (s = 0; s < steps; s++) {
                var t = s / Math.max(1, steps - 1)
                var expand = feather * (1 - t)
                // Soft falloff — erase weak until close to the cutout core
                var alpha = Math.pow(t, 2.6)
                if (alpha < 0.015) {
                    continue
                }
                ctx.beginPath()
                var x = c.x - expand
                var y = c.y - expand
                var rw = c.w + expand * 2
                var rh = c.h + expand * 2
                var r = Math.min(rh * 0.5, 10 + expand * 0.55)
                ctx.moveTo(x + r, y)
                ctx.lineTo(x + rw - r, y)
                ctx.quadraticCurveTo(x + rw, y, x + rw, y + r)
                ctx.lineTo(x + rw, y + rh - r)
                ctx.quadraticCurveTo(x + rw, y + rh, x + rw - r, y + rh)
                ctx.lineTo(x + r, y + rh)
                ctx.quadraticCurveTo(x, y + rh, x, y + rh - r)
                ctx.lineTo(x, y + r)
                ctx.quadraticCurveTo(x, y, x + r, y)
                ctx.closePath()
                ctx.fillStyle = Qt.rgba(0, 0, 0, Math.min(1, alpha))
                ctx.fill()
            }
            // Solid core = inset cutout bounds
            ctx.beginPath()
            var cx = c.x
            var cy = c.y
            var cw = c.w
            var ch = c.h
            var cr = Math.min(ch * 0.4, 4)
            ctx.moveTo(cx + cr, cy)
            ctx.lineTo(cx + cw - cr, cy)
            ctx.quadraticCurveTo(cx + cw, cy, cx + cw, cy + cr)
            ctx.lineTo(cx + cw, cy + ch - cr)
            ctx.quadraticCurveTo(cx + cw, cy + ch, cx + cw - cr, cy + ch)
            ctx.lineTo(cx + cr, cy + ch)
            ctx.quadraticCurveTo(cx, cy + ch, cx, cy + ch - cr)
            ctx.lineTo(cx, cy + cr)
            ctx.quadraticCurveTo(cx, cy, cx + cr, cy)
            ctx.closePath()
            ctx.fillStyle = Qt.rgba(0, 0, 0, 1)
            ctx.fill()
        }
        ctx.restore()
    }

    function pointInCutouts(px, py) {
        var cutouts = root.arcCutouts
        if (!cutouts || !cutouts.length) {
            return false
        }
        var i
        for (i = 0; i < cutouts.length; i++) {
            var c = cutouts[i]
            if (!c) {
                continue
            }
            var pad = Math.max(4, Math.round(Kirigami.Units.smallSpacing * 0.5))
            if (px >= c.x - pad && px <= c.x + c.w + pad
                && py >= c.y - pad && py <= c.y + c.h + pad) {
                return true
            }
        }
        return false
    }

    readonly property var sunPoint: {
        var _force = root.nowTick
        var s = root.sky.sun || {}
        if (s.polarDay) {
            return Solar.arcPoint(0, 1, root.sky.now, false)
        }
        if (s.polarNight || !s.valid) {
            return { visible: false, xFrac: 0, yNorm: 0, t: 0 }
        }
        return Solar.arcPoint(s.sunrise, s.sunset, root.sky.now, false)
    }
    readonly property var moonPoint: {
        var _force = root.nowTick
        var m = root.sky.moon || {}
        if (!m.valid || m.alwaysDown) {
            return { visible: false, xFrac: 0, yNorm: 0, t: 0 }
        }
        if (m.alwaysUp) {
            return Solar.arcPoint(0, 1, root.sky.now, false)
        }
        return Solar.arcPoint(m.moonrise, m.moonset, root.sky.now, !!m.wraps)
    }


    Canvas {
        id: skyCanvas
        anchors.fill: parent
        antialiasing: true

        function repaint() { requestPaint() }

        Connections {
            target: root
            function onSkyChanged() { skyCanvas.repaint() }
            function onViewStartChanged() { skyCanvas.repaint() }
            function onViewSpanChanged() { skyCanvas.repaint() }
            function onWidthChanged() { skyCanvas.repaint() }
            function onVisibleChanged() { skyCanvas.repaint() }
            function onArcCutoutsChanged() { skyCanvas.repaint() }
        }
        onWidthChanged: repaint()
        onHeightChanged: repaint()
        Component.onCompleted: repaint()

        onPaint: {
            var ctx = getContext("2d")
            var w = width
            var h = height
            if (w < 2 || h < 2) {
                return
            }
            ctx.clearRect(0, 0, w, h)
            var skyModel = root.sky
            var sun = skyModel.sun || {}
            var moon = skyModel.moon || {}

            function drawSpan(rise, set, wraps, peak, ribbon, stroke, dash) {
                if (wraps) {
                    drawCurve(rise, 1, peak, ribbon, stroke, dash)
                    drawCurve(0, set, peak, ribbon, stroke, dash)
                } else if (set > rise) {
                    drawCurve(rise, set, peak, ribbon, stroke, dash)
                }
            }

            function drawCurve(rise, set, peak, ribbon, stroke, dash) {
                if (!(set > rise)) {
                    return
                }
                var x0 = root.mapX(rise) * w
                var x1 = root.mapX(set) * w
                var mid = (x0 + x1) / 2
                var base = h - 0.5
                var top = base - peak
                var glowW = Math.max(4, Math.min(9, peak * 0.28))
                Arc.strokeFadingGlow(ctx, x0, base, mid, top, x1, base, ribbon, glowW)
                Arc.strokeArcLine(ctx, x0, base, mid, top, x1, base, stroke, 1.15, dash)
            }

            if (sun.valid && !sun.polarNight) {
                if (sun.polarDay) {
                    drawSpan(0, 1, false, root.peakSun, root.sunRibbon, root.sunStroke, [])
                } else {
                    drawSpan(sun.sunrise, sun.sunset, false, root.peakSun,
                             root.sunRibbon, root.sunStroke, [])
                }
            }
            if (moon.valid && !moon.alwaysDown) {
                if (moon.alwaysUp) {
                    drawSpan(0, 1, false, root.peakMoon, root.moonRibbon, root.moonStroke, [2, 2])
                } else {
                    drawSpan(moon.moonrise, moon.moonset, !!moon.wraps, root.peakMoon,
                             root.moonRibbon, root.moonStroke, [2, 2])
                }
            }

            // Feathered holes under timer / customer — no dark scrim, just no arcs
            root.punchArcCutouts(ctx, root.arcCutouts)
        }
    }

    // Rise / set downward chevrons at arc feet
    Repeater {
        model: {
            var out = []
            var s = root.sky.sun || {}
            var m = root.sky.moon || {}
            if (s.valid && !s.polarNight && !s.polarDay) {
                out.push({ frac: s.sunrise, kind: "sun" })
                out.push({ frac: s.sunset, kind: "sun" })
            }
            if (m.valid && !m.alwaysUp && !m.alwaysDown) {
                out.push({ frac: m.moonrise, kind: "moon" })
                out.push({ frac: m.moonset, kind: "moon" })
            }
            return out
        }
        delegate: Item {
            required property var modelData
            visible: {
                if (!root.inView(modelData.frac || 0, 0.01)) {
                    return false
                }
                var ix = root.mapX(modelData.frac || 0) * root.width
                var iy = root.height - 2
                return !root.pointInCutouts(ix, iy)
            }
            width: 7
            height: 5
            x: Math.round(root.mapX(modelData.frac || 0) * root.width) - width / 2
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 0
            z: 2

            Canvas {
                anchors.fill: parent
                antialiasing: true
                onPaint: {
                    var ctx = getContext("2d")
                    ctx.clearRect(0, 0, width, height)
                    ctx.beginPath()
                    ctx.moveTo(0.5, 0.5)
                    ctx.lineTo(width / 2, height - 0.5)
                    ctx.lineTo(width - 0.5, 0.5)
                    ctx.strokeStyle = modelData.kind === "sun" ? root.sunStroke : root.moonStroke
                    ctx.lineWidth = 1.25
                    ctx.lineCap = "round"
                    ctx.lineJoin = "round"
                    ctx.stroke()
                }
                Component.onCompleted: requestPaint()
            }
        }
    }

    // Sun icon on the arc. Rotation is a scene-graph transform (no skyCanvas
    // repaint). Header cutouts are applied with a mask in sky space so the
    // holes stay fixed while the glyph spins.
    Item {
        id: sunSlot
        readonly property var pos: {
            var sp = root.sunPoint
            if (!sp.visible || !(sp.t > 0) || !root.inView(sp.xFrac, 0.02)) {
                return { visible: false, x: 0, y: 0 }
            }
            var sunModel = (root.sky && root.sky.sun) ? root.sky.sun : {}
            var sRise = sunModel.polarDay ? 0 : sunModel.sunrise
            var sSet = sunModel.polarDay ? 1 : sunModel.sunset
            var w = root.width
            var h = root.height
            if (w < 2 || h < 2) {
                return { visible: false, x: 0, y: 0 }
            }
            var sx0 = root.mapX(sRise) * w
            var sx1 = root.mapX(sSet) * w
            var sMid = (sx0 + sx1) / 2
            var arcBase = h - 0.5
            var sTop = arcBase - root.peakSun
            var sP = Arc.quadPoint(sx0, arcBase, sMid, sTop, sx1, arcBase, sp.t)
            return { visible: true, x: sP.x, y: sP.y }
        }
        visible: pos.visible
        width: root.iconSize
        height: root.iconSize
        x: pos.x - width / 2
        y: pos.y - height / 2
        z: 4
        onXChanged: sunMask.requestPaint()
        onYChanged: sunMask.requestPaint()

        Item {
            id: sunSpin
            anchors.fill: parent
            visible: !root.masksRender
            transformOrigin: Item.Center

            RotationAnimator on rotation {
                from: 0
                to: 360
                duration: 48000
                loops: Animation.Infinite
                // Hidden (masks drawn by the GPU): a running animator still redraws every frame.
                running: sunSpin.visible && sunSlot.visible && root.visible && root.flyoutOpen
            }

            Canvas {
                id: sunIconCanvas
                anchors.fill: parent
                antialiasing: true
                onPaint: {
                    var ctx = getContext("2d")
                    ctx.clearRect(0, 0, width, height)
                    root.drawSunIconCanvas(ctx, width / 2, height / 2, width)
                }
                Component.onCompleted: requestPaint()
                onWidthChanged: requestPaint()
                onHeightChanged: requestPaint()
                Connections {
                    target: root
                    function onSunStrokeChanged() { sunIconCanvas.requestPaint() }
                    function onLightBgChanged() { sunIconCanvas.requestPaint() }
                }
            }
        }

        Canvas {
            id: sunMask
            anchors.fill: parent
            visible: false
            layer.enabled: true
            onPaint: {
                var ctx = getContext("2d")
                var w = width
                var h = height
                if (w < 2 || h < 2) {
                    return
                }
                ctx.clearRect(0, 0, w, h)
                ctx.fillStyle = "#ffffff"
                ctx.fillRect(0, 0, w, h)
                var cuts = root.arcCutouts || []
                var locals = []
                var i
                for (i = 0; i < cuts.length; i++) {
                    var c = cuts[i]
                    if (!c) {
                        continue
                    }
                    locals.push({
                        x: c.x - sunSlot.x,
                        y: c.y - sunSlot.y,
                        w: c.w,
                        h: c.h
                    })
                }
                root.punchArcCutouts(ctx, locals)
            }
            Component.onCompleted: requestPaint()
            Connections {
                target: root
                function onArcCutoutsChanged() { sunMask.requestPaint() }
            }
        }

        // Qt Quick's own mask (Qt5Compat's OpacityMask is gone): alpha of sunMask,
        // with a soft edge like the old alpha multiply.
        MultiEffect {
            anchors.fill: parent
            visible: root.masksRender
            source: sunSpin
            maskEnabled: true
            maskSource: sunMask
            maskThresholdMin: 0.5
            maskSpreadAtMin: 1.0
        }
    }

    // Moon icon on path (same glyph as before; not composited into skyCanvas)
    Item {
        id: moonIcon
        visible: {
            if (!root.moonPoint.visible || !root.inView(root.moonPoint.xFrac, 0.02)) {
                return false
            }
            var ix = root.mapX(root.moonPoint.xFrac) * root.width
            var iy = root.height - root.moonPoint.yNorm * root.peakMoon
            return !root.pointInCutouts(ix, iy)
        }
        width: root.iconSize
        height: root.iconSize
        x: (root.mapX(root.moonPoint.xFrac) * root.width) - width / 2
        y: (root.height - root.moonPoint.yNorm * root.peakMoon) - height / 2
        opacity: 0
        z: 4

        Canvas {
            id: moonIconCanvas
            anchors.fill: parent
            antialiasing: true
            onPaint: {
                var ctx = getContext("2d")
                var s = width
                var cx = s / 2
                var cy = s / 2
                var r = s * 0.16
                ctx.clearRect(0, 0, s, s)

                ctx.beginPath()
                ctx.arc(cx, cy, s * 0.48, 0, Math.PI * 2)
                ctx.fillStyle = KanteStyle.tint(KanteStyle.backgroundColor, 0.94)
                ctx.fill()
                ctx.strokeStyle = root.moonStroke
                ctx.lineWidth = Math.max(1.2, s * 0.06)
                ctx.stroke()

                ctx.fillStyle = root.moonStroke
                ctx.beginPath()
                ctx.arc(cx, cy, r, 0, Math.PI * 2)
                ctx.fill()
                ctx.globalCompositeOperation = "destination-out"
                ctx.beginPath()
                ctx.arc(cx + r * 0.38, cy - r * 0.08, r * 0.78, 0, Math.PI * 2)
                ctx.fill()
                ctx.globalCompositeOperation = "source-over"
            }
            Component.onCompleted: requestPaint()
            Connections {
                target: root
                function onMoonStrokeChanged() { moonIconCanvas.requestPaint() }
                function onLightBgChanged() { moonIconCanvas.requestPaint() }
            }
        }
    }
}
