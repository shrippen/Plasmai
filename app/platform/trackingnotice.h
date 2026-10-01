#pragma once

#include <QObject>
#include <QString>

// -- TrackingNotice: a permanent notification while a timer runs ---------------
// One implementation per platform, chosen in CMakeLists.txt:
//   trackingnotice_android.cpp  Android: ongoing notification with a chronometer
//                               (TrackingNotice.java)
//   trackingnotice_dbus.cpp     Linux / Plasma Mobile: a resident notification
//   trackingnotice_none.cpp     elsewhere: not supported, not offered to QML
// QML decides where to show it (mobile only); show() again replaces the shown one.
class TrackingNotice : public QObject {
    Q_OBJECT
public:
    explicit TrackingNotice(QObject *parent = nullptr);

    static bool isSupported();
    /** `sinceMsecs`: begin of the entry (ms since the epoch), the elapsed time counts from it. */
    Q_INVOKABLE void show(const QString &title, const QString &text, qint64 sinceMsecs);
    Q_INVOKABLE void hide();

signals:
    /** The notification was tapped (D-Bus; Android opens the app itself). */
    void activated();
};
