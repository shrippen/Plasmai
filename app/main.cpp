#include <QGuiApplication>
#include <QIcon>
#include <QtQml>
#include "addons/yearmodel.h"
#include "addons/monthmodel.h"
#include "addons/infinitecalendarviewmodel.h"
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QStandardPaths>
#include <QFile>
#include <QSaveFile>
#include <QHash>
#include <QJsonDocument>
#include <QJsonObject>
#include <QLocale>
#include <QDir>
#include <QObject>
#include <cstdio>
#ifdef PLASMAI_TEST_DRIVER
#include "testdriver.h"
#endif

#ifdef HAVE_KF6
#ifdef HAVE_KF6_COREADDONS
#include <KLocalizedString>
#include <KAboutData>
#include <KLocalizedQmlContext>
#endif
#endif

// TokenStore with cross-platform support
#ifdef Qt6Keychain_FOUND
#include <keychain.h>
#define HAS_KEYCHAIN 1
#endif

// Idle detection + native notifications: real Linux/Plasma session only
// (desktop Linux and Plasma Mobile devices both run a Plasma D-Bus session;
// Android does not, so this whole block is compiled out there).
#ifdef HAVE_QTDBUS
#include <QDBusInterface>
#include <QDBusReply>
#include <QVariantList>
#include <QVariantMap>
#endif

// -- I18nFallback: passthrough i18n() when KF6 I18n is unavailable -----------

#if !defined(HAVE_KF6_COREADDONS)
// Android has no KF6 I18n / gettext runtime. Messages are looked up in JSON catalogs
// ({msgid: msgstr}, generated from translate/*.po by translate/po2json.py) that are
// bundled in the QRC under :/i18n/<lang>.json. English source strings are the fallback.
class I18nFallback : public QObject {
    Q_OBJECT
public:
    explicit I18nFallback(QObject *parent = nullptr) : QObject(parent) { loadCatalog(); }

    // 0 extra args
    Q_INVOKABLE QString i18n(const QString &text) const { return tr(text); }

    // Domain / context variants used by the vendored kirigami-addons QML
    Q_INVOKABLE QString i18nd(const QString &, const QString &text) const { return tr(text); }
    Q_INVOKABLE QString i18ndc(const QString &, const QString &, const QString &text) const { return tr(text); }

    // Plural form. Catalogs only carry the two-form (singular/plural) English rule —
    // see translate/po2json.py — good enough since the languages shipped here all use it.
    Q_INVOKABLE QString i18np(const QString &singular, const QString &plural, const QVariant &n) const {
        return tr(n.toInt() == 1 ? singular : plural).arg(n.toString());
    }

    // 1 extra arg
    Q_INVOKABLE QString i18n(const QString &text, const QVariant &a1) const {
        return tr(text).arg(a1.toString());
    }

    // 2 extra args
    Q_INVOKABLE QString i18n(const QString &text, const QVariant &a1, const QVariant &a2) const {
        return tr(text).arg(a1.toString()).arg(a2.toString());
    }

    // 3 extra args
    Q_INVOKABLE QString i18n(const QString &text, const QVariant &a1, const QVariant &a2, const QVariant &a3) const {
        return tr(text).arg(a1.toString()).arg(a2.toString()).arg(a3.toString());
    }

    // 4 extra args
    Q_INVOKABLE QString i18n(const QString &text, const QVariant &a1, const QVariant &a2, const QVariant &a3, const QVariant &a4) const {
        return tr(text).arg(a1.toString()).arg(a2.toString()).arg(a3.toString()).arg(a4.toString());
    }

private:
    QString tr(const QString &text) const { return m_catalog.value(text, text); }

    // Pick the first UI language that has a catalog; English (no file) stops the search.
    void loadCatalog() {
        const QStringList uiLanguages = QLocale::system().uiLanguages();
        for (const QString &ui : uiLanguages) {
            const QString name = QString(ui).replace(QLatin1Char('-'), QLatin1Char('_'));
            const QString base = name.section(QLatin1Char('_'), 0, 0);
            if (base == QLatin1String("en")) {
                return;
            }
            QStringList candidates{name, base};
            if (base == QLatin1String("pt")) candidates << QStringLiteral("pt_BR");
            if (base == QLatin1String("zh")) candidates << QStringLiteral("zh_CN");
            for (const QString &c : std::as_const(candidates)) {
                QFile f(QStringLiteral(":/i18n/%1.json").arg(c));
                if (!f.open(QIODevice::ReadOnly)) {
                    continue;
                }
                const QJsonObject obj = QJsonDocument::fromJson(f.readAll()).object();
                for (auto it = obj.constBegin(); it != obj.constEnd(); ++it) {
                    m_catalog.insert(it.key(), it.value().toString());
                }
                return;
            }
        }
    }

