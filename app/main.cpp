#include <QGuiApplication>
#include <QIcon>
#include <QtQml>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <cstdio>

#include "addons/yearmodel.h"
#include "addons/monthmodel.h"
#include "addons/infinitecalendarviewmodel.h"
#include "appid.h"
#include "i18nfallback.h"
#include "platform/filestore.h"
#include "platform/idlewatcher.h"
#include "platform/networkstatus.h"
#include "platform/notifier.h"
#include "platform/tokenstore.h"
#include "platform/useragentnam.h"
#ifdef Q_OS_ANDROID
#include "platform/androidbackfilter.h"
#endif
#ifdef PLASMAI_TEST_DRIVER
#include "testdriver.h"
#endif

// Platform code lives in platform/ (one file per service, per platform where it
// differs; CMakeLists.txt picks them). This file wires them into QML.

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

    // Names the token files and QStandardPaths depend on: keep them as the builds had them
    // (desktop: KAboutData's component name and domain; Android: Qt's defaults as set here).
#ifdef Q_OS_ANDROID
    app.setApplicationName(QStringLiteral("Plasmai"));
    app.setOrganizationName(QStringLiteral("shrippen"));
#else
    app.setApplicationName(APP_ID);
    app.setOrganizationDomain(QStringLiteral("kde.org"));
    app.setApplicationDisplayName(QStringLiteral("Plasmai"));
    // Desktop identity (Flathub ID); APP_ID stays the keychain service and the config folder shared with the widget.
    QGuiApplication::setDesktopFileName(QStringLiteral("io.github.shrippen.Plasmai"));
#endif
    app.setApplicationVersion(QStringLiteral("2.0.1"));

    // Singletons
    auto *tokenStore = new TokenStore(&app);
    auto *fileStore = new FileStore(&app);

    // Vendored kirigami-addons dateandtime module (see addons/README.md)
    qmlRegisterType<YearModel>("org.kde.kirigamiaddons.dateandtime", 1, 0, "YearModel");
    qmlRegisterType<MonthModel>("org.kde.kirigamiaddons.dateandtime", 1, 0, "MonthModel");
    qmlRegisterType<InfiniteCalendarViewModel>("org.kde.kirigamiaddons.dateandtime", 1, 0, "InfiniteCalendarViewModel");

    UserAgentNamFactory namFactory; // outlives the engine
    QQmlApplicationEngine engine;
    engine.setNetworkAccessManagerFactory(&namFactory);
    QObject::connect(&engine, &QQmlApplicationEngine::objectCreationFailed,
                     &app, []() {
        fprintf(stderr, "QML object creation failed\n");
        fflush(stderr);
    }, Qt::QueuedConnection);
    I18nFallback i18nFallback;
    engine.rootContext()->setContextObject(&i18nFallback);
    engine.rootContext()->setContextProperty(QStringLiteral("TokenStore"), tokenStore);
#ifdef PLASMAI_DEMO
    engine.rootContext()->setContextProperty(QStringLiteral("plasmaiDemoBuild"), true);
#else
    engine.rootContext()->setContextProperty(QStringLiteral("plasmaiDemoBuild"), false);
#endif
    engine.rootContext()->setContextProperty(QStringLiteral("FileStore"), fileStore);
    // Platform services: offered to QML only where this platform has them.
    if (IdleWatcher::isSupported()) {
        engine.rootContext()->setContextProperty(QStringLiteral("idleWatcher"), new IdleWatcher(&app));
    }
    if (Notifier::isSupported()) {
        engine.rootContext()->setContextProperty(QStringLiteral("notifier"), new Notifier(&app));
    }
    if (NetworkStatus::isSupported()) {
        engine.rootContext()->setContextProperty(QStringLiteral("networkStatus"), new NetworkStatus(&app));
    }

    // Add QRC import path so Kirigami platform plugin can find style modules
#ifdef Q_OS_ANDROID
    engine.addImportPath(QStringLiteral("qrc:/qt/qml"));
#endif

    engine.load(QUrl(QStringLiteral("qrc:/qml/main.qml")));
    if (engine.rootObjects().isEmpty()) {
        fprintf(stderr, "plasmai-app: failed to load QML\n");
        return -1;
    }
#ifdef Q_OS_ANDROID
    app.installEventFilter(new AndroidBackFilter(&engine));
#endif
#ifdef PLASMAI_TEST_DRIVER
    if (qEnvironmentVariableIsSet("PLASMAI_TEST_SCRIPT")) {
        auto *win = qobject_cast<QQuickWindow *>(engine.rootObjects().first());
        new TestDriver(win, &engine, qEnvironmentVariable("PLASMAI_TEST_SCRIPT"),
                       qEnvironmentVariable("PLASMAI_TEST_OUT", QStringLiteral(".")), &app);
    }
#endif
    return app.exec();
}
