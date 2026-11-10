#include <QDir>
#include <QDirIterator>
#include <QFile>
#include <QFileInfo>
#include <QSignalSpy>
#include <QStandardPaths>
#include <QTest>
#include <qt6keychain/keychain.h>

#include "appid.h"
#include "platform/appidmigration.h"
#include "platform/tokenstore.h"

// TokenStore never keeps a token in plain text. With a keychain running (a
// Secret Service in a D-Bus session): tokens round-trip and an older build's
// token file moves in. Without one: saving fails and writes no file.
class TstTokenStore : public QObject {
    Q_OBJECT

private:
    const QString m_profile = QStringLiteral("tst-profile");

    static QString legacyPath(const QString &profile)
    {
        return QStandardPaths::writableLocation(QStandardPaths::AppDataLocation)
            + QStringLiteral("/tokens/") + profile + QStringLiteral(".token");
    }

    // Where the builds up to 2.6.3 had the file: the AppData folder of the old id.
    static QString oldIdLegacyPath(const QString &profile)
    {
        return AppIdMigration::folders(OLD_APP_ID).first() + QStringLiteral("/tokens/") + profile
            + QStringLiteral(".token");
    }

    static void writeOldIdLegacy(const QString &profile, const QByteArray &token)
    {
        QDir().mkpath(QFileInfo(oldIdLegacyPath(profile)).absolutePath());
        QFile f(oldIdLegacyPath(profile));
        QVERIFY(f.open(QIODevice::WriteOnly));
        f.write(token);
    }

    static void writeLegacy(const QString &profile, const QByteArray &token)
    {
        QDir().mkpath(QFileInfo(legacyPath(profile)).absolutePath());
        QFile f(legacyPath(profile));
        QVERIFY(f.open(QIODevice::WriteOnly));
        f.write(token);
    }

    // Anything with the token's text under the test's data and config dirs, and
    // the user's (QSettings, where QtKeychain's insecure fallback would write).
    static bool plainTextAnywhere(const QByteArray &token)
    {
        const QStringList roots{QStandardPaths::writableLocation(QStandardPaths::GenericDataLocation),
                                QStandardPaths::writableLocation(QStandardPaths::GenericConfigLocation),
                                QDir::homePath() + QStringLiteral("/.config"),
                                QDir::homePath() + QStringLiteral("/.local/share")};
        for (const QString &root : roots) {
            QDirIterator it(root, QDir::Files, QDirIterator::Subdirectories);
            while (it.hasNext()) {
                QFile f(it.next());
                if (f.open(QIODevice::ReadOnly) && f.readAll().contains(token)) {
                    return true;
                }
            }
        }
        return false;
    }

    static QString loadToken(TokenStore &store, const QString &profile)
    {
        QSignalSpy spy(&store, &TokenStore::loaded);
        store.load(profile);
        if (!spy.wait(10000)) {
            return QStringLiteral("<timeout>");
        }
        return spy.takeFirst().at(1).toString();
    }

    static bool saveToken(TokenStore &store, const QString &profile, const QString &token)
    {
        QSignalSpy spy(&store, &TokenStore::saved);
        store.save(profile, token);
        return spy.wait(10000) && spy.takeFirst().at(1).toBool();
    }

    static bool writeKeychain(const QString &service, const QString &key, const QString &token)
    {
        QKeychain::WritePasswordJob job(service);
        job.setAutoDelete(false);
        job.setInsecureFallback(false);
        job.setKey(key);
        job.setTextData(token);
        QSignalSpy spy(&job, &QKeychain::Job::finished);
        job.start();
        return spy.wait(10000) && job.error() == QKeychain::NoError;
    }

    // The entry's text, a null string when there is none.
    static QString readKeychain(const QString &service, const QString &key)
    {
        QKeychain::ReadPasswordJob job(service);
        job.setAutoDelete(false);
        job.setInsecureFallback(false);
        job.setKey(key);
        QSignalSpy spy(&job, &QKeychain::Job::finished);
        job.start();
        if (!spy.wait(10000) || job.error() != QKeychain::NoError) {
            return QString();
        }
        return job.textData();
    }

    static bool keychainRunning()
    {
        // A write that succeeds tells for sure (isAvailable() only sees the bus name).
        TokenStore probe;
        const bool ok = saveToken(probe, QStringLiteral("tst-probe"), QStringLiteral("probe"));
        if (ok) {
            QSignalSpy spy(&probe, &TokenStore::removed);
            probe.remove(QStringLiteral("tst-probe"));
            spy.wait(10000);
        }
        return ok;
    }

private slots:
    void initTestCase()
    {
        QStandardPaths::setTestModeEnabled(true);
        QCoreApplication::setApplicationName(QStringLiteral("plasmai-tst-tokenstore"));
    }

