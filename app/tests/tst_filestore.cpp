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

        store.loadLocal(QStringLiteral("missing"));
        QCOMPARE(loaded.takeFirst().at(1).toString(), QString());
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
        QVERIFY(!(perms & (QFileDevice::ReadGroup | QFileDevice::ReadOther)));
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
