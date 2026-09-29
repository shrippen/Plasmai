#pragma once

#include <QElapsedTimer>
#include <QIcon>
#include <QLocalServer>
#include <QMenu>
#include <QObject>
#include <QPointer>
#include <QQuickWindow>
#include <QSystemTrayIcon>
#include <QVariantList>

// -- TrayController: the tray client (ROADMAP pillar 7) -------------------------
// A tray icon and a popup, conceptually the Plasmoid: the icon shows the timer
// state, a left click opens the app's window as a frameless popup next to it,
// losing focus hides it again; the right-click menu comes from QML (its texts
// are translated there). One instance per user: a second start opens the
// running one's popup and exits.
class TrayController : public QObject {
    Q_OBJECT
    Q_PROPERTY(bool tracking READ tracking WRITE setTracking NOTIFY trackingChanged)
    Q_PROPERTY(QString toolTip READ toolTip WRITE setToolTip NOTIFY toolTipChanged)
    // [{ id, text, enabled, checkable, checked, separator }], shown as the context menu.
    Q_PROPERTY(QVariantList menu READ menu WRITE setMenu NOTIFY menuChanged)

public:
    // A system tray is there (Windows: always; elsewhere a tray host may be missing).
    static bool isSupported();
    // Another instance runs: tells it to show its popup; this one should exit then.
    static bool handOverToRunning();
    // The running controller (notifications go through its icon), or nullptr.
    static TrayController *instance();

    explicit TrayController(QObject *parent = nullptr);
    ~TrayController() override;

    // The app window becomes the popup; shown at once unless `hidden` (autostart).
    void setWindow(QQuickWindow *window, bool hidden);

    bool tracking() const { return m_tracking; }
    void setTracking(bool tracking);
    QString toolTip() const { return m_toolTip; }
    void setToolTip(const QString &toolTip);
    QVariantList menu() const { return m_menuModel; }
    void setMenu(const QVariantList &menu);

    Q_INVOKABLE void showPopup();
    Q_INVOKABLE void hidePopup();
    void showMessage(const QString &title, const QString &body);

signals:
    void trackingChanged();
    void toolTipChanged();
    void menuChanged();
    void menuTriggered(const QString &id);

private:
    void toggle();
    void place();
    void rebuildMenu();
    void updateIcon();
    static QIcon trayIcon(bool tracking);

    QSystemTrayIcon m_icon;
    QMenu m_menu;
    QVariantList m_menuModel;
    QPointer<QQuickWindow> m_window;
    QLocalServer m_server;
    QElapsedTimer m_hiddenAt;
    bool m_tracking = false;
    QString m_toolTip;
};
