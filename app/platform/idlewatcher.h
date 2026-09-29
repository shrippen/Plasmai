#pragma once

#include <QObject>

// -- IdleWatcher: session idle time -------------------------------------------
// One implementation per platform, chosen in CMakeLists.txt:
//   idlewatcher_dbus.cpp   Linux / Plasma Mobile: org.freedesktop.ScreenSaver
//   idlewatcher_win.cpp    Windows: GetLastInputInfo
//   idlewatcher_none.cpp   elsewhere: not supported, not offered to QML
// QML sees `idleWatcher` only where isSupported() (a missing service is no error).
class IdleWatcher : public QObject {
    Q_OBJECT
public:
    using QObject::QObject;

    static bool isSupported();
    Q_INVOKABLE void checkIdle();

signals:
    void idleChecked(qint64 idleMs, bool ok);
};
