#include "traycontroller.h"

#include <QAction>
#include <QCursor>
#include <QGuiApplication>
#include <QLocalSocket>
#include <QMouseEvent>
#include <QPainter>
#include <QScreen>
#include <QSettings>
#include <QStandardPaths>

#include "../appid.h"
#include "trayplacement.h"
#include "trayresize.h"

#ifdef Q_OS_WIN
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>
#endif

namespace {

// A click on the icon right after the popup hid on focus loss (the click took
// the focus) must not open it again.
constexpr int REOPEN_GUARD_MS = 300;
constexpr int POPUP_WIDTH = 400;
constexpr int POPUP_HEIGHT = 640;
// Smallest popup the border can drag to: the timer card and a few rows still fit.
constexpr int POPUP_MIN_WIDTH = 320;
constexpr int POPUP_MIN_HEIGHT = 400;
// Logical px inside the popup's edge that resize it (no frame to grab otherwise).
constexpr int RESIZE_BORDER = 6;
// Open/close animation: fade in while sliding this far out of the taskbar, and back.
constexpr int SHOW_MS = 180;
constexpr int HIDE_MS = 130;
constexpr int SLIDE_DISTANCE = 16;
const QString SIZE_KEY = QStringLiteral("popup/size");
constexpr int HANDOVER_TIMEOUT_MS = 500;
const QByteArray SHOW_COMMAND = QByteArrayLiteral("show");

TrayController *s_instance = nullptr;

// tray.ini next to the app's other local files; QSettings without names would write nowhere.
QSettings traySettings()
{
    const QString dir = QStandardPaths::writableLocation(QStandardPaths::AppConfigLocation);
    return QSettings(dir + QStringLiteral("/tray.ini"), QSettings::IniFormat);
}

QString serverName()
{
    // Per user: another user's instance on the same machine is not ours.
    const QString user = qEnvironmentVariable("USERNAME", qEnvironmentVariable("USER"));
    return APP_ID + QStringLiteral(".tray.") + user;
}

} // namespace

bool TrayController::isSupported()
{
    return QSystemTrayIcon::isSystemTrayAvailable();
}

bool TrayController::handOverToRunning()
{
    QLocalSocket socket;
    socket.connectToServer(serverName());
    if (!socket.waitForConnected(HANDOVER_TIMEOUT_MS)) {
        return false;
    }
    socket.write(SHOW_COMMAND);
    socket.waitForBytesWritten(HANDOVER_TIMEOUT_MS);
    return true;
}

TrayController *TrayController::instance()
{
    return s_instance;
}

TrayController::TrayController(QObject *parent)
    : QObject(parent)
{
    s_instance = this;

    // A second start sends "show" (handOverToRunning).
    QLocalServer::removeServer(serverName());
    m_server.setSocketOptions(QLocalServer::UserAccessOption);
    m_server.listen(serverName());
    connect(&m_server, &QLocalServer::newConnection, this, [this]() {
        QLocalSocket *socket = m_server.nextPendingConnection();
        connect(socket, &QLocalSocket::readyRead, this, [this, socket]() {
            if (socket->readAll().startsWith(SHOW_COMMAND)) {
                showPopup();
            }
            socket->deleteLater();
        });
    });

    connect(&m_anim, &QVariantAnimation::valueChanged, this, [this](const QVariant &value) {
        applyShown(value.toReal());
    });
    connect(&m_anim, &QAbstractAnimation::finished, this, [this]() {
        if (m_hiding) {
            finishHide();
        }
    });

    m_icon.setContextMenu(&m_menu);
    connect(&m_icon, &QSystemTrayIcon::activated, this, [this](QSystemTrayIcon::ActivationReason reason) {
        if (reason == QSystemTrayIcon::Trigger) {
            toggle();
        }
    });
    m_toolTip = QStringLiteral("Plasmai");
    m_icon.setToolTip(m_toolTip);
    updateIcon();
    m_icon.show();
}

TrayController::~TrayController()
{
    saveSize();
    if (s_instance == this) {
        s_instance = nullptr;
    }
}

void TrayController::setWindow(QQuickWindow *window, bool hidden)
{
    m_window = window;
    if (!m_window) {
        return;
    }
    // A popup, not a window: no frame, no taskbar button, above the others.
    m_window->setFlags(Qt::Tool | Qt::FramelessWindowHint | Qt::WindowStaysOnTopHint);
    loadSize();
    m_window->resize(m_wantedSize);
    // The border resizes: pointer events reach this filter before the QML items.
    m_window->installEventFilter(this);
    // Like a Plasma popup: gone as soon as something else gets the focus.
    connect(m_window, &QWindow::activeChanged, this, [this]() {
        if (m_window && !m_window->isActive() && m_window->isVisible() && !m_hiding) {
            hidePopup();
        }
    });
    if (!hidden) {
        showPopup();
    }
}

