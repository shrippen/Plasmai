#include <QDateTime>
#include <QDir>
#include <QFile>
#include <QStandardPaths>
#include <QTemporaryDir>
#include <QTest>

#include "platform/appidmigration.h"

// Up to 2.6.3 the desktop app's folders had the old id's name; the first start copies them.
class TstAppIdMigration : public QObject {
    Q_OBJECT

private:
    const QString m_old = QStringLiteral("tst.old.id");
    const QString m_new = QStringLiteral("tst.New.Id");

    static void write(const QString &path, const QByteArray &data)
    {
        QDir().mkpath(QFileInfo(path).absolutePath());
        QFile f(path);
        QVERIFY(f.open(QIODevice::WriteOnly));
        f.write(data);
    }

    static QByteArray read(const QString &path)
    {
        QFile f(path);
        return f.open(QIODevice::ReadOnly) ? f.readAll() : QByteArray("<missing>");
    }

    QString config(const QString &name) const
    {
        return QStandardPaths::writableLocation(QStandardPaths::GenericConfigLocation) + "/" + name;
    }

    QString data(const QString &name) const
    {
        return QStandardPaths::writableLocation(QStandardPaths::GenericDataLocation) + "/" + name;
    }

    QString cache(const QString &name) const
    {
        return QStandardPaths::writableLocation(QStandardPaths::GenericCacheLocation) + "/" + name;
    }

private slots:
    void initTestCase()
    {
        QStandardPaths::setTestModeEnabled(true);
    }

    void cleanup()
    {
        for (const QString &name : {m_old, m_new}) {
            for (const QString &dir : AppIdMigration::folders(name)) {
                QDir(dir).removeRecursively();
            }
        }
    }

    // Copied, not moved: a widget or app of the old id still running keeps its folders (review
    // of PR #52: moved by the app, an old widget's waiting offline changes were lost).
    void oldFoldersAreCopiedOnce()
    {
        write(config(m_old) + "/shared.json", "{\"profiles\":1}");
        write(data(m_old) + "/app/today.json", "[1]");
        write(cache(m_old) + "/catalog-cache.json", "{}");
        QCoreApplication::setApplicationName(m_new);

        QVERIFY(AppIdMigration::copyFolders(m_old, m_new) >= 2);
        QCOMPARE(read(config(m_new) + "/shared.json"), QByteArray("{\"profiles\":1}"));
        QCOMPARE(read(data(m_new) + "/app/today.json"), QByteArray("[1]"));
        QCOMPARE(read(cache(m_new) + "/catalog-cache.json"), QByteArray("{}"));
        QCOMPARE(read(config(m_old) + "/shared.json"), QByteArray("{\"profiles\":1}"));
        QCOMPARE(read(data(m_old) + "/app/today.json"), QByteArray("[1]"));
        // The application name is left as it was.
        QCOMPARE(QCoreApplication::applicationName(), m_new);
        // A second start copies nothing.
        write(config(m_old) + "/shared.json", "changed");
        QCOMPARE(AppIdMigration::copyFolders(m_old, m_new), 0);
        QCOMPARE(read(config(m_new) + "/shared.json"), QByteArray("{\"profiles\":1}"));
    }

    // The widget's own files (plasmoid/, its outbox among them) are the widget's to take.
    void widgetFilesStay()
    {
        write(data(m_old) + "/app/today.json", "[1]");
        write(data(m_old) + "/plasmoid/offline-outbox-plasmoid-9-default.json", "{\"ops\":[1]}");

        AppIdMigration::copyFolders(m_old, m_new);
        QCOMPARE(read(data(m_new) + "/app/today.json"), QByteArray("[1]"));
        QVERIFY(!QFileInfo::exists(data(m_new) + "/plasmoid"));
        QVERIFY(QFileInfo::exists(data(m_old) + "/plasmoid/offline-outbox-plasmoid-9-default.json"));
    }

    // The new widget may start first: its localStore.sh makes the new data folder with
    // plasmoid/ only. The app's own entries (app/) are still copied (review of PR #52).
    void appEntriesFollowAWidgetThatStartedFirst()
    {
        write(data(m_old) + "/app/offline-outbox-default.json", "{\"ops\":[1]}");
        write(data(m_old) + "/tokens/default.token", "t");
        write(data(m_new) + "/plasmoid/offline-state-plasmoid-5-default.json", "{}");

        QVERIFY(AppIdMigration::copyFolders(m_old, m_new) >= 1);
        QCOMPARE(read(data(m_new) + "/app/offline-outbox-default.json"), QByteArray("{\"ops\":[1]}"));
        // Token files are plain text: never copied (TokenStore takes them from the old place).
        QVERIFY(!QFileInfo::exists(data(m_new) + "/tokens"));
        QCOMPARE(read(data(m_new) + "/plasmoid/offline-state-plasmoid-5-default.json"), QByteArray("{}"));
        // An entry the new folder has already is never overwritten, and a second start copies nothing.
        write(data(m_old) + "/app/offline-outbox-default.json", "changed");
        QCOMPARE(AppIdMigration::copyFolders(m_old, m_new), 0);
        QCOMPARE(read(data(m_new) + "/app/offline-outbox-default.json"), QByteArray("{\"ops\":[1]}"));
        // Taken over once: what the app removes later does not come back from the old folder
        // (sent changes would be sent again).
        QDir(data(m_new) + "/app").removeRecursively();
        QCOMPARE(AppIdMigration::copyFolders(m_old, m_new), 0);
        QVERIFY(!QFileInfo::exists(data(m_new) + "/app"));
    }

    // A start that crashed mid-copy left "<entry>.copy.<pid>"; a later start removes it (review
    // of PR #52). A recent one may be another start's copy in progress and stays.
    void staleCopiesAreRemoved()
    {
        write(data(m_old) + "/app/today.json", "[1]");
        const QString stale = data(m_new) + "/state.json.copy.4711";
        const QString recent = data(m_new) + "/other.json.copy.4712";
        write(stale, "half");
        write(recent, "half");
        QFile part(stale);
        QVERIFY(part.open(QIODevice::ReadWrite));
        QVERIFY(part.setFileTime(QDateTime::currentDateTime().addDays(-1), QFileDevice::FileModificationTime));
        part.close();

        AppIdMigration::copyFolders(m_old, m_new);
        QCOMPARE(read(data(m_new) + "/app/today.json"), QByteArray("[1]"));
        QVERIFY(!QFileInfo::exists(stale));
        QVERIFY(QFileInfo::exists(recent));
    }

    void newFolderIsNotOverwritten()
    {
        write(config(m_old) + "/shared.json", "old");
        write(config(m_new) + "/shared.json", "new");

        AppIdMigration::copyFolders(m_old, m_new);
        QCOMPARE(read(config(m_new) + "/shared.json"), QByteArray("new"));
        QCOMPARE(read(config(m_old) + "/shared.json"), QByteArray("old"));
    }

    void nothingToCopy()
    {
        QCOMPARE(AppIdMigration::copyFolders(m_old, m_new), 0);
        QVERIFY(!QFileInfo::exists(config(m_new)));
    }
};

QTEST_GUILESS_MAIN(TstAppIdMigration)
#include "tst_appidmigration.moc"
