#include "trackingnotice.h"

#include <QCoreApplication>
#include <QJniObject>
#include <QtCore/qjnitypes.h>

// The Java side builds and posts the notification (app/android/src).
Q_DECLARE_JNI_CLASS(TrackingNoticeJava, "com/github/shrippen/plasmai/TrackingNotice")

TrackingNotice::TrackingNotice(QObject *parent)
    : QObject(parent)
{
}

bool TrackingNotice::isSupported()
{
    return true;
}

void TrackingNotice::show(const QString &title, const QString &text, qint64 sinceMsecs)
{
    QtJniTypes::TrackingNoticeJava::callStaticMethod<void>(
        "show", QNativeInterface::QAndroidApplication::context(), title, text, jlong(sinceMsecs));
}

void TrackingNotice::hide()
{
    QtJniTypes::TrackingNoticeJava::callStaticMethod<void>(
        "hide", QNativeInterface::QAndroidApplication::context());
}
