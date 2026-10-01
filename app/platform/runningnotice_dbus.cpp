#include "runningnotice.h"

#include <QCoreApplication>
#include <QDBusInterface>
#include <QDBusReply>
#include <QDateTime>
#include <QLocale>
#include <QVariantMap>

#include "../appid.h"

namespace {
const QString NOTIFY_SERVICE = QStringLiteral("org.freedesktop.Notifications");
const QString NOTIFY_PATH = QStringLiteral("/org/freedesktop/Notifications");
const QString NOTIFY_IFACE = QStringLiteral("org.freedesktop.Notifications");

// expire_timeout 0: the server never expires it (spec); resident: it stays when clicked.
constexpr int NEVER_EXPIRES = 0;
const QString HINT_RESIDENT = QStringLiteral("resident");

QDBusInterface notifications()
{
    return QDBusInterface(NOTIFY_SERVICE, NOTIFY_PATH, NOTIFY_IFACE, QDBusConnection::sessionBus());
}
}

RunningNotice::RunningNotice(QObject *parent)
    : QObject(parent)
{
    // The timer runs on in the cloud, but nothing updates this notice once the app is gone.
    connect(qApp, &QCoreApplication::aboutToQuit, this, &RunningNotice::clear);
}

bool RunningNotice::isSupported()
{
    return true;
}

// Plasma has no live chronometer: the start time is the second line instead,
// e.g. "Project · Activity" / "09:14" (the time in the user's locale).
void RunningNotice::show(const QString &title, const QString &body, qint64 startedAtMs)
{
    QString text = body;
    if (startedAtMs > 0) {
        const QDateTime started = QDateTime::fromMSecsSinceEpoch(startedAtMs);
        text += QLatin1Char('\n') + QLocale().toString(started.time(), QLocale::ShortFormat);
    }

    QDBusInterface iface = notifications();
    if (!iface.isValid()) {
        return;
    }

    QVariantMap hints;
    hints.insert(HINT_RESIDENT, true);
    QDBusReply<uint> reply = iface.call(
        QStringLiteral("Notify"),
        APP_ID,                        // app_name
        m_id,                          // replaces_id: update instead of a second one
        QStringLiteral("chronometer"), // app_icon
        title,
        text,
        QStringList(),                 // actions
        hints,
        NEVER_EXPIRES);
    if (reply.isValid()) {
        m_id = reply.value();
    }
}

void RunningNotice::clear()
{
    if (m_id == 0) {
        return;
    }

    QDBusInterface iface = notifications();
    if (iface.isValid()) {
        iface.call(QStringLiteral("CloseNotification"), m_id);
    }
    m_id = 0;
}
