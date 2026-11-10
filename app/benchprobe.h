#pragma once
// Internal benchmark (demo builds only, -DPLASMAI_DEMO; never shipped): what QML cannot
// read itself. Memory and CPU time of this process from /proc/self (Linux and Android),
// the time since the app started, and the start's phases from the process start on.
//
//   BenchRunner.qml ─▶ benchProbe.rssKb() / cpuMs() / uptimeMs() / requested / startupOnly
//   main.cpp        ─▶ benchProbe->mark("loaded"), ... ─▶ benchProbe.marks()
#include <QElapsedTimer>
#include <QFile>
#include <QObject>
#include <QRegularExpression>
#include <QVariantMap>
#include <ctime>
#if defined(Q_OS_LINUX) || defined(Q_OS_ANDROID)
#include <unistd.h>
#endif

class BenchProbe : public QObject {
    Q_OBJECT
    /** The benchmark was asked for: PLASMAI_BENCH=1 or the argument --bench (Android: intent extra). */
    Q_PROPERTY(bool requested READ requested CONSTANT)
    /** Only the start is measured, then the app quits (PLASMAI_BENCH=startup, --bench-startup). */
    Q_PROPERTY(bool startupOnly READ startupOnly CONSTANT)

public:
    BenchProbe(bool requested, bool startupOnly, QObject *parent = nullptr)
        : QObject(parent), m_requested(requested || startupOnly), m_startupOnly(startupOnly)
    {
        m_clock.start();
        m_beforeMain = processAgeMs();
        m_marks.insert(QStringLiteral("main"), m_beforeMain);
    }

    bool requested() const { return m_requested; }
    bool startupOnly() const { return m_startupOnly; }

    /** Notes ms since the process started under `name` (the first time only). */
    Q_INVOKABLE void mark(const QString &name)
    {
        if (!m_marks.contains(name)) {
            m_marks.insert(name, sinceProcessStartMs());
        }
    }

    /** The marks so far: name ─▶ ms since the process started ("main": when main() began). */
    Q_INVOKABLE QVariantMap marks() const { return m_marks; }

    /** ms since the process started (fork; on Android the zygote's fork for this app). */
    Q_INVOKABLE qint64 sinceProcessStartMs() const { return m_beforeMain < 0 ? -1 : m_beforeMain + m_clock.elapsed(); }

    /** Resident memory in KiB, -1 if unknown. */
    Q_INVOKABLE qint64 rssKb() const
    {
        QFile f(QStringLiteral("/proc/self/status"));
        if (!f.open(QIODevice::ReadOnly)) {
            return -1;
        }
        const auto m = QRegularExpression(QStringLiteral("VmRSS:\\s+(\\d+)")).match(QString::fromLatin1(f.readAll()));
        return m.hasMatch() ? m.captured(1).toLongLong() : -1;
    }

    /** CPU time (user + system) of the process in ms, -1 if unknown. */
    Q_INVOKABLE qint64 cpuMs() const
    {
        QFile f(QStringLiteral("/proc/self/stat"));
        if (!f.open(QIODevice::ReadOnly)) {
            return -1;
        }
        // The name in parentheses may hold spaces: count the fields after its ")".
        const QString text = QString::fromLatin1(f.readAll());
        const QStringList fields = text.mid(text.lastIndexOf(QLatin1Char(')')) + 2).split(QLatin1Char(' '));
        const int utime = 11; // field 14 of stat, the 12th after the name
        if (fields.size() <= utime + 1) {
            return -1;
        }
        const qint64 ticks = fields.at(utime).toLongLong() + fields.at(utime + 1).toLongLong();
        return ticks * 1000 / sysconf(_SC_CLK_TCK);
    }

    /** ms since the probe was made (first thing in main). */
    Q_INVOKABLE qint64 uptimeMs() const { return m_clock.elapsed(); }

private:
    /** Age of this process in ms from /proc/self/stat's start time (clock ticks since boot), -1 if unknown. */
    // From the process start on; -1 where there is no /proc (Windows, macOS).
    static qint64 processAgeMs()
    {
#if defined(Q_OS_LINUX) || defined(Q_OS_ANDROID)
        QFile f(QStringLiteral("/proc/self/stat"));
        timespec now {};
        if (!f.open(QIODevice::ReadOnly) || clock_gettime(CLOCK_BOOTTIME, &now) != 0) {
            return -1;
        }
        const QString text = QString::fromLatin1(f.readAll());
        const QStringList fields = text.mid(text.lastIndexOf(QLatin1Char(')')) + 2).split(QLatin1Char(' '));
        const int starttime = 19; // field 22 of stat
        if (fields.size() <= starttime) {
            return -1;
        }
        const qint64 startMs = fields.at(starttime).toLongLong() * 1000 / sysconf(_SC_CLK_TCK);
        return qint64(now.tv_sec) * 1000 + now.tv_nsec / 1000000 - startMs;
#else
        return -1;
#endif
    }

    bool m_requested;
    bool m_startupOnly;
    qint64 m_beforeMain = -1;
    QElapsedTimer m_clock;
    QVariantMap m_marks;
};
