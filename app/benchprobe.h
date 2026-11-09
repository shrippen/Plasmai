#pragma once
// Internal benchmark (demo builds only, -DPLASMAI_DEMO; never shipped): what QML cannot
// read itself. Memory and CPU time of this process from /proc/self (Linux and Android),
// and the time since the app started.
//
//   BenchRunner.qml ─▶ benchProbe.rssKb() / cpuMs() / uptimeMs() / requested
#include <QElapsedTimer>
#include <QFile>
#include <QObject>
#include <QRegularExpression>
#include <unistd.h>

class BenchProbe : public QObject {
    Q_OBJECT
    /** The benchmark was asked for: PLASMAI_BENCH=1 or the argument --bench (Android: intent extra). */
    Q_PROPERTY(bool requested READ requested CONSTANT)

public:
    BenchProbe(bool requested, QObject *parent = nullptr)
        : QObject(parent), m_requested(requested)
    {
        m_clock.start();
    }

    bool requested() const { return m_requested; }

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
    bool m_requested;
    QElapsedTimer m_clock;
};
