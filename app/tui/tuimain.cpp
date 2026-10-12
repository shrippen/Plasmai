#include "tuimain.h"

#include <QCoreApplication>
#include <QQmlContext>
#include <QQmlEngine>
#include <QQmlComponent>
#include <cstdio>

#include "../appid.h"
#include "../i18nfallback.h"
#include "../platform/filestore.h"
#include "../platform/tokenstore.h"
#include "../platform/useragentnam.h"
#include "terminal.h"

// The terminal client: the app's Session and providers in a QML engine
// without a window (QtQml only), drawn by Tui.qml through Terminal.
//
//   plasmai-app --tui [--demo]
//     QCoreApplication ─ QQmlEngine ─ qrc:/qml/tui/Tui.qml ─ Session (contents/ui)
//                        └ context: terminal, TokenStore, FileStore

namespace {
const QString kTuiFlag = QStringLiteral("--tui");
const QString kDemoFlag = QStringLiteral("--demo");
}

bool wantsTui(int argc, char *argv[])
{
    for (int i = 1; i < argc; ++i) {
        if (QString::fromLocal8Bit(argv[i]) == kTuiFlag) {
            return true;
        }
    }
    return false;
}

int runTui(int argc, char *argv[], const QString &version)
{
    QCoreApplication app(argc, argv);

    // Same identity as the desktop app: tokens and shared.json are found under it.
    app.setApplicationName(APP_ID);
    app.setOrganizationDomain(QStringLiteral("kde.org"));
    app.setApplicationVersion(version);

    if (!Terminal::isSupported()) {
        fprintf(stderr, "plasmai-app: --tui is not available on this platform\n");
        return 1;
    }
    Terminal terminal;
    if (!terminal.open()) {
        fprintf(stderr, "plasmai-app: --tui needs a terminal\n");
        return 1;
    }

    auto *tokenStore = new TokenStore(&app);
    auto *fileStore = new FileStore(&app);

    UserAgentNamFactory namFactory; // outlives the engine
    QQmlEngine engine;
    engine.setNetworkAccessManagerFactory(&namFactory);
    QObject::connect(&engine, &QQmlEngine::quit, &app, &QCoreApplication::quit);

    I18nFallback i18nFallback;
    QQmlContext *context = engine.rootContext();
    context->setContextObject(&i18nFallback);
    context->setContextProperty(QStringLiteral("terminal"), &terminal);
    context->setContextProperty(QStringLiteral("TokenStore"), tokenStore);
    context->setContextProperty(QStringLiteral("FileStore"), fileStore);
#ifdef PLASMAI_DEMO
    const bool demo = app.arguments().contains(kDemoFlag);
#else
    const bool demo = false;
#endif
    context->setContextProperty(QStringLiteral("tuiDemo"), demo);

    QQmlComponent component(&engine, QUrl(QStringLiteral("qrc:/qml/tui/Tui.qml")));
    QObject *root = component.create();
    if (!root) {
        terminal.close();
        fprintf(stderr, "plasmai-app: %s\n", qPrintable(component.errorString()));
        return 1;
    }

    const int code = app.exec();
    delete root;
    terminal.close();
    return code;
}
