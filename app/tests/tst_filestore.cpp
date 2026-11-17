#include <QDir>
#include <QFile>
#include <QSignalSpy>
#include <QStandardPaths>
#include <QTest>

#include "platform/filestore.h"

// FileStore's local files: the app's own offline snapshot and outbox, private
// to the user, never outside their folder.
class TstFileStore : public QObject {
    Q_OBJECT

private slots:
    void initTestCase()
    {
        QStandardPaths::setTestModeEnabled(true);
        QCoreApplication::setApplicationName(QStringLiteral("plasmai-tst-filestore"));
    }

    void roundTrip()
    {
        FileStore store;
        QSignalSpy saved(&store, &FileStore::localSaved);
        store.saveLocal(QStringLiteral("offline-outbox-p1"), QStringLiteral("{\"v\":1}"));
        QCOMPARE(saved.takeFirst().at(1).toBool(), true);

        QSignalSpy loaded(&store, &FileStore::localLoaded);
        store.loadLocal(QStringLiteral("offline-outbox-p1"));
        const auto args = loaded.takeFirst();
        QCOMPARE(args.at(0).toString(), QStringLiteral("offline-outbox-p1"));
        QCOMPARE(args.at(1).toString(), QStringLiteral("{\"v\":1}"));
        QCOMPARE(args.at(2).toString(), QStringLiteral("ok"));

        store.loadLocal(QStringLiteral("missing"));
        const auto none = loaded.takeFirst();
        QCOMPARE(none.at(1).toString(), QString());
        QCOMPARE(none.at(2).toString(), QStringLiteral("missing"));
    }

    // A file that cannot be read is not "missing": the caller must not replace it.
    void unreadableIsNotMissing()
    {
        const QString dir = QStandardPaths::writableLocation(QStandardPaths::AppDataLocation)
            + QStringLiteral("/app");
        QVERIFY(QDir().mkpath(dir + QStringLiteral("/unreadable.json")));

        FileStore store;
        QSignalSpy loaded(&store, &FileStore::localLoaded);
        store.loadLocal(QStringLiteral("unreadable"));
        QCOMPARE(loaded.takeFirst().at(2).toString(), QStringLiteral("unreadable"));
    }

    // A broken file is moved aside under <name>.broken-<time>, never deleted.
    void quarantineMovesAside()
    {
        const QString dir = QStandardPaths::writableLocation(QStandardPaths::AppDataLocation)
            + QStringLiteral("/app");
        // Leftovers of an earlier run (the test location persists).
        for (const QString &old : QDir(dir).entryList({QStringLiteral("garbled.*")}, QDir::Files)) {
            QFile::remove(dir + "/" + old);
        }

        FileStore store;
        QSignalSpy saved(&store, &FileStore::localSaved);
        store.saveLocal(QStringLiteral("garbled"), QStringLiteral("{not json"));
        QVERIFY(saved.takeFirst().at(1).toBool());

        QSignalSpy moved(&store, &FileStore::localQuarantined);
        store.quarantineLocal(QStringLiteral("garbled"));
        QVERIFY(moved.takeFirst().at(1).toBool());

        QVERIFY(!QFile::exists(dir + QStringLiteral("/garbled.json")));
        const QStringList kept = QDir(dir).entryList({QStringLiteral("garbled.broken-*")}, QDir::Files);
        QCOMPARE(kept.size(), 1);

        QSignalSpy loaded(&store, &FileStore::localLoaded);
        store.loadLocal(QStringLiteral("garbled"));
        QCOMPARE(loaded.takeFirst().at(2).toString(), QStringLiteral("missing"));
    }

    void privateFile()
    {
        FileStore store;
        QSignalSpy saved(&store, &FileStore::localSaved);
        store.saveLocal(QStringLiteral("offline-state-p1"), QStringLiteral("{}"));
        QVERIFY(saved.takeFirst().at(1).toBool());
        const QString path = QStandardPaths::writableLocation(QStandardPaths::AppDataLocation)
            + QStringLiteral("/app/offline-state-p1.json");
        const auto perms = QFile(path).permissions();
        QVERIFY(perms & QFileDevice::ReadOwner);
#ifndef Q_OS_WIN
        // Windows has no group/other bits (Qt reports them set): the profile's ACLs keep
        // %LOCALAPPDATA% to its user.
        QVERIFY(!(perms & (QFileDevice::ReadGroup | QFileDevice::ReadOther)));
#endif
    }

    void rejectsPaths()
    {
        FileStore store;
        QSignalSpy saved(&store, &FileStore::localSaved);
        for (const QString &name : {QStringLiteral("../x"), QStringLiteral("a/b"), QStringLiteral(".hidden"), QString()}) {
            store.saveLocal(name, QStringLiteral("{}"));
            QCOMPARE(saved.takeFirst().at(1).toBool(), false);
        }
        QVERIFY(!QFile::exists(QStandardPaths::writableLocation(QStandardPaths::AppDataLocation) + QStringLiteral("/x.json")));
    }
};

QTEST_GUILESS_MAIN(TstFileStore)
#include "tst_filestore.moc"
