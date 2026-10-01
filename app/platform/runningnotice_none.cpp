#include "runningnotice.h"

RunningNotice::RunningNotice(QObject *parent)
    : QObject(parent)
{
}

bool RunningNotice::isSupported()
{
    return false;
}

void RunningNotice::show(const QString &, const QString &, qint64)
{
}

void RunningNotice::clear()
{
}
