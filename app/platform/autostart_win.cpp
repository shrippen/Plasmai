#include "autostart.h"

#include <QCoreApplication>
#include <QDir>
#include <QSettings>

namespace {

const QString RUN_KEY = QStringLiteral("HKEY_CURRENT_USER\\Software\\Microsoft\\Windows\\CurrentVersion\\Run");
const QString VALUE_NAME = QStringLiteral("Plasmai");

// This executable, quoted, started without its popup.
QString command()
{
    return QLatin1Char('"') + QDir::toNativeSeparators(QCoreApplication::applicationFilePath())
        + QStringLiteral("\" --hidden");
}

} // namespace

bool Autostart::isSupported()
{
    return true;
}

// Enabled only when the entry starts this executable (a moved install counts as off).
bool Autostart::enabled() const
{
    return QSettings(RUN_KEY, QSettings::NativeFormat).value(VALUE_NAME).toString() == command();
}

void Autostart::setEnabled(bool enabled)
{
    if (enabled == this->enabled()) {
        return;
    }
    QSettings run(RUN_KEY, QSettings::NativeFormat);
    if (enabled) {
        run.setValue(VALUE_NAME, command());
    } else {
        run.remove(VALUE_NAME);
    }
    emit enabledChanged();
}
