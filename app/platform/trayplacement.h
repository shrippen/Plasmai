#pragma once

#include <QPoint>
#include <QRect>
#include <QSize>
#include <algorithm>

// -- TrayPlacement: where the tray popup opens ---------------------------------
// Next to the tray icon, on the taskbar's side of the screen, inside the
// available area (the part the taskbar does not cover). Pure, so it is tested
// on any platform (tests/tst_trayplacement.cpp).
namespace TrayPlacement {

enum class Edge { Bottom, Top, Left, Right };

// The taskbar's edge: where the available area is smaller than the screen; with
// an auto-hidden taskbar (no difference) the screen edge nearest to the icon.
inline Edge taskbarEdge(const QRect &icon, const QRect &screen, const QRect &avail)
{
    if (avail.bottom() < screen.bottom()) {
        return Edge::Bottom;
    }
    if (avail.top() > screen.top()) {
        return Edge::Top;
    }
    if (avail.left() > screen.left()) {
        return Edge::Left;
    }
    if (avail.right() < screen.right()) {
        return Edge::Right;
    }
    if (!icon.isValid()) {
        return Edge::Bottom;
    }
    const QPoint c = icon.center();
    const int toBottom = screen.bottom() - c.y();
    const int toTop = c.y() - screen.top();
    const int toLeft = c.x() - screen.left();
    const int toRight = screen.right() - c.x();
    const int nearest = std::min({toBottom, toTop, toLeft, toRight});
    if (nearest == toBottom) {
        return Edge::Bottom;
    }
    if (nearest == toTop) {
        return Edge::Top;
    }
    return nearest == toLeft ? Edge::Left : Edge::Right;
}

// The popup's size on this screen: the wanted size, at least `minimum`, never larger
// than the available area. Sizes are logical pixels, so scaling shrinks the room:
// 1920×1080 at 250 % is 768×432, where a 640 px high popup would run off the screen.
inline QSize fitSize(const QSize &wanted, const QSize &minimum, const QRect &avail)
{
    const int w = std::min(std::max(wanted.width(), minimum.width()), avail.width());
    const int h = std::min(std::max(wanted.height(), minimum.height()), avail.height());
    return QSize(w, h);
}

// Top left of a popup of `size`. icon may be empty (unknown): the popup then
// opens at the corner of the taskbar's side, bottom right by default.
inline QPoint popupPosition(const QRect &icon, const QRect &screen, const QRect &avail, const QSize &size)
{
    const Edge edge = taskbarEdge(icon, screen, avail);
    const QPoint anchor = icon.isValid() ? icon.center() : QPoint(avail.right(), avail.bottom());
    const int w = size.width();
    const int h = size.height();
    int x = anchor.x() - w / 2;
    int y = anchor.y() - h / 2;
    switch (edge) {
    case Edge::Bottom:
        y = (icon.isValid() ? std::min(avail.bottom() + 1, icon.top()) : avail.bottom() + 1) - h;
        break;
    case Edge::Top:
        y = icon.isValid() ? std::max(avail.top(), icon.bottom() + 1) : avail.top();
        break;
    case Edge::Left:
        x = icon.isValid() ? std::max(avail.left(), icon.right() + 1) : avail.left();
        break;
    case Edge::Right:
        x = (icon.isValid() ? std::min(avail.right() + 1, icon.left()) : avail.right() + 1) - w;
        break;
    }
    // Inside the available area; a popup larger than it starts at its top left.
    x = std::max(avail.left(), std::min(x, avail.right() + 1 - w));
    y = std::max(avail.top(), std::min(y, avail.bottom() + 1 - h));
    return QPoint(x, y);
}

// Where the popup slides from as it opens (and back to as it closes): `distance` px
// towards the taskbar, so it seems to come out of it.
inline QPoint slideOffset(const QRect &icon, const QRect &screen, const QRect &avail, int distance)
{
    switch (taskbarEdge(icon, screen, avail)) {
    case Edge::Bottom:
        return QPoint(0, distance);
    case Edge::Top:
        return QPoint(0, -distance);
    case Edge::Left:
        return QPoint(-distance, 0);
    case Edge::Right:
        return QPoint(distance, 0);
    }
    return QPoint(0, distance);
}

} // namespace TrayPlacement
