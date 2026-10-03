#include "trackingnotice.h"

#include <QDBusConnection>
#include <QDBusInterface>
#include <QDBusReply>
#include <QGuiApplication>
#include <QVariantMap>

namespace {
const QString SERVICE = QStringLiteral("org.freedesktop.Notifications");
const QString PATH = QStringLiteral("/org/freedesktop/Notifications");
const QString INTERFACE = QStringLiteral("org.freedesktop.Notifications");
const QString DEFAULT_ACTION = QStringLiteral("default");
constexpr int NEVER_EXPIRE = 0;
}

// Holds the shown notification's id and takes the server's signals (a D-Bus
// connection needs a slot by name).
class DbusNotice : public QObject {
    Q_OBJECT
public:
    explicit DbusNotice(TrackingNotice *notice)
        : QObject(notice), m_notice(notice)
    {
        auto bus = QDBusConnection::sessionBus();
        bus.connect(SERVICE, PATH, INTERFACE, QStringLiteral("ActionInvoked"),
                    this, SLOT(onAction(uint, QString)));
        bus.connect(SERVICE, PATH, INTERFACE, QStringLiteral("ActivationToken"),
                    this, SLOT(onToken(uint, QString)));
        bus.connect(SERVICE, PATH, INTERFACE, QStringLiteral("NotificationClosed"),
                    this, SLOT(onClosed(uint, uint)));
    }

    uint id = 0;

private slots:
    // Comes before ActionInvoked: lets the window raise itself on Wayland.
    void onToken(uint notificationId, const QString &token)
    {
        if (notificationId != id) {
            return;
        }
        qputenv("XDG_ACTIVATION_TOKEN", token.toUtf8());
    }

    void onAction(uint notificationId, const QString &key)
    {
        if (notificationId != id || key != DEFAULT_ACTION) {
            return;
        }
        emit m_notice->activated();
    }

    void onClosed(uint notificationId, uint)
    {
        if (notificationId != id) {
            return;
        }
        id = 0;
    }

private:
    TrackingNotice *m_notice;
};

TrackingNotice::TrackingNotice(QObject *parent)
    : QObject(parent)
{
    new DbusNotice(this);
}

bool TrackingNotice::isSupported()
{
    return true;
}

void TrackingNotice::show(const QString &title, const QString &text, qint64)
{
    auto *dbus = findChild<DbusNotice *>(Qt::FindDirectChildrenOnly);
    QDBusInterface iface(SERVICE, PATH, INTERFACE, QDBusConnection::sessionBus());
    if (!iface.isValid()) {
        return;
    }

    // Resident and never expiring: it stays until hide(). Same id = replaced in place.
    QVariantMap hints;
    hints.insert(QStringLiteral("resident"), true);
    hints.insert(QStringLiteral("desktop-entry"), QGuiApplication::desktopFileName());
    QDBusReply<uint> reply = iface.call(
        QStringLiteral("Notify"),
        QGuiApplication::applicationDisplayName(),
        dbus->id,
        QStringLiteral("chronometer"),
        title,
        text,
        QStringList{DEFAULT_ACTION, QString()},
        hints,
        NEVER_EXPIRE);
    if (reply.isValid()) {
        dbus->id = reply.value();
    }
}

void TrackingNotice::hide()
{
    auto *dbus = findChild<DbusNotice *>(Qt::FindDirectChildrenOnly);
    if (dbus->id == 0) {
        return;
    }

    QDBusInterface iface(SERVICE, PATH, INTERFACE, QDBusConnection::sessionBus());
    iface.call(QStringLiteral("CloseNotification"), dbus->id);
    dbus->id = 0;
}

#include "trackingnotice_dbus.moc"