    void cleanup()
    {
        TokenStore store;
        QSignalSpy spy(&store, &TokenStore::removed);
        store.remove(m_profile);
        spy.wait(10000);
    }

    void withKeychain()
    {
        if (!keychainRunning()) {
            QSKIP("no keychain in this session (see withoutKeychain)");
        }
        TokenStore store;

        // save / load, nothing on disk
        QVERIFY(saveToken(store, m_profile, QStringLiteral("secret-1")));
        QCOMPARE(loadToken(store, m_profile), QStringLiteral("secret-1"));
        QVERIFY(!plainTextAnywhere("secret-1"));

        // An older build's file moves into the keychain and is deleted.
        QSignalSpy removedSpy(&store, &TokenStore::removed);
        store.remove(m_profile);
        QVERIFY(removedSpy.wait(10000));
        writeLegacy(m_profile, "legacy-2\n");
        QCOMPARE(loadToken(store, m_profile), QStringLiteral("legacy-2"));
        QVERIFY(!QFile::exists(legacyPath(m_profile)));
        QVERIFY(!plainTextAnywhere("legacy-2"));
        QCOMPARE(loadToken(store, m_profile), QStringLiteral("legacy-2"));

        // An entry under the id up to 2.6.3 moves to APP_ID and is deleted there.
        store.remove(m_profile);
        QVERIFY(removedSpy.wait(10000));
        QVERIFY(writeKeychain(OLD_APP_ID, m_profile, QStringLiteral("old-id-5")));
        // QtKeychain 0.15 on Windows names a Credential Manager entry by its key only: old and
        // new id share it there, and there is nothing to move.
        const bool shared = readKeychain(APP_ID, m_profile) == QStringLiteral("old-id-5");
        QCOMPARE(loadToken(store, m_profile), QStringLiteral("old-id-5"));
        // Shared or moved, the token is under APP_ID afterwards.
        QCOMPARE(readKeychain(APP_ID, m_profile), QStringLiteral("old-id-5"));
        if (!shared) {
            QVERIFY(readKeychain(OLD_APP_ID, m_profile).isNull());
        }

        // A token file of a build before 2.1 under the id up to 2.6.3 moves into the keychain
        // and is deleted there (review of PR #52: copied to the new folder, the original stayed).
        store.remove(m_profile);
        QVERIFY(removedSpy.wait(10000));
        writeOldIdLegacy(m_profile, "old-file-7\n");
        QCOMPARE(loadToken(store, m_profile), QStringLiteral("old-file-7"));
        QVERIFY(!QFile::exists(oldIdLegacyPath(m_profile)));
        QVERIFY(!plainTextAnywhere("old-file-7"));
        // remove() deletes one not yet moved too.
        writeOldIdLegacy(m_profile, "old-file-8\n");
        store.remove(m_profile);
        QVERIFY(removedSpy.wait(10000));
        QVERIFY(!QFile::exists(oldIdLegacyPath(m_profile)));

        // remove() clears an old entry not yet moved, so it does not come back.
        store.remove(m_profile);
        QVERIFY(removedSpy.wait(10000));
        QVERIFY(writeKeychain(OLD_APP_ID, m_profile, QStringLiteral("old-id-6")));
        store.remove(m_profile);
        QVERIFY(removedSpy.wait(10000));
        QVERIFY(readKeychain(OLD_APP_ID, m_profile).isNull());
        QCOMPARE(loadToken(store, m_profile), QString());
    }

    void withoutKeychain()
    {
        if (keychainRunning()) {
            QSKIP("a keychain runs in this session (see withKeychain)");
        }
        TokenStore store;

        // No secure storage: the save fails, no plain-text copy appears.
        QVERIFY(!saveToken(store, m_profile, QStringLiteral("secret-3")));
        QVERIFY(!plainTextAnywhere("secret-3"));

        // An older build's file stays (deleting it would lose the token) and is answered.
        writeLegacy(m_profile, "legacy-4");
        QCOMPARE(loadToken(store, m_profile), QStringLiteral("legacy-4"));
        QVERIFY(QFile::exists(legacyPath(m_profile)));
        QFile::remove(legacyPath(m_profile));
    }
};

QTEST_GUILESS_MAIN(TstTokenStore)
#include "tst_tokenstore.moc"
