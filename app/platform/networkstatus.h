#pragma once

#include <QNetworkInformation>
#include <QObject>

// -- NetworkStatus: is a network there (QNetworkInformation) ---------------
// Offered to QML only where Qt has a reachability backend (NetworkManager,
// Android, Windows, macOS). Only "disconnected" counts as offline: a Kimai in
// the local network is reachable with Local or Site reachability, and Unknown
// must not block anything.

class NetworkStatus : public QObject {
    Q_OBJECT
    Q_PROPERTY(bool reachable READ reachable NOTIFY reachableChanged)
public:
    static bool isSupported() {
        return QNetworkInformation::loadBackendByFeatures(QNetworkInformation::Feature::Reachability);
    }

    explicit NetworkStatus(QObject *parent = nullptr) : QObject(parent) {
        connect(QNetworkInformation::instance(), &QNetworkInformation::reachabilityChanged,
                this, &NetworkStatus::reachableChanged);
    }

    bool reachable() const {
        return QNetworkInformation::instance()->reachability() != QNetworkInformation::Reachability::Disconnected;
    }

signals:
    void reachableChanged();
};
