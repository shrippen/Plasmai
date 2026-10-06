#pragma once

#include <QDir>
#include <QFile>
#include <QObject>
#include <QRegularExpression>
#include <QSaveFile>
#include <QStandardPaths>

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
        // QSaveFile: temp file + rename (like mktemp + mv in sharedConfig.sh),
        // so a killed app never leaves a half-written shared.json.
        QSaveFile f(dir + "/" + fileName);
        bool ok = f.open(QIODevice::WriteOnly | QIODevice::Text);
        if (ok) {
            f.write(json.toUtf8());
            ok = f.commit();
        }
        if (!ok) {
            qWarning("plasmai: could not save %s: %s", qPrintable(fileName), qPrintable(f.errorString()));
        }
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
        bool ok = validName(name) && QDir().mkpath(localDir());
        if (ok) {
            QSaveFile f(localDir() + "/" + name + ".json");
            ok = f.open(QIODevice::WriteOnly | QIODevice::Text);
            if (ok) {
                f.setPermissions(QFileDevice::ReadOwner | QFileDevice::WriteOwner);
                f.write(json.toUtf8());
                ok = f.commit();
            }
            if (!ok) {
                qWarning("plasmai: could not save %s: %s", qPrintable(name), qPrintable(f.errorString()));
            }
        }
        emit localSaved(name, ok);
    }

private:
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
