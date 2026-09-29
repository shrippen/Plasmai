#include "idlewatcher.h"

#include <windows.h>

// Windows: time since the last keyboard or mouse input of this session.
bool IdleWatcher::isSupported()
{
    return true;
}

void IdleWatcher::checkIdle()
{
    LASTINPUTINFO info;
    info.cbSize = sizeof(info);
    if (!GetLastInputInfo(&info)) {
        emit idleChecked(-1, false);
        return;
    }
    // Both are milliseconds since boot, 32 bit: the unsigned difference survives the wrap.
    const DWORD idle = GetTickCount() - info.dwTime;
    emit idleChecked(static_cast<qint64>(idle), true);
}
