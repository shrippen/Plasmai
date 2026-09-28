#include "tokenstore.h"

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

        // Not in the keychain: a token file of an older build moves in.
        migrate(profileId);
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

    auto *job = new QKeychain::DeletePasswordJob(APP_ID, this);
    job->setAutoDelete(true);
    job->setInsecureFallback(false);
    job->setKey(profileId);
    connect(job, &QKeychain::Job::finished, this, [this, profileId](QKeychain::Job *j) {
        const bool ok = j->error() == QKeychain::NoError || j->error() == QKeychain::EntryNotFound;
        emit removed(profileId, ok);
    });
    job->start();
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

QString TokenStore::readLegacy(const QString &profileId)
{
    QFile f(legacyPath(profileId));
    if (!f.open(QIODevice::ReadOnly | QIODevice::Text)) {
        return QString();
    }
    return QString::fromUtf8(f.readAll()).trimmed();
}

void TokenStore::removeLegacy(const QString &profileId)
{
    QFile::remove(legacyPath(profileId));
}
