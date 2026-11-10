#include "tokenstore.h"

#include <QCoreApplication>
#include <QFile>
#include <QStandardPaths>
#include <qt6keychain/keychain.h>

#include "../appid.h"

void TokenStore::load(const QString &profileId)
{
    auto *job = new QKeychain::ReadPasswordJob(APP_ID, this);
    job->setAutoDelete(true);
    job->setInsecureFallback(false);
    job->setKey(profileId);
    connect(job, &QKeychain::Job::finished, this, [this, profileId](QKeychain::Job *j) {
        auto *rj = static_cast<QKeychain::ReadPasswordJob *>(j);
        if (rj->error() == QKeychain::NoError) {
            emit loaded(profileId, rj->textData());
            return;
        }
        if (rj->error() != QKeychain::EntryNotFound) {
            qWarning("plasmai: secure storage not readable: %s", qPrintable(rj->errorString()));
        }

        // Not in the keychain: an entry under the id up to 2.6.3 or a token file of an
        // older build moves in.
        migrateOldService(profileId);
    });
    job->start();
}

// The old id's entry is copied to APP_ID and then deleted, so a later remove() clears the
// token for good. While the copy fails the old entry stays and is answered.
void TokenStore::migrateOldService(const QString &profileId)
{
    auto *job = new QKeychain::ReadPasswordJob(OLD_APP_ID, this);
    job->setAutoDelete(true);
    job->setInsecureFallback(false);
    job->setKey(profileId);
    connect(job, &QKeychain::Job::finished, this, [this, profileId](QKeychain::Job *j) {
        auto *rj = static_cast<QKeychain::ReadPasswordJob *>(j);
        if (rj->error() != QKeychain::NoError) {
            migrate(profileId);
            return;
        }
        const QString token = rj->textData();
        write(profileId, token, [this, profileId, token](bool ok, const QString &error) {
            if (!ok) {
                qWarning("plasmai: token kept under the old id: %s", qPrintable(error));
                emit loaded(profileId, token);
                return;
            }
            auto *del = new QKeychain::DeletePasswordJob(OLD_APP_ID, this);
            del->setAutoDelete(true);
            del->setInsecureFallback(false);
            del->setKey(profileId);
            connect(del, &QKeychain::Job::finished, this, [this, profileId, token](QKeychain::Job *) {
                emit loaded(profileId, token);
            });
            del->start();
        });
    });
    job->start();
}

void TokenStore::save(const QString &profileId, const QString &token)
{
    write(profileId, token, [this, profileId](bool ok, const QString &error) {
        if (ok) {
            removeLegacy(profileId);
        }
        emit saved(profileId, ok, error);
    });
}

void TokenStore::remove(const QString &profileId)
{
    removeLegacy(profileId);

    // First an entry under the old id not yet moved: it would come back with the next load.
    auto *old = new QKeychain::DeletePasswordJob(OLD_APP_ID, this);
    old->setAutoDelete(true);
    old->setInsecureFallback(false);
    old->setKey(profileId);
    connect(old, &QKeychain::Job::finished, this, [this, profileId](QKeychain::Job *) {
        auto *job = new QKeychain::DeletePasswordJob(APP_ID, this);
        job->setAutoDelete(true);
        job->setInsecureFallback(false);
        job->setKey(profileId);
        connect(job, &QKeychain::Job::finished, this, [this, profileId](QKeychain::Job *j) {
            const bool ok = j->error() == QKeychain::NoError || j->error() == QKeychain::EntryNotFound;
            emit removed(profileId, ok);
        });
        job->start();
    });
    old->start();
}

// The legacy file's token goes to the keychain; the file is deleted only once
// the keychain has it. The token is answered either way.
void TokenStore::migrate(const QString &profileId)
{
    const QString token = readLegacy(profileId);
    if (token.isEmpty()) {
        emit loaded(profileId, QString());
        return;
    }

    write(profileId, token, [this, profileId, token](bool ok, const QString &error) {
        if (ok) {
            removeLegacy(profileId);
        } else {
            qWarning("plasmai: token file kept, secure storage unavailable: %s", qPrintable(error));
        }
        emit loaded(profileId, token);
    });
}

void TokenStore::write(const QString &profileId, const QString &token,
                       const std::function<void(bool, const QString &)> &done)
{
    auto *job = new QKeychain::WritePasswordJob(APP_ID, this);
    job->setAutoDelete(true);
    job->setInsecureFallback(false);
    job->setKey(profileId);
    job->setTextData(token);
    connect(job, &QKeychain::Job::finished, this, [done](QKeychain::Job *j) {
        done(j->error() == QKeychain::NoError, j->errorString());
    });
    job->start();
}

QString TokenStore::legacyPath(const QString &profileId)
{
    return QStandardPaths::writableLocation(QStandardPaths::AppDataLocation)
        + QStringLiteral("/tokens/") + profileId + QStringLiteral(".token");
}

// The same file where the builds up to 2.6.3 had it: the AppData folder of the old id (desktop;
// on Android that package is another app). Read and deleted there in place, never copied
// (AppIdMigration leaves tokens/ out), so no plain-text copy stays behind.
QString TokenStore::oldIdLegacyPath(const QString &profileId)
{
#ifdef Q_OS_ANDROID
    Q_UNUSED(profileId)
    return QString();
#else
    const QString base = QStandardPaths::writableLocation(QStandardPaths::AppDataLocation);
    const QString name = QCoreApplication::applicationName();
    if (name == OLD_APP_ID || !base.endsWith(QLatin1Char('/') + name)) {
        return QString();
    }
    return base.left(base.size() - name.size()) + OLD_APP_ID + QStringLiteral("/tokens/") + profileId
        + QStringLiteral(".token");
#endif
}

QString TokenStore::readLegacy(const QString &profileId)
{
    for (const QString &path : {legacyPath(profileId), oldIdLegacyPath(profileId)}) {
        QFile f(path);
        if (!path.isEmpty() && f.open(QIODevice::ReadOnly | QIODevice::Text)) {
            return QString::fromUtf8(f.readAll()).trimmed();
        }
    }
    return QString();
}

void TokenStore::removeLegacy(const QString &profileId)
{
    QFile::remove(legacyPath(profileId));
    const QString old = oldIdLegacyPath(profileId);
    if (!old.isEmpty()) {
        QFile::remove(old);
    }
}
