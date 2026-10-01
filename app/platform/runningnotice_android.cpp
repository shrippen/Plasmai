#include "runningnotice.h"

#include <QCoreApplication>
#include <QGuiApplication>
#include <QJniObject>

namespace {
// The Java side: android/src/com/github/shrippen/plasmai/RunningNotice.java
constexpr const char *JAVA_CLASS = "com/github/shrippen/plasmai/RunningNotice";
constexpr const char *SHOW_SIGNATURE =
    "(Landroid/content/Context;Ljava/lang/String;Ljava/lang/String;J)V";
constexpr const char *CLEAR_SIGNATURE = "(Landroid/content/Context;)V";

QJniObject context()
{
    return QNativeInterface::QAndroidApplication::context();
}
}

RunningNotice::RunningNotice(QObject *parent)
    : QObject(parent)
{
    // On Android 13+ the first notification asks for permission; the prompt covers the
    // app, so post again when it is gone (inactive -> active) in case it was granted.
    connect(qGuiApp, &QGuiApplication::applicationStateChanged, this, [this](Qt::ApplicationState state) {
        if (state == Qt::ApplicationActive && m_shown) {
            show(m_title, m_body, m_startedAtMs);
        }
    });
}

bool RunningNotice::isSupported()
{
    return true;
}

void RunningNotice::show(const QString &title, const QString &body, qint64 startedAtMs)
{
    m_shown = true;
    m_title = title;
    m_body = body;
    m_startedAtMs = startedAtMs;

    QJniObject::callStaticMethod<void>(JAVA_CLASS, "show", SHOW_SIGNATURE,
                                       context().object(),
                                       QJniObject::fromString(title).object<jstring>(),
                                       QJniObject::fromString(body).object<jstring>(),
                                       static_cast<jlong>(startedAtMs));
}

void RunningNotice::clear()
{
    m_shown = false;

    QJniObject::callStaticMethod<void>(JAVA_CLASS, "clear", CLEAR_SIGNATURE, context().object());
}
