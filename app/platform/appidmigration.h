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
// GenericConfig. Each folder of the old name is copied to the new name, once: not when the new
// one exists already (a newer start, or the widget copied it first).
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

// Copies what exists of oldName's folders; returns how many were copied. Copied, not moved: a
// widget or app of the old id still running keeps its folders. The widget's own files
// (plasmoid/, its offline outbox among them) are left to the widget (localStore.sh): moved
// along by the app, an old widget's waiting changes were lost. A copy is made under a temporary
// name and renamed at the end, so a half copy is never taken for the new folder.
inline int copyFolders(const QString &oldName, const QString &newName)
{
    const QStringList from = folders(oldName);
    const QStringList to = folders(newName);
    int copied = 0;
    for (qsizetype i = 0; i < from.size(); ++i) {
        if (from[i] == to[i] || !QFileInfo(from[i]).isDir() || QFileInfo::exists(to[i])) {
            continue;
        }
        const QString part = to[i] + QStringLiteral(".copy");
        QDir(part).removeRecursively();
        if (copyTree(from[i], part, {QStringLiteral("plasmoid")}) && !QFileInfo::exists(to[i])
            && QDir().rename(part, to[i])) {
            ++copied;
        } else {
            QDir(part).removeRecursively();
            qWarning("plasmai: could not copy %s to %s", qPrintable(from[i]), qPrintable(to[i]));
        }
    }
    return copied;
}

} // namespace AppIdMigration