void TrayController::setTracking(bool tracking)
{
    if (m_tracking == tracking) {
        return;
    }
    m_tracking = tracking;
    updateIcon();
    emit trackingChanged();
}

void TrayController::setToolTip(const QString &toolTip)
{
    if (m_toolTip == toolTip) {
        return;
    }
    m_toolTip = toolTip;
    m_icon.setToolTip(toolTip);
    emit toolTipChanged();
}

void TrayController::setMenu(const QVariantList &menu)
{
    if (m_menuModel == menu) {
        return;
    }
    m_menuModel = menu;
    rebuildMenu();
    emit menuChanged();
}

void TrayController::showPopup()
{
    if (!m_window) {
        return;
    }
    const bool opening = !m_window->isVisible();
    // Sliding out: turns around where it is. Otherwise (re)placed next to the icon.
    if (!m_hiding) {
        place();
    }
    m_hiding = false;
    if (opening) {
        m_shown = 0;
    }
    if (animationsEnabled()) {
        // Invisible at the start position before the first frame shows.
        applyShown(m_shown);
        animateTo(1);
    } else {
        m_anim.stop();
        applyShown(1);
    }
    m_window->show();
    m_window->raise();
    m_window->requestActivate();
}

void TrayController::hidePopup()
{
    if (!m_window || !m_window->isVisible() || m_hiding) {
        return;
    }
    saveSize();
    m_hiddenAt.start();
    if (!animationsEnabled()) {
        finishHide();
        return;
    }
    // Slides out from where it is now (dragging the border may have moved it).
    m_restPos = m_window->position();
    m_hiding = true;
    animateTo(0);
}

// Animates m_shown to `shown` (0 or 1); a turn halfway takes only the rest of the time.
void TrayController::animateTo(qreal shown)
{
    m_anim.stop();
    const bool opening = shown > m_shown;
    const int full = opening ? SHOW_MS : HIDE_MS;
    m_anim.setDuration(qMax(1, qRound(full * qAbs(shown - m_shown))));
    m_anim.setEasingCurve(opening ? QEasingCurve::OutCubic : QEasingCurve::InCubic);
    m_anim.setStartValue(m_shown);
    m_anim.setEndValue(shown);
    m_anim.start();
}

void TrayController::applyShown(qreal shown)
{
    m_shown = shown;
    if (!m_window) {
        return;
    }
    m_window->setOpacity(shown);
    m_window->setPosition(m_restPos + m_slide * (1 - shown));
}

void TrayController::finishHide()
{
    m_anim.stop();
    m_hiding = false;
    m_shown = 0;
    if (m_window) {
        m_window->hide();
        m_window->setOpacity(1);
        m_window->setPosition(m_restPos);
    }
}

// The system's "animation effects" setting (Windows: Accessibility > Visual effects).
bool TrayController::animationsEnabled()
{
#ifdef Q_OS_WIN
    BOOL enabled = TRUE;
    if (SystemParametersInfoW(SPI_GETCLIENTAREAANIMATION, 0, &enabled, 0)) {
        return enabled;
    }
#endif
    return true;
}

void TrayController::showMessage(const QString &title, const QString &body)
{
    // The plain app icon: the message is sent as the state changes, and the icon with the red
    // dot on "Stopped" (the tracking flag follows a moment later) was wrong.
    m_icon.showMessage(title, body, trayIcon(false));
}

void TrayController::toggle()
{
    if (!m_window) {
        return;
    }
    // Sliding out counts as hidden: the click that took the focus started it.
    if (m_window->isVisible() && !m_hiding) {
        hidePopup();
        return;
    }
    if (m_hiddenAt.isValid() && m_hiddenAt.elapsed() < REOPEN_GUARD_MS) {
        return;
    }
    showPopup();
}

void TrayController::place()
{
    const QRect icon = m_icon.geometry();
    const QPoint probe = icon.isValid() ? icon.center() : QCursor::pos();
    QScreen *screen = QGuiApplication::screenAt(probe);
    if (!screen) {
        screen = QGuiApplication::primaryScreen();
    }
    if (!screen) {
        return;
    }
    m_window->setScreen(screen);
    // Logical px: at 250 % a full HD screen has 432 px of height, less than the default popup.
    const QRect avail = screen->availableGeometry();
    const QSize minimum(POPUP_MIN_WIDTH, POPUP_MIN_HEIGHT);
    const QSize size = TrayPlacement::fitSize(m_wantedSize, minimum, avail);
    // The window system's resize (Windows: WM_GETMINMAXINFO) stops here too; never above the screen.
    m_window->setMinimumSize(minimum.boundedTo(avail.size()));
    m_window->resize(size);
    m_placedSize = size;
    m_restPos = TrayPlacement::popupPosition(icon, screen->geometry(), avail, size);
    m_slide = TrayPlacement::slideOffset(icon, screen->geometry(), avail, SLIDE_DISTANCE);
    m_window->setPosition(m_restPos);
}

