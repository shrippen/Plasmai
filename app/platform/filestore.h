#pragma once

#include <QDir>
#include <QFile>
#include <QObject>
#include <QRegularExpression>
#include <QSaveFile>
#include <QStandardPaths>
#include <QThread>

#include "../appid.h"

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
        const bool ok = write(dir + "/" + fileName, json.toUtf8(), false);
        emit saved(fileName, ok);
    }

    // The app's own files (offline snapshot, outbox): data, not config, and not
    // shared with the widget. name: letters, digits, "_", "-", "." (no path).
    Q_INVOKABLE void loadLocal(const QString &name) {
        QString data;
        if (validName(name)) {
            QFile f(localDir() + "/" + name + ".json");
            if (f.open(QIODevice::ReadOnly | QIODevice::Text)) {
                data = QString::fromUtf8(f.readAll());
            }
        }
        emit localLoaded(name, data);
    }

    Q_INVOKABLE void saveLocal(const QString &name, const QString &json) {
        const bool ok = validName(name) && QDir().mkpath(localDir())
            && write(localDir() + "/" + name + ".json", json.toUtf8(), true);
        emit localSaved(name, ok);
    }

private:
    /**
     * QSaveFile: temp file + rename (like mktemp + mv in sharedConfig.sh), so a
     * killed app never leaves a half-written file. On Windows the rename can be
     * refused ("Access denied") while a scanner still holds the fresh temp file:
     * try again shortly, and as a last resort write the file in place.
     */
    static bool write(const QString &path, const QByteArray &data, bool ownerOnly) {
        QString error;
        for (int attempt = 0; attempt < 5; ++attempt) {
            if (attempt > 0) {
                QThread::msleep(50 * attempt);
            }
            QSaveFile f(path);
            if (f.open(QIODevice::WriteOnly | QIODevice::Text)) {
                if (ownerOnly) {
                    f.setPermissions(QFileDevice::ReadOwner | QFileDevice::WriteOwner);
                }
                f.write(data);
                if (f.commit()) {
                    return true;
                }
            }
            error = f.errorString();
        }

        QFile direct(path);
        if (direct.open(QIODevice::WriteOnly | QIODevice::Truncate | QIODevice::Text)
                && direct.write(data) == data.size() && direct.flush()) {
            qWarning("plasmai: %s written in place (%s)", qPrintable(path), qPrintable(error));
            return true;
        }
        qWarning("plasmai: could not save %s: %s", qPrintable(path), qPrintable(error));
        return false;
    }

    static bool validName(const QString &name) {
        static const QRegularExpression pattern(QStringLiteral("^[A-Za-z0-9_-][A-Za-z0-9_.-]*$"));
        return pattern.match(name).hasMatch();
    }

    static QString localDir() {
        return QStandardPaths::writableLocation(QStandardPaths::AppDataLocation) + "/app";
    }

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
    void localLoaded(const QString &name, const QString &data);
    void localSaved(const QString &name, bool ok);
};
