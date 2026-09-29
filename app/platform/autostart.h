#pragma once

#include <QObject>

// -- Autostart: start with the user session (the tray client, ROADMAP pillar 7) --
// One implementation per platform, chosen in CMakeLists.txt:
//   autostart_win.cpp    Windows: HKCU\Software\Microsoft\Windows\CurrentVersion\Run
//   autostart_none.cpp   elsewhere: not supported, not offered to QML
// A started-at-login instance passes --hidden: the tray icon only, no popup.
class Autostart : public QObject {
    Q_OBJECT
    Q_PROPERTY(bool enabled READ enabled WRITE setEnabled NOTIFY enabledChanged)
public:
    using QObject::QObject;

    static bool isSupported();
    bool enabled() const;
    void setEnabled(bool enabled);

signals:
    void enabledChanged();
};
