#pragma once
// Scripted UI driver for automated checks of the desktop / Plasma Mobile build.
// Only compiled with -DPLASMAI_TEST_DRIVER=ON (off by default, never shipped).
//
// PLASMAI_TEST_SCRIPT=<file> runs one command per line ('#' starts a comment):
//   size W H        resize the window
//   wait MS         wait
//   grab NAME       save the window content to $PLASMAI_TEST_OUT/NAME.png (this window only)
//   click X Y       left click at window coordinates
//   text STRING     type text into the focused item
//   key NAME        Return, Escape, Backspace, Tab, Down, Up
//   scroll X Y DY   mouse wheel (positive = up)
//   js EXPR         evaluate a JavaScript expression in main.qml's context (ids resolve)
//   quit
#include <QCoreApplication>
#include <QFile>
#include <QImage>
#include <QKeyEvent>
#include <QMouseEvent>
#include <QObject>
#include <QQmlContext>
#include <QQmlExpression>
#include <QtQml/qqml.h>
#include <QQuickItem>
#include <QQuickWindow>
#include <QTimer>
#include <QWheelEvent>

class TestDriver : public QObject {
public:
    TestDriver(QQuickWindow *window, QQmlEngine *engine, const QString &scriptPath, const QString &outDir, QObject *parent = nullptr)
        : QObject(parent), m_window(window), m_engine(engine), m_out(outDir)
    {
        QFile f(scriptPath);
        if (f.open(QIODevice::ReadOnly | QIODevice::Text)) {
            const auto lines = QString::fromUtf8(f.readAll()).split(QLatin1Char('\n'));
            for (const QString &l : lines) {
                const QString t = l.trimmed();
                if (!t.isEmpty() && !t.startsWith(QLatin1Char('#'))) m_lines << t;
            }
        }
        QTimer::singleShot(0, this, &TestDriver::next);
    }

private:
    void next() {
        if (m_pos >= m_lines.size()) {
            QCoreApplication::quit();
            return;
        }
        const QString line = m_lines.at(m_pos++);
        const QString cmd = line.section(QLatin1Char(' '), 0, 0);
        const QString arg = line.section(QLatin1Char(' '), 1);
        const QStringList a = arg.split(QLatin1Char(' '), Qt::SkipEmptyParts);
        int delay = 150;
        if (cmd == QLatin1String("size") && a.size() >= 2) {
            m_window->resize(a[0].toInt(), a[1].toInt());
        } else if (cmd == QLatin1String("wait") && !a.isEmpty()) {
            delay = a[0].toInt();
        } else if (cmd == QLatin1String("grab") && !a.isEmpty()) {
            m_window->grabWindow().save(m_out + QLatin1Char('/') + a[0] + QStringLiteral(".png"));
        } else if (cmd == QLatin1String("click") && a.size() >= 2) {
            click(QPointF(a[0].toDouble(), a[1].toDouble()));
        } else if (cmd == QLatin1String("text")) {
            for (const QChar c : arg) key(0, QString(c));
        } else if (cmd == QLatin1String("key") && !a.isEmpty()) {
            static const QHash<QString, int> keys{{"Return", Qt::Key_Return}, {"Escape", Qt::Key_Escape},
                {"Backspace", Qt::Key_Backspace}, {"Tab", Qt::Key_Tab}, {"Down", Qt::Key_Down}, {"Up", Qt::Key_Up}};
            key(keys.value(a[0], 0), QString());
        } else if (cmd == QLatin1String("scroll") && a.size() >= 3) {
            const QPointF p(a[0].toDouble(), a[1].toDouble());
            QWheelEvent ev(p, m_window->mapToGlobal(p), QPoint(), QPoint(0, a[2].toInt()), Qt::NoButton,
                           Qt::NoModifier, Qt::NoScrollPhase, false);
            QCoreApplication::sendEvent(m_window, &ev);
        } else if (cmd == QLatin1String("js")) {
            // The window's own context, so ids declared in main.qml resolve.
            QQmlContext *context = qmlContext(m_window);
            QQmlExpression expr(context ? context : m_engine->rootContext(), m_window, arg);
            expr.evaluate();
            if (expr.hasError()) qWarning() << "js:" << expr.error().toString();
        } else if (cmd == QLatin1String("quit")) {
            QCoreApplication::quit();
            return;
        }
        QTimer::singleShot(delay, this, &TestDriver::next);
    }

    void click(const QPointF &p) {
        for (auto type : {QEvent::MouseButtonPress, QEvent::MouseButtonRelease}) {
            QMouseEvent ev(type, p, m_window->mapToGlobal(p), Qt::LeftButton,
                           type == QEvent::MouseButtonPress ? Qt::LeftButton : Qt::NoButton, Qt::NoModifier);
            QCoreApplication::sendEvent(m_window, &ev);
        }
    }

    void key(int code, const QString &text) {
        QObject *target = m_window->activeFocusItem() ? static_cast<QObject *>(m_window->activeFocusItem()) : m_window;
        for (auto type : {QEvent::KeyPress, QEvent::KeyRelease}) {
            QKeyEvent ev(type, code, Qt::NoModifier, text);
            QCoreApplication::sendEvent(target, &ev);
        }
    }

    QQuickWindow *m_window;
    QQmlEngine *m_engine;
    QString m_out;
    QStringList m_lines;
    int m_pos = 0;
};