    QHash<QString, QString> m_catalog;
};
#endif

static const QString APP_ID = QStringLiteral("com.github.shrippen.plasmai");

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

// -- FileStore: read / write JSON files in app config dir -----------------

class FileStore : public QObject {
    Q_OBJECT
public:
    using QObject::QObject;

    Q_INVOKABLE void load(const QString &fileName) {
        QString path = configDir() + "/" + fileName;
        QFile f(path);
        QString data;
        if (f.open(QIODevice::ReadOnly | QIODevice::Text)) {
            data = QString::fromUtf8(f.readAll());
        }
        emit loaded(fileName, data);
    }

    Q_INVOKABLE void save(const QString &fileName, const QString &json) {
        QString dir = configDir();
        QDir().mkpath(dir);
        // QSaveFile: temp file + rename (like mktemp + mv in sharedConfig.sh),
        // so a killed app never leaves a half-written shared.json.
        QSaveFile f(dir + "/" + fileName);
        bool ok = f.open(QIODevice::WriteOnly | QIODevice::Text);
        if (ok) {
            f.write(json.toUtf8());
            ok = f.commit();
        }
        emit saved(fileName, ok);
    }

private:
    static QString configDir() {
#ifdef Q_OS_ANDROID
        return QStandardPaths::writableLocation(QStandardPaths::AppDataLocation);
#else
        return QStandardPaths::writableLocation(QStandardPaths::GenericConfigLocation)
            + "/" + APP_ID;
#endif
    }

signals:
    void loaded(const QString &fileName, const QString &data);
    void saved(const QString &fileName, bool ok);
};

// -- IdleWatcher: session idle time via org.freedesktop.ScreenSaver -------
// Same D-Bus source contents/code/idle.sh falls back to on Wayland/Plasma;
// Plasma Mobile devices run a real Plasma Wayland session so this works
// unmodified on-device, same as on a desktop Linux build.

#ifdef HAVE_QTDBUS
class IdleWatcher : public QObject {
    Q_OBJECT
public:
    using QObject::QObject;

    Q_INVOKABLE void checkIdle() {
        QDBusInterface iface(QStringLiteral("org.freedesktop.ScreenSaver"),
                             QStringLiteral("/org/freedesktop/ScreenSaver"),
                             QStringLiteral("org.freedesktop.ScreenSaver"),
                             QDBusConnection::sessionBus());
        if (!iface.isValid()) {
            emit idleChecked(-1, false);
            return;
        }
        QDBusReply<uint> reply = iface.call(QStringLiteral("GetSessionIdleTime"));
        if (!reply.isValid()) {
            emit idleChecked(-1, false);
            return;
        }
        emit idleChecked(static_cast<qint64>(reply.value()), true);
    }

signals:
    void idleChecked(qint64 idleMs, bool ok);
};

// -- Notifier: desktop notifications via org.freedesktop.Notifications ----

class Notifier : public QObject {
    Q_OBJECT
public:
    using QObject::QObject;

    Q_INVOKABLE void notify(const QString &summary, const QString &body) {
        QDBusInterface iface(QStringLiteral("org.freedesktop.Notifications"),
                             QStringLiteral("/org/freedesktop/Notifications"),
                             QStringLiteral("org.freedesktop.Notifications"),
                             QDBusConnection::sessionBus());
        if (!iface.isValid()) {
            emit notified(false);
            return;
        }
        QDBusReply<uint> reply = iface.call(
            QStringLiteral("Notify"),
            APP_ID,               // app_name
            0u,                    // replaces_id
            QStringLiteral("chronometer"), // app_icon
            summary,
            body,
            QStringList(),         // actions
            QVariantMap(),         // hints
            -1);                   // expire_timeout (server default)
        emit notified(reply.isValid());
    }

signals:
    void notified(bool ok);
};
#endif

// -- main ----------------------------------------------------------------

