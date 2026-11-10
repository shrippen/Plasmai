#pragma once

#include <QString>

// One id everywhere (Flathub's form): the keychain service, the config folder shared with the
// widget, the desktop builds' application name (token files live under it), the desktop file,
// the Flatpak and the Android package. Keep it stable.
inline const QString APP_ID = QStringLiteral("io.github.shrippen.Plasmai");

// The id up to 2.6.3. On the first start its folders are copied and its keychain entries moved
// to APP_ID (platform/appidmigration.h, TokenStore::load); its Android package is another app.
inline const QString OLD_APP_ID = QStringLiteral("com.github.shrippen.plasmai");
