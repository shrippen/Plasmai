#pragma once

#include <QString>

// One id everywhere (Flathub's form): the keychain service, the config folder shared with the
// widget, the desktop builds' application name (token files live under it), the desktop file,
// the Flatpak and the Android package. Keep it stable.
inline const QString APP_ID = QStringLiteral("io.github.shrippen.Plasmai");

// The id up to 2.6.3. Folders and keychain entries under it move to APP_ID on the first start
// (platform/appidmigration.h, TokenStore::load); the Android package of that id is another app.
inline const QString OLD_APP_ID = QStringLiteral("com.github.shrippen.plasmai");
