#include <QTest>

#include "platform/trayresize.h"

// Resizing the frameless tray popup by dragging its border: which edges the
// pointer is on, the cursor there, and the geometry while dragging.
class TstTrayResize : public QObject {
    Q_OBJECT

private slots:
    void edgesInside()
    {
        QCOMPARE(TrayResize::edgesAt(QPointF(200, 300), QSize(400, 640), 6), Qt::Edges());
    }

    void edgesSidesAndCorners()
    {
        const QSize size(400, 640);
        QCOMPARE(TrayResize::edgesAt(QPointF(2, 300), size, 6), Qt::Edges(Qt::LeftEdge));
        QCOMPARE(TrayResize::edgesAt(QPointF(397, 300), size, 6), Qt::Edges(Qt::RightEdge));
        QCOMPARE(TrayResize::edgesAt(QPointF(200, 0), size, 6), Qt::Edges(Qt::TopEdge));
        QCOMPARE(TrayResize::edgesAt(QPointF(200, 639), size, 6), Qt::Edges(Qt::BottomEdge));
        QCOMPARE(TrayResize::edgesAt(QPointF(1, 1), size, 6), Qt::TopEdge | Qt::LeftEdge);
        QCOMPARE(TrayResize::edgesAt(QPointF(399, 639), size, 6), Qt::BottomEdge | Qt::RightEdge);
    }

    // Outside the window (a grabbed drag) is no edge.
    void edgesOutside()
    {
        QCOMPARE(TrayResize::edgesAt(QPointF(-3, 300), QSize(400, 640), 6), Qt::Edges());
    }

    void cursors()
    {
        QCOMPARE(TrayResize::cursorFor(Qt::LeftEdge), Qt::SizeHorCursor);
        QCOMPARE(TrayResize::cursorFor(Qt::BottomEdge), Qt::SizeVerCursor);
        QCOMPARE(TrayResize::cursorFor(Qt::TopEdge | Qt::LeftEdge), Qt::SizeFDiagCursor);
        QCOMPARE(TrayResize::cursorFor(Qt::BottomEdge | Qt::RightEdge), Qt::SizeFDiagCursor);
        QCOMPARE(TrayResize::cursorFor(Qt::TopEdge | Qt::RightEdge), Qt::SizeBDiagCursor);
        QCOMPARE(TrayResize::cursorFor(Qt::BottomEdge | Qt::LeftEdge), Qt::SizeBDiagCursor);
    }

    // Popup above a bottom taskbar: dragging the top edge up grows it, the bottom stays.
    void dragTopEdge()
    {
        const QRect start(1520, 400, 400, 640);
        const QRect r = TrayResize::resized(start, Qt::TopEdge, QPoint(0, -100), QSize(320, 400), QRect(0, 0, 1920, 1040));
        QCOMPARE(r, QRect(1520, 300, 400, 740));
    }

    void dragLeftEdge()
    {
        const QRect start(1520, 400, 400, 640);
        const QRect r = TrayResize::resized(start, Qt::LeftEdge, QPoint(-80, 0), QSize(320, 400), QRect(0, 0, 1920, 1040));
        QCOMPARE(r, QRect(1440, 400, 480, 640));
    }

    // Not below the minimum: the opposite edge stays put.
    void minimum()
    {
        const QRect start(1520, 400, 400, 640);
        const QRect r = TrayResize::resized(start, Qt::TopEdge | Qt::LeftEdge, QPoint(300, 400), QSize(320, 400),
                                            QRect(0, 0, 1920, 1040));
        QCOMPARE(r, QRect(1600, 640, 320, 400));
    }

    // Not past the available area (the taskbar, the screen's edge).
    void bounds()
    {
        const QRect start(1520, 400, 400, 640);
        const QRect up = TrayResize::resized(start, Qt::TopEdge, QPoint(0, -1000), QSize(320, 400), QRect(0, 0, 1920, 1040));
        QCOMPARE(up, QRect(1520, 0, 400, 1040));
        const QRect right = TrayResize::resized(start, Qt::RightEdge, QPoint(500, 0), QSize(320, 400), QRect(0, 0, 1920, 1040));
        QCOMPARE(right, QRect(1520, 400, 400, 640));
    }
};

QTEST_GUILESS_MAIN(TstTrayResize)
#include "tst_trayresize.moc"
