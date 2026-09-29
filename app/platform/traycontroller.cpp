#include "traycontroller.h"

#include <QAction>
#include <QCursor>
#include <QGuiApplication>
#include <QLocalSocket>
#include <QPainter>
#include <QScreen>

#include "../appid.h"
#include "trayplacement.h"

namespace {

// A click on the icon right after the popup hid on focus loss (the click took
// the focus) must not open it again.
constexpr int REOPEN_GUARD_MS = 300;
constexpr int POPUP_WIDTH = 400;
constexpr int POPUP_HEIGHT = 640;
constexpr int HANDOVER_TIMEOUT_MS = 500;
const QByteArray SHOW_COMMAND = QByteArrayLiteral("show");

TrayController *s_instance = nullptr;

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
    m_window->resize(POPUP_WIDTH, POPUP_HEIGHT);
    // Like a Plasma popup: gone as soon as something else gets the focus.
    connect(m_window, &QWindow::activeChanged, this, [this]() {
        if (m_window && !m_window->isActive() && m_window->isVisible()) {
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
    place();
    m_window->show();
    m_window->raise();
    m_window->requestActivate();
}

void TrayController::hidePopup()
{
    if (m_window && m_window->isVisible()) {
        m_window->hide();
        m_hiddenAt.start();
    }
}

void TrayController::showMessage(const QString &title, const QString &body)
{
    m_icon.showMessage(title, body, trayIcon(m_tracking));
}

void TrayController::toggle()
{
    if (!m_window) {
        return;
    }
    if (m_window->isVisible()) {
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
    m_window->setPosition(TrayPlacement::popupPosition(icon, screen->geometry(), screen->availableGeometry(),
                                                       m_window->size()));
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
