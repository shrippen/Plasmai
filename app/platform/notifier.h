#pragma once

#include <QObject>
#include <QString>

// -- Notifier: desktop notifications -------------------------------------------
// One implementation per platform, chosen in CMakeLists.txt:
//   notifier_dbus.cpp   Linux / Plasma Mobile: org.freedesktop.Notifications
//   notifier_tray.cpp   tray client (Windows): the tray icon's message
//   notifier_none.cpp   elsewhere: not supported, not offered to QML
class Notifier : public QObject {
    Q_OBJECT
public:
    using QObject::QObject;

    static bool isSupported();
    Q_INVOKABLE void notify(const QString &summary, const QString &body);

signals:
    void notified(bool ok);
};
