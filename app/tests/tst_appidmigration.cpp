#include <QDir>
#include <QFile>
#include <QStandardPaths>
#include <QTemporaryDir>
#include <QTest>

#include "platform/appidmigration.h"

// Up to 2.6.3 the desktop app's folders had the old id's name; the first start moves them.
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

    void oldFoldersMoveOnce()
    {
        write(config(m_old) + "/shared.json", "{\"profiles\":1}");
        write(data(m_old) + "/app/today.json", "[1]");
        write(cache(m_old) + "/catalog-cache.json", "{}");
        QCoreApplication::setApplicationName(m_new);

        QVERIFY(AppIdMigration::moveFolders(m_old, m_new) >= 2);
        QCOMPARE(read(config(m_new) + "/shared.json"), QByteArray("{\"profiles\":1}"));
        QCOMPARE(read(data(m_new) + "/app/today.json"), QByteArray("[1]"));
        QCOMPARE(read(cache(m_new) + "/catalog-cache.json"), QByteArray("{}"));
        QVERIFY(!QFileInfo::exists(config(m_old)));
        QVERIFY(!QFileInfo::exists(data(m_old)));
        // The application name is left as it was.
        QCOMPARE(QCoreApplication::applicationName(), m_new);
        // A second start finds nothing to move.
        QCOMPARE(AppIdMigration::moveFolders(m_old, m_new), 0);
    }

    void newFolderIsNotOverwritten()
    {
        write(config(m_old) + "/shared.json", "old");
        write(config(m_new) + "/shared.json", "new");

        AppIdMigration::moveFolders(m_old, m_new);
        QCOMPARE(read(config(m_new) + "/shared.json"), QByteArray("new"));
        QCOMPARE(read(config(m_old) + "/shared.json"), QByteArray("old"));
    }

    void nothingToMove()
    {
        QCOMPARE(AppIdMigration::moveFolders(m_old, m_new), 0);
        QVERIFY(!QFileInfo::exists(config(m_new)));
    }
};

QTEST_GUILESS_MAIN(TstAppIdMigration)
#include "tst_appidmigration.moc"
