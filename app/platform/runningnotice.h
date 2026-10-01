#pragma once

#include <QObject>
#include <QString>

// -- RunningNotice: the notification that stays while a timer runs --------------
// One implementation per platform, chosen in CMakeLists.txt:
//   runningnotice_dbus.cpp     Linux / Plasma Mobile: org.freedesktop.Notifications
//   runningnotice_android.cpp  Android: ongoing notification with a live chronometer
//   runningnotice_none.cpp     elsewhere: not supported, not offered to QML
// show() on a shown notice updates it in place. startedAtMs is epoch ms, 0 if unknown.
class RunningNotice : public QObject {
    Q_OBJECT
public:
    explicit RunningNotice(QObject *parent = nullptr);

    static bool isSupported();
    Q_INVOKABLE void show(const QString &title, const QString &body, qint64 startedAtMs);
    Q_INVOKABLE void clear();

private:
    // What is shown now. D-Bus: the id to replace; Android: the payload to post again
    // once the user has answered the notification permission prompt.
    uint m_id = 0;
    bool m_shown = false;
    QString m_title;
    QString m_body;
    qint64 m_startedAtMs = 0;
};
