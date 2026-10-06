#include <QTest>

#include "platform/trayplacement.h"

// Where the tray popup opens: next to the icon, on the taskbar's side, inside
// the screen's available area (the part the taskbar does not cover).
class TstTrayPlacement : public QObject {
    Q_OBJECT

private slots:
    void taskbarBottom()
    {
        const QRect screen(0, 0, 1920, 1080);
        const QRect avail(0, 0, 1920, 1040);   // 40 px taskbar at the bottom
        const QRect icon(1800, 1044, 32, 32);
        const QPoint p = TrayPlacement::popupPosition(icon, screen, avail, QSize(400, 620));
        QCOMPARE(p, QPoint(1520, 420));        // right edge of the screen, above the taskbar
    }

    // The open/close animation slides from the taskbar's side.
    void slideOffset()
    {
        const QRect screen(0, 0, 1920, 1080);
        const QRect icon(1800, 1044, 32, 32);
        QCOMPARE(TrayPlacement::slideOffset(icon, screen, QRect(0, 0, 1920, 1040), 20), QPoint(0, 20));
        QCOMPARE(TrayPlacement::slideOffset(icon, screen, QRect(0, 40, 1920, 1040), 20), QPoint(0, -20));
        QCOMPARE(TrayPlacement::slideOffset(icon, screen, QRect(48, 0, 1872, 1080), 20), QPoint(-20, 0));
        QCOMPARE(TrayPlacement::slideOffset(icon, screen, QRect(0, 0, 1872, 1080), 20), QPoint(20, 0));
    }

    void taskbarBottomIconInMiddle()
    {
        const QPoint p = TrayPlacement::popupPosition(QRect(900, 1044, 32, 32), QRect(0, 0, 1920, 1080),
                                                      QRect(0, 0, 1920, 1040), QSize(400, 620));
        QCOMPARE(p, QPoint(715, 420));         // centred on the icon (QRect::center() is 915)
    }

    void taskbarTop()
    {
        const QPoint p = TrayPlacement::popupPosition(QRect(1800, 4, 32, 32), QRect(0, 0, 1920, 1080),
                                                      QRect(0, 40, 1920, 1040), QSize(400, 620));
        QCOMPARE(p, QPoint(1520, 40));
    }

    void taskbarLeft()
    {
        const QPoint p = TrayPlacement::popupPosition(QRect(8, 1000, 32, 32), QRect(0, 0, 1920, 1080),
                                                      QRect(48, 0, 1872, 1080), QSize(400, 620));
        QCOMPARE(p, QPoint(48, 460));          // beside the taskbar, as low as fits
    }

    void taskbarRight()
    {
        const QPoint p = TrayPlacement::popupPosition(QRect(1880, 100, 32, 32), QRect(0, 0, 1920, 1080),
                                                      QRect(0, 0, 1872, 1080), QSize(400, 620));
        QCOMPARE(p, QPoint(1472, 0));
    }

    // Auto-hidden taskbar (available == screen): the icon's side of the screen decides.
    void autoHiddenTaskbar()
    {
        const QPoint p = TrayPlacement::popupPosition(QRect(1800, 1050, 32, 32), QRect(0, 0, 1920, 1080),
                                                      QRect(0, 0, 1920, 1080), QSize(400, 620));
        QCOMPARE(p, QPoint(1520, 1050 - 620));
    }

    // No icon geometry (some platforms): bottom right of the available area.
    void unknownIcon()
    {
        const QPoint p = TrayPlacement::popupPosition(QRect(), QRect(0, 0, 1920, 1080),
                                                      QRect(0, 0, 1920, 1040), QSize(400, 620));
        QCOMPARE(p, QPoint(1520, 420));
    }

    // A popup larger than the screen starts at its top left.
    void tooLarge()
    {
        const QPoint p = TrayPlacement::popupPosition(QRect(600, 740, 32, 32), QRect(0, 0, 800, 780),
                                                      QRect(0, 0, 800, 740), QSize(900, 900));
        QCOMPARE(p, QPoint(0, 0));
    }

    // 1920×1080 at 250 % is 768×432 logical px: the 400×640 popup must shrink to the
    // available area, or its bottom and the buttons there are off the screen.
    void fitSizeHighDpi()
    {
        const QSize s = TrayPlacement::fitSize(QSize(400, 640), QSize(320, 400), QRect(0, 0, 768, 416));
        QCOMPARE(s, QSize(400, 416));
    }

    // The wanted size where it fits; never below the minimum while the screen allows it.
    void fitSizeKeepsWanted()
    {
        QCOMPARE(TrayPlacement::fitSize(QSize(400, 640), QSize(320, 400), QRect(0, 0, 1920, 1040)), QSize(400, 640));
        QCOMPARE(TrayPlacement::fitSize(QSize(100, 100), QSize(320, 400), QRect(0, 0, 1920, 1040)), QSize(320, 400));
    }

    // A screen smaller than the minimum: the screen wins.
    void fitSizeTinyScreen()
    {
        QCOMPARE(TrayPlacement::fitSize(QSize(400, 640), QSize(320, 400), QRect(0, 0, 300, 380)), QSize(300, 380));
    }

    // A second screen to the right (negative and offset coordinates).
    void secondScreen()
    {
        const QPoint p = TrayPlacement::popupPosition(QRect(3700, 1044, 32, 32), QRect(1920, 0, 1920, 1080),
                                                      QRect(1920, 0, 1920, 1040), QSize(400, 620));
        QCOMPARE(p, QPoint(3440, 420));
    }
};

QTEST_GUILESS_MAIN(TstTrayPlacement)
#include "tst_trayplacement.moc"
