#include "notifier.h"

#include <QDBusInterface>
#include <QDBusReply>
#include <QVariantList>
#include <QVariantMap>

#include "../appid.h"

bool Notifier::isSupported()
{
    return true;
}

void Notifier::notify(const QString &summary, const QString &body)
{
    QDBusInterface iface(QStringLiteral("org.freedesktop.Notifications"),
                         QStringLiteral("/org/freedesktop/Notifications"),
                         QStringLiteral("org.freedesktop.Notifications"),
                         QDBusConnection::sessionBus());
    if (!iface.isValid()) {
        emit notified(false);
        return;
    }
    QDBusReply<uint> reply = iface.call(
        QStringLiteral("Notify"),
        APP_ID,               // app_name
        0u,                    // replaces_id
        QStringLiteral("chronometer"), // app_icon
        summary,
        body,
        QStringList(),         // actions
        QVariantMap(),         // hints
        -1);                   // expire_timeout (server default)
    emit notified(reply.isValid());
}
