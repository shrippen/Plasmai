#pragma once

#include <QObject>
#include <QString>
#include <functional>

// -- TokenStore: API tokens in the platform's secure storage ----------------
//
// QtKeychain on every platform, never plain text:
//   Linux / Plasma Mobile  Secret Service or KWallet
//   Android                encrypted with a key in the Android Keystore
//   Windows                Credential Manager     macOS  Keychain
// Its insecure fallback (plain text when no backend answers) stays off: no
// secure storage means the save fails and the user is told so.
//
// Builds before 2.0.2 wrote tokens to <AppData>/tokens/<profile>.token. A load
// moves such a file into the keychain and deletes it; while the keychain cannot
// take it (none running), the file stays so the token is not lost.
class TokenStore : public QObject {
    Q_OBJECT
public:
    using QObject::QObject;

    Q_INVOKABLE void load(const QString &profileId);
    Q_INVOKABLE void save(const QString &profileId, const QString &token);
    Q_INVOKABLE void remove(const QString &profileId);

signals:
    void loaded(const QString &profileId, const QString &token);
    // error: the keychain's message when ok is false
    void saved(const QString &profileId, bool ok, const QString &error);
    void removed(const QString &profileId, bool ok);

private:
    void migrate(const QString &profileId);
    void write(const QString &profileId, const QString &token, const std::function<void(bool, const QString &)> &done);

    static QString legacyPath(const QString &profileId);
    static QString readLegacy(const QString &profileId);
    static void removeLegacy(const QString &profileId);
};
