#include "notifier.h"

bool Notifier::isSupported()
{
    return false;
}

void Notifier::notify(const QString &, const QString &)
{
    emit notified(false);
}
