.pragma library

// Quadratic arcs on a 2D canvas context, for the sun, moon and work arcs of the day chart.

/** Point on quadratic Bézier at t ∈ [0,1]. */
function quadPoint(x0, y0, cx, cy, x1, y1, t) {
    var u = 1 - t
    return {
        x: u * u * x0 + 2 * u * t * cx + t * t * x1,
        y: u * u * y0 + 2 * u * t * cy + t * t * y1
    }
}

/**
 * Soft glow along a quadratic arc that fades (and thins) toward the ends.
 * baseY/ctrlY/endY: absolute canvas coordinates.
 */
function strokeFadingGlow(ctx, x0, y0, cx, cy, x1, y1, color, maxWidth) {
    // Round-capped segments read as dots unless they overlap heavily.
    // Density tracks arc length (≈ span) and stroke width, with no low cap.
    var span = Math.abs(x1 - x0)
    var rise = Math.abs(cy - (y0 + y1) * 0.5)
    var approxLen = Math.sqrt(span * span + rise * rise * 4) * 1.05
    var spacing = Math.max(1.2, Math.min(2.2, maxWidth * 0.22))
    var steps = Math.max(48, Math.min(2400, Math.ceil(approxLen / spacing)))
    var prev = quadPoint(x0, y0, cx, cy, x1, y1, 0)
    var i
    for (i = 1; i <= steps; i++) {
        var t = i / steps
        var p = quadPoint(x0, y0, cx, cy, x1, y1, t)
        // Smooth fade: 0 at feet, 1 at apex
        var env = Math.sin(Math.PI * t)
        env = env * env
        if (env < 0.02) {
            prev = p
            continue
        }
        ctx.beginPath()
        ctx.moveTo(prev.x, prev.y)
        ctx.lineTo(p.x, p.y)
        ctx.strokeStyle = Qt.rgba(color.r, color.g, color.b, color.a * env)
        ctx.lineWidth = maxWidth * (0.35 + 0.65 * env)
        ctx.lineCap = "round"
        ctx.lineJoin = "round"
        ctx.setLineDash([])
        ctx.stroke()
        prev = p
    }
}

function strokeArcLine(ctx, x0, y0, cx, cy, x1, y1, color, width, dash) {
    ctx.beginPath()
    ctx.moveTo(x0, y0)
    ctx.quadraticCurveTo(cx, cy, x1, y1)
    ctx.strokeStyle = color
    ctx.lineWidth = width
    ctx.lineCap = "round"
    ctx.lineJoin = "round"
    if (dash && dash.length) {
        ctx.setLineDash(dash)
    } else {
        ctx.setLineDash([])
    }
    ctx.stroke()
    ctx.setLineDash([])
}
