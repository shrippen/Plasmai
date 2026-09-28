#include "idlewatcher.h"

#include <QDBusInterface>
#include <QDBusReply>

// Same D-Bus source contents/code/idle.sh falls back to on Wayland/Plasma;
// Plasma Mobile devices run a real Plasma Wayland session so this works
// unmodified on-device, same as on a desktop Linux build.

bool IdleWatcher::isSupported()
{
    return true;
}

void IdleWatcher::checkIdle()
{
    QDBusInterface iface(QStringLiteral("org.freedesktop.ScreenSaver"),
                         QStringLiteral("/org/freedesktop/ScreenSaver"),
                         QStringLiteral("org.freedesktop.ScreenSaver"),
                         QDBusConnection::sessionBus());
    if (!iface.isValid()) {
        emit idleChecked(-1, false);
        return;
    }
    QDBusReply<uint> reply = iface.call(QStringLiteral("GetSessionIdleTime"));
    if (!reply.isValid()) {
        emit idleChecked(-1, false);
        return;
    }
    emit idleChecked(static_cast<qint64>(reply.value()), true);
}
