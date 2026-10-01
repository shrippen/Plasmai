#include "trackingnotice.h"

TrackingNotice::TrackingNotice(QObject *parent)
    : QObject(parent)
{
}

bool TrackingNotice::isSupported()
{
    return false;
}

void TrackingNotice::show(const QString &, const QString &, qint64)
{
}

void TrackingNotice::hide()
{
}
