#pragma once

#include <QCoreApplication>
#include <QDir>
#include <QFileInfo>
#include <QStandardPaths>
#include <QStringList>

// -- AppIdMigration: the folders of an older id move to the new one ---------------
//
// The desktop builds name their folders after the application name: AppData, AppConfig and
// the cache through QStandardPaths, the config folder shared with the widget under
// GenericConfig. Each folder of the old name moves to the new name, once: not when the new
// one exists already (a newer start, or the widget moved it first). Same volume, so a rename.
namespace AppIdMigration {

// The writable folders an application of this name uses, in a fixed order.
inline QStringList folders(const QString &appName)
{
    const QString current = QCoreApplication::applicationName();
    QCoreApplication::setApplicationName(appName);
    QStringList out;
    for (const auto type : {QStandardPaths::AppDataLocation, QStandardPaths::AppLocalDataLocation,
                            QStandardPaths::AppConfigLocation, QStandardPaths::CacheLocation}) {
        out << QStandardPaths::writableLocation(type);
    }
    for (const auto type : {QStandardPaths::GenericConfigLocation, QStandardPaths::GenericDataLocation,
                            QStandardPaths::GenericCacheLocation}) {
        out << QStandardPaths::writableLocation(type) + QLatin1Char('/') + appName;
    }
    QCoreApplication::setApplicationName(current);
    return out;
}

// Moves what exists of oldName's folders; returns how many moved.
inline int moveFolders(const QString &oldName, const QString &newName)
{
    const QStringList from = folders(oldName);
    const QStringList to = folders(newName);
    int moved = 0;
    for (qsizetype i = 0; i < from.size(); ++i) {
        if (from[i] == to[i] || !QFileInfo(from[i]).isDir() || QFileInfo::exists(to[i])) {
            continue;
        }
        QDir().mkpath(QFileInfo(to[i]).absolutePath());
        if (QDir().rename(from[i], to[i])) {
            ++moved;
        } else {
            qWarning("plasmai: could not move %s to %s", qPrintable(from[i]), qPrintable(to[i]));
        }
    }
    return moved;
}

} // namespace AppIdMigration