bool TrayController::eventFilter(QObject *watched, QEvent *event)
{
    if (watched == m_window && onBorderEvent(event)) {
        return true;
    }
    return QObject::eventFilter(watched, event);
}

// Pointer on the popup's border: resize cursor, and a press there resizes. Returns
// true when the event was the border's (the QML items below do not get it then).
bool TrayController::onBorderEvent(QEvent *event)
{
    const QEvent::Type type = event->type();
    if (type != QEvent::MouseMove && type != QEvent::MouseButtonPress && type != QEvent::MouseButtonRelease) {
        return false;
    }
    auto *mouse = static_cast<QMouseEvent *>(event);
    const QRect avail = m_window->screen() ? m_window->screen()->availableGeometry() : m_window->geometry();
    const QSize minimum(POPUP_MIN_WIDTH, POPUP_MIN_HEIGHT);

    // Block: our own drag (platforms without startSystemResize) follows the pointer.
    if (m_dragEdges) {
        if (type == QEvent::MouseMove) {
            const QPoint delta = mouse->globalPosition().toPoint() - m_dragOrigin;
            m_window->setGeometry(TrayResize::resized(m_dragStart, m_dragEdges, delta, minimum, avail));
        } else if (type == QEvent::MouseButtonRelease) {
            m_dragEdges = Qt::Edges();
            saveSize();
        }
        return true;
    }

    const Qt::Edges edges = TrayResize::edgesAt(mouse->position(), m_window->size(), RESIZE_BORDER);

    // Block: hover. The resize cursor on the border; leaving it hands the cursor back to QML.
    if (type == QEvent::MouseMove && mouse->buttons() == Qt::NoButton) {
        if (edges) {
            m_window->setCursor(TrayResize::cursorFor(edges));
            m_resizeCursor = true;
            return true;
        }
        if (m_resizeCursor) {
            m_window->unsetCursor();
            m_resizeCursor = false;
        }
        return false;
    }

    // Block: press on the border. The window system resizes where it can (Windows, X11,
    // Wayland); otherwise the moves above do.
    if (type != QEvent::MouseButtonPress || mouse->button() != Qt::LeftButton || !edges) {
        return false;
    }
    if (m_window->startSystemResize(edges)) {
        return true;
    }
    m_dragEdges = edges;
    m_dragStart = m_window->geometry();
    m_dragOrigin = mouse->globalPosition().toPoint();
    return true;
}

void TrayController::loadSize()
{
    const QSize stored = traySettings().value(SIZE_KEY).toSize();
    m_wantedSize = stored.isValid() ? stored : QSize(POPUP_WIDTH, POPUP_HEIGHT);
}

// Only a size the user dragged to (it differs from the one place() set): a size fitted to a
// small screen must not stick on a large one, and a click on the border changes nothing.
void TrayController::saveSize()
{
    if (!m_window || !m_placedSize.isValid() || m_window->size() == m_placedSize) {
        return;
    }
    m_wantedSize = m_window->size();
    m_placedSize = m_wantedSize;
    traySettings().setValue(SIZE_KEY, m_wantedSize);
}

void TrayController::rebuildMenu()
{
    m_menu.clear();
    for (const QVariant &entry : std::as_const(m_menuModel)) {
        const QVariantMap item = entry.toMap();
        if (item.value(QStringLiteral("separator")).toBool()) {
            m_menu.addSeparator();
            continue;
        }
        QAction *action = m_menu.addAction(item.value(QStringLiteral("text")).toString());
        action->setEnabled(item.value(QStringLiteral("enabled"), true).toBool());
        action->setCheckable(item.value(QStringLiteral("checkable")).toBool());
        action->setChecked(item.value(QStringLiteral("checked")).toBool());
        const QString id = item.value(QStringLiteral("id")).toString();
        connect(action, &QAction::triggered, this, [this, id]() { emit menuTriggered(id); });
    }
}

void TrayController::updateIcon()
{
    m_icon.setIcon(trayIcon(m_tracking));
}

// The app icon; while tracking with a red dot, like the Plasmoid's running indicator (Kante).
QIcon TrayController::trayIcon(bool tracking)
{
    static const QIcon base(QStringLiteral(":/plasmai.svg"));
    if (!tracking) {
        return base;
    }
    QIcon out;
    for (const int size : {16, 20, 24, 32, 40, 48, 64}) {
        QPixmap pixmap = base.pixmap(size, size);
        QPainter painter(&pixmap);
        painter.setRenderHint(QPainter::Antialiasing);
        const qreal dot = size * 0.42;
        painter.setPen(QPen(Qt::white, qMax(1.0, size / 16.0)));
        painter.setBrush(QColor(0xda, 0x44, 0x53));
        painter.drawEllipse(QRectF(size - dot - 0.5, size - dot - 0.5, dot, dot));
        painter.end();
        out.addPixmap(pixmap);
    }
    return out;
}
