#pragma once

#include <QDir>
#include <QFile>
#include <QObject>
#include <QSaveFile>
#include <QStandardPaths>

#include "../appid.h"

// Keychain when the build has it, token files otherwise (Android).
#ifdef Qt6Keychain_FOUND
#include <qt6keychain/keychain.h>
#define HAS_KEYCHAIN 1
#endif

// -- TokenStore: read / write / delete API tokens via QtKeychain ----------

class TokenStore : public QObject {
    Q_OBJECT
public:
    using QObject::QObject;

    Q_INVOKABLE void load(const QString &profileId) {
#ifdef HAS_KEYCHAIN
        auto *job = new QKeychain::ReadPasswordJob(APP_ID, this);
        job->setAutoDelete(true);
        job->setKey(profileId);
        connect(job, &QKeychain::ReadPasswordJob::finished,
                this, [this, profileId](QKeychain::Job *j) {
            auto *rj = static_cast<QKeychain::ReadPasswordJob *>(j);
            QString token;
            if (rj->error() == QKeychain::NoError) {
                token = rj->textData();
            }
            emit loaded(profileId, token);
        });
        job->start();
#else
        QFile f(tokenPath(profileId));
        QString token;
        if (f.open(QIODevice::ReadOnly | QIODevice::Text)) {
            token = QString::fromUtf8(f.readAll()).trimmed();
        }
        emit loaded(profileId, token);
#endif
    }

    Q_INVOKABLE void save(const QString &profileId, const QString &token) {
#ifdef HAS_KEYCHAIN
        auto *job = new QKeychain::WritePasswordJob(APP_ID, this);
        job->setAutoDelete(true);
        job->setKey(profileId);
        job->setTextData(token);
        connect(job, &QKeychain::WritePasswordJob::finished,
                this, [this, profileId](QKeychain::Job *j) {
            emit saved(profileId, j->error() == QKeychain::NoError);
        });
        job->start();
#else
        QDir().mkpath(tokenDir());
        // QSaveFile: temp file + rename, so a killed app never leaves a torn token.
        QSaveFile f(tokenPath(profileId));
        bool ok = f.open(QIODevice::WriteOnly | QIODevice::Text);
        if (ok) {
            f.write(token.toUtf8());
            ok = f.commit();
        }
        emit saved(profileId, ok);
#endif
    }

    Q_INVOKABLE void remove(const QString &profileId) {
#ifdef HAS_KEYCHAIN
        auto *job = new QKeychain::DeletePasswordJob(APP_ID, this);
        job->setAutoDelete(true);
        job->setKey(profileId);
        connect(job, &QKeychain::DeletePasswordJob::finished,
                this, [this, profileId](QKeychain::Job *j) {
            emit removed(profileId, j->error() == QKeychain::NoError);
        });
        job->start();
#else
        QFile f(tokenPath(profileId));
        bool ok = f.remove();
        emit removed(profileId, ok);
#endif
    }

signals:
    void loaded(const QString &profileId, const QString &token);
    void saved(const QString &profileId, bool ok);
    void removed(const QString &profileId, bool ok);

private:
    static QString tokenDir() {
        return QStandardPaths::writableLocation(QStandardPaths::AppDataLocation) + "/tokens";
    }
    static QString tokenPath(const QString &id) {
        return tokenDir() + "/" + id + ".token";
    }
};