int main(int argc, char *argv[])
{
    // Force Material Dark style for Android to match Plasmoid appearance
#ifdef Q_OS_ANDROID
    qputenv("QT_QUICK_CONTROLS_MATERIAL_THEME", "Dark");
    qputenv("QT_QUICK_CONTROLS_MATERIAL_ACCENT", "#27ae60");
    qputenv("QT_QUICK_CONTROLS_MATERIAL_PRIMARY", "#2d2d2d");
    qputenv("QT_QUICK_CONTROLS_STYLE", "Material");
#endif

    QGuiApplication app(argc, argv);

#ifdef Q_OS_ANDROID
    // Android has no system icon theme: use the Breeze Dark subset bundled in the QRC
    // (icons/breeze-dark) so icon.name / Kirigami.Icon resolve like on the Plasmoid.
    QIcon::setThemeSearchPaths(QIcon::themeSearchPaths() << QStringLiteral(":/icons"));
    QIcon::setThemeName(QStringLiteral("breeze-dark"));
    QIcon::setFallbackThemeName(QStringLiteral("breeze-dark"));
#endif

#ifdef HAVE_KF6_COREADDONS
    KLocalizedString::setApplicationDomain("plasmai");
#ifdef PLASMAI_BUILD_LOCALE_DIR
    // Development runs from the build tree find the compiled catalogs here;
    // installed builds use the regular <prefix>/share/locale.
    if (QDir(QStringLiteral(PLASMAI_BUILD_LOCALE_DIR)).exists()) {
        KLocalizedString::addDomainLocaleDir("plasmai", QStringLiteral(PLASMAI_BUILD_LOCALE_DIR));
    }
#endif
    KAboutData aboutData(APP_ID, i18n("Plasmai"),
                         QStringLiteral("2.0.0"),
                         i18n("Time tracking with Kimai, Clockify, Toggl Track, or SolidTime"),
                         KAboutLicense::GPL_V3,
                         i18n("© 2025 Plasmai contributors"));
    KAboutData::setApplicationData(aboutData);
#else
    app.setApplicationName("Plasmai");
    app.setApplicationVersion("2.0.0");
    app.setOrganizationName("shrippen");
#endif

    // Singletons
    auto *tokenStore = new TokenStore(&app);
    auto *fileStore = new FileStore(&app);

    // Vendored kirigami-addons dateandtime module (see addons/README.md)
    qmlRegisterType<YearModel>("org.kde.kirigamiaddons.dateandtime", 1, 0, "YearModel");
    qmlRegisterType<MonthModel>("org.kde.kirigamiaddons.dateandtime", 1, 0, "MonthModel");
    qmlRegisterType<InfiniteCalendarViewModel>("org.kde.kirigamiaddons.dateandtime", 1, 0, "InfiniteCalendarViewModel");

    QQmlApplicationEngine engine;
    QObject::connect(&engine, &QQmlApplicationEngine::objectCreationFailed,
                     &app, []() {
        fprintf(stderr, "QML object creation failed\n");
        fflush(stderr);
    }, Qt::QueuedConnection);
#if defined(HAVE_KF6_COREADDONS)
    KLocalizedQmlContext klocalizedContext(&engine);
    engine.rootContext()->setContextObject(&klocalizedContext);
#else
    I18nFallback i18nFallback;
    engine.rootContext()->setContextObject(&i18nFallback);
#endif
    engine.rootContext()->setContextProperty(QStringLiteral("TokenStore"), tokenStore);
    engine.rootContext()->setContextProperty(QStringLiteral("FileStore"), fileStore);
#ifdef HAVE_QTDBUS
    auto *idleWatcher = new IdleWatcher(&app);
    auto *notifier = new Notifier(&app);
    engine.rootContext()->setContextProperty(QStringLiteral("idleWatcher"), idleWatcher);
    engine.rootContext()->setContextProperty(QStringLiteral("notifier"), notifier);
#endif

    // Add QRC import path so Kirigami platform plugin can find style modules
#ifdef Q_OS_ANDROID
    engine.addImportPath(QStringLiteral("qrc:/qt/qml"));
#endif

    engine.load(QUrl(QStringLiteral("qrc:/qml/main.qml")));
    if (engine.rootObjects().isEmpty()) {
        fprintf(stderr, "plasmai-app: failed to load QML\n");
        return -1;
    }
#ifdef PLASMAI_TEST_DRIVER
    if (qEnvironmentVariableIsSet("PLASMAI_TEST_SCRIPT")) {
        auto *win = qobject_cast<QQuickWindow *>(engine.rootObjects().first());
        new TestDriver(win, &engine, qEnvironmentVariable("PLASMAI_TEST_SCRIPT"),
                       qEnvironmentVariable("PLASMAI_TEST_OUT", QStringLiteral(".")), &app);
    }
#endif
    return app.exec();
}

#include "main.moc"
