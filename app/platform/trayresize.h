#pragma once

#include <QPoint>
#include <QPointF>
#include <QRect>
#include <QSize>
#include <algorithm>

// -- TrayResize: dragging the frameless tray popup's border -------------------
// The popup has no frame of its own, so TrayController finds the edges under the
// pointer and resizes: through the window system where it can
// (QWindow::startSystemResize), else by this geometry while the pointer moves.
// Pure, so it is tested on any platform (tests/tst_trayresize.cpp).
//
//   ┌─┬──────────── top ────────────┬─┐    border: a few logical px inside
//   ├─┘                             └─┤    the window; corners are two edges
//   left            content       right
//   ├─┐                             ┌─┤
//   └─┴─────────── bottom ──────────┴─┘
namespace TrayResize {

// The edges `pos` (window coordinates) is within `border` of; none outside the window.
inline Qt::Edges edgesAt(const QPointF &pos, const QSize &size, int border)
{
    Qt::Edges edges;
    if (pos.x() < 0 || pos.y() < 0 || pos.x() >= size.width() || pos.y() >= size.height()) {
        return edges;
    }
    if (pos.x() < border) {
        edges |= Qt::LeftEdge;
    }
    if (pos.x() >= size.width() - border) {
        edges |= Qt::RightEdge;
    }
    if (pos.y() < border) {
        edges |= Qt::TopEdge;
    }
    if (pos.y() >= size.height() - border) {
        edges |= Qt::BottomEdge;
    }
    return edges;
}

// The pointer shape over these edges.
inline Qt::CursorShape cursorFor(Qt::Edges edges)
{
    const bool horizontal = edges & (Qt::LeftEdge | Qt::RightEdge);
    const bool vertical = edges & (Qt::TopEdge | Qt::BottomEdge);
    if (horizontal && vertical) {
        // "\" for top left and bottom right, "/" for the other two corners.
        const bool topLeft = (edges & Qt::TopEdge) && (edges & Qt::LeftEdge);
        const bool bottomRight = (edges & Qt::BottomEdge) && (edges & Qt::RightEdge);
        return topLeft || bottomRight ? Qt::SizeFDiagCursor : Qt::SizeBDiagCursor;
    }
    return horizontal ? Qt::SizeHorCursor : Qt::SizeVerCursor;
}

// The geometry after dragging `edges` of `start` by `delta`: the dragged edges move,
// the others stay; at least `minimum` and inside `bounds` (the available area).
inline QRect resized(const QRect &start, Qt::Edges edges, const QPoint &delta, const QSize &minimum,
                     const QRect &bounds)
{
    int left = start.left();
    int top = start.top();
    int right = start.right();
    int bottom = start.bottom();

    // Block: each dragged edge, stopped by the minimum and by the bounds.
    if (edges & Qt::LeftEdge) {
        left = std::clamp(left + delta.x(), bounds.left(), right + 1 - minimum.width());
    }
    if (edges & Qt::RightEdge) {
        right = std::clamp(right + delta.x(), left - 1 + minimum.width(), bounds.right());
    }
    if (edges & Qt::TopEdge) {
        top = std::clamp(top + delta.y(), bounds.top(), bottom + 1 - minimum.height());
    }
    if (edges & Qt::BottomEdge) {
        bottom = std::clamp(bottom + delta.y(), top - 1 + minimum.height(), bounds.bottom());
    }
    return QRect(QPoint(left, top), QPoint(right, bottom));
}

} // namespace TrayResize
