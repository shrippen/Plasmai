#include <QGuiApplication>
#ifdef PLASMAI_TRAY
#include <QApplication>
#endif
#include <QColor>
#include <QIcon>
#include <QPalette>
#include <QStyleHints>
#include <QtQml>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <cstdio>

#include "addons/yearmodel.h"
#include "addons/monthmodel.h"
#include "addons/infinitecalendarviewmodel.h"
#include "appid.h"
#include "i18nfallback.h"
#include "platform/autostart.h"
#include "platform/filestore.h"
#include "platform/idlewatcher.h"
#include "platform/networkstatus.h"
#include "platform/notifier.h"
#include "platform/tokenstore.h"
#include "platform/trackingnotice.h"
#include "platform/useragentnam.h"
#ifdef PLASMAI_TRAY
#include "platform/traycontroller.h"
#endif
#ifdef Q_OS_ANDROID
#include "platform/androidbackfilter.h"
#endif
#ifdef PLASMAI_TEST_DRIVER
#include "testdriver.h"
#endif

// Platform code lives in platform/ (one file per service, per platform where it
// differs; CMakeLists.txt picks them). This file wires them into QML.


#if defined(Q_OS_WIN) || defined(Q_OS_MACOS)
// Breeze, the colors Kirigami's own apps use: what the Kirigami and Basic controls draw with here.
static QPalette desktopPalette(bool dark)
{
    struct Colors { QColor window, base, text, disabled, mid, highlight; };
    auto rgb = [](const char *hex) { return QColor(QString::fromLatin1(hex)); };
    const Colors c = dark ? Colors{rgb("#31363b"), rgb("#232629"), rgb("#eff0f1"), rgb("#7f8c8d"), rgb("#4d5359"), rgb("#3daee9")}
                          : Colors{rgb("#eff0f1"), rgb("#fcfcfc"), rgb("#232629"), rgb("#a1a9b1"), rgb("#bcc0c4"), rgb("#3daee9")};
    QPalette p;
    p.setColor(QPalette::Window, c.window);
    p.setColor(QPalette::WindowText, c.text);
    p.setColor(QPalette::Base, c.base);
    p.setColor(QPalette::AlternateBase, c.window);
    p.setColor(QPalette::Text, c.text);
    // Button = Window: the tool bar, its buttons and the flat buttons are one surface; a
    // button shows itself by its border (Mid) and on hover.
    p.setColor(QPalette::Button, c.window);
    p.setColor(QPalette::ButtonText, c.text);
    p.setColor(QPalette::Mid, c.mid);
    p.setColor(QPalette::Light, rgb(dark ? "#4d5359" : "#ffffff"));
    p.setColor(QPalette::Dark, rgb(dark ? "#1b1e20" : "#a0a4a8"));
    p.setColor(QPalette::Highlight, c.highlight);
    p.setColor(QPalette::HighlightedText, rgb("#fcfcfc"));
    p.setColor(QPalette::ToolTipBase, c.base);
    p.setColor(QPalette::ToolTipText, c.text);
    p.setColor(QPalette::PlaceholderText, c.disabled);
    p.setColor(QPalette::Link, rgb("#2980b9"));
    for (auto role : {QPalette::WindowText, QPalette::Text, QPalette::ButtonText}) {
        p.setColor(QPalette::Disabled, role, c.disabled);
    }
    return p;
}

static void applyDesktopScheme()
{
    const bool dark = QGuiApplication::styleHints()->colorScheme() == Qt::ColorScheme::Dark;
    QGuiApplication::setPalette(desktopPalette(dark));
    const QString icons = dark ? QStringLiteral("breeze-dark") : QStringLiteral("breeze-light");
    QIcon::setThemeName(icons);
    QIcon::setFallbackThemeName(icons);
}
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
#elif defined(Q_OS_WIN) || defined(Q_OS_MACOS)
    // The native styles cannot be customized (a Button with our own contentItem shows
    // no label): the app draws its controls itself, on Basic. An explicit choice wins.
    if (!qEnvironmentVariableIsSet("QT_QUICK_CONTROLS_STYLE")) {
        qputenv("QT_QUICK_CONTROLS_STYLE", "Basic");
    }
#endif

#ifdef PLASMAI_TRAY
    // The tray icon's menu is a QMenu: widgets need a QApplication.
    QApplication app(argc, argv);
#else
    QGuiApplication app(argc, argv);
#endif

#if defined(Q_OS_ANDROID)
    // Android has no system icon theme: use the Breeze Dark subset bundled in the QRC
    // (icons/breeze-dark) so icon.name / Kirigami.Icon resolve like on the Plasmoid.
    QIcon::setThemeSearchPaths(QIcon::themeSearchPaths() << QStringLiteral(":/icons"));
    QIcon::setThemeName(QStringLiteral("breeze-dark"));
    QIcon::setFallbackThemeName(QStringLiteral("breeze-dark"));
#elif defined(Q_OS_WIN) || defined(Q_OS_MACOS)
    // No system icon theme and no Kirigami platform theme here: the app hands Qt the Breeze
    // colors itself, light or dark as the system is set (the Basic style follows neither, and
    // Kirigami's light text on its light windows was unreadable), and picks the matching
    // subset of the bundled icons (dark icons for the light scheme and the other way round).
    QIcon::setThemeSearchPaths(QIcon::themeSearchPaths() << QStringLiteral(":/icons"));
    applyDesktopScheme();
    QObject::connect(QGuiApplication::styleHints(), &QStyleHints::colorSchemeChanged, &app, &applyDesktopScheme);
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
    app.setApplicationVersion(QStringLiteral("2.5.0"));

#ifdef PLASMAI_TRAY
    // One tray client per user: a second start opens the running one's popup.
    if (TrayController::handOverToRunning()) {
        return 0;
    }
    // Started at login (Autostart): the icon only, the popup on the first click.
    const bool startHidden = app.arguments().contains(QStringLiteral("--hidden"));
    TrayController *tray = TrayController::isSupported() ? new TrayController(&app) : nullptr;
    if (tray) {
        // The popup hides instead of closing; only "Quit" ends the app.
        app.setQuitOnLastWindowClosed(false);
    }
#endif

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
    if (TrackingNotice::isSupported()) {
        engine.rootContext()->setContextProperty(QStringLiteral("trackingNotice"), new TrackingNotice(&app));
    }
    if (Autostart::isSupported()) {
        engine.rootContext()->setContextProperty(QStringLiteral("autostart"), new Autostart(&app));
    }
#ifdef PLASMAI_TRAY
    if (tray) {
        engine.rootContext()->setContextProperty(QStringLiteral("trayClient"), tray);
    }
#endif
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
#ifdef PLASMAI_TRAY
    if (tray) {
        tray->setWindow(qobject_cast<QQuickWindow *>(engine.rootObjects().first()), startHidden);
    }
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
