#pragma once

#include <QCoreApplication>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QStandardPaths>
#include <QStringList>

// -- AppIdMigration: the folders of an older id are copied to the new one ----------
//
// The desktop builds name their folders after the application name: AppData, AppConfig and
// the cache through QStandardPaths, the config folder shared with the widget under
// GenericConfig. What a folder of the old name holds is copied to the new name, once per entry.
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

// Copies dir's files below `to`, without the top-level entries named in `skip`.
inline bool copyTree(const QString &from, const QString &to, const QStringList &skip = {})
{
    if (!QDir().mkpath(to)) {
        return false;
    }
    const QDir source(from);
    const auto entries = source.entryInfoList(QDir::AllEntries | QDir::Hidden | QDir::NoDotAndDotDot);
    for (const QFileInfo &entry : entries) {
        if (skip.contains(entry.fileName())) {
            continue;
        }
        const QString target = to + QLatin1Char('/') + entry.fileName();
        const bool ok = entry.isDir() && !entry.isSymLink() ? copyTree(entry.filePath(), target)
                                                            : QFile::copy(entry.filePath(), target);
        if (!ok) {
            return false;
        }
    }
    return true;
}

// Copies what is missing of oldName's folders, entry by entry at the top level, once per folder
// (a marker file remembers it); returns how many entries were copied. Copied, not moved: a widget or app of the old id still running
// keeps its folders. An entry the new folder has already is never overwritten, so it does not
// matter who started first (the new widget makes the data folder with plasmoid/ only; the
// app's app/ and tokens/ follow later). plasmoid/ (the widget's files, its offline outbox among
// them) is left to the widget's localStore.sh: taken by the app, an old widget's waiting
// changes were lost. Each entry is copied under a name of this process and renamed at the end,
// so a half copy is never taken for the entry.
inline int copyFolders(const QString &oldName, const QString &newName)
{
    const QStringList from = folders(oldName);
    const QStringList to = folders(newName);
    const QString suffix = QStringLiteral(".copy.") + QString::number(QCoreApplication::applicationPid());
    int copied = 0;
    for (qsizetype i = 0; i < from.size(); ++i) {
        // Taken over once per folder: what the app removes later must not come back from the
        // old folder (sent offline changes would be sent again).
        const QString marker = to[i] + QStringLiteral("/.taken-over-from-") + oldName;
        if (from[i] == to[i] || !QFileInfo(from[i]).isDir() || QFileInfo::exists(marker)) {
            continue;
        }
        bool failed = false;
        const auto entries = QDir(from[i]).entryInfoList(QDir::AllEntries | QDir::Hidden | QDir::NoDotAndDotDot);
        for (const QFileInfo &entry : entries) {
            const QString target = to[i] + QLatin1Char('/') + entry.fileName();
            // plasmoid/ is the widget's; tokens/ holds plain-text token files of builds before 2.1,
            // which TokenStore moves into the keychain from where they are (never copied).
            if (entry.fileName() == QLatin1String("plasmoid") || entry.fileName() == QLatin1String("tokens")
                || entry.fileName().contains(QLatin1String(".copy."))
                || entry.fileName().startsWith(QLatin1String(".taken-over-from-"))
                || QFileInfo::exists(target)) {
                continue;
            }
            const QString part = target + suffix;
            QDir().mkpath(to[i]);
            const bool ok = entry.isDir() && !entry.isSymLink() ? copyTree(entry.filePath(), part)
                                                                : QFile::copy(entry.filePath(), part);
            if (ok && !QFileInfo::exists(target) && QDir().rename(part, target)) {
                ++copied;
                continue;
            }
            if (QFileInfo(part).isDir()) {
                QDir(part).removeRecursively();
            } else {
                QFile::remove(part);
            }
            if (!QFileInfo::exists(target)) {
                qWarning("plasmai: could not copy %s to %s", qPrintable(entry.filePath()), qPrintable(target));
                failed = true;
            }
        }
        if (!failed) {
            QDir().mkpath(to[i]);
            QFile mark(marker);
            if (!mark.open(QIODevice::WriteOnly)) {
                qWarning("plasmai: could not write %s", qPrintable(marker));
            }
        }
    }
    return copied;
}

} // namespace AppIdMigration
