#include "idlewatcher.h"

bool IdleWatcher::isSupported()
{
    return false;
}

void IdleWatcher::checkIdle()
{
    emit idleChecked(-1, false);
}
