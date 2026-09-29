#include "notifier.h"

#include "traycontroller.h"

// Tray client: notifications as the tray icon's balloon / toast.
bool Notifier::isSupported()
{
    return TrayController::instance() != nullptr;
}

void Notifier::notify(const QString &summary, const QString &body)
{
    TrayController *tray = TrayController::instance();
    if (!tray) {
        emit notified(false);
        return;
    }
    tray->showMessage(summary, body);
    emit notified(true);
}
