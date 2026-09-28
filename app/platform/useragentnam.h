#pragma once

#include <QGuiApplication>
#include <QNetworkAccessManager>
#include <QNetworkRequest>
#include <QQmlNetworkAccessManagerFactory>

// -- Every request names Plasmai: OpenStreetMap (trip map, place search) asks for it.

class UserAgentNam : public QNetworkAccessManager {
public:
    using QNetworkAccessManager::QNetworkAccessManager;

protected:
    QNetworkReply *createRequest(Operation op, const QNetworkRequest &request, QIODevice *data) override {
        QNetworkRequest named(request);
        named.setHeader(QNetworkRequest::UserAgentHeader,
                        QStringLiteral("Plasmai/%1 (+https://github.com/shrippen/Plasmai)").arg(QGuiApplication::applicationVersion()));
        return QNetworkAccessManager::createRequest(op, named, data);
    }
};

class UserAgentNamFactory : public QQmlNetworkAccessManagerFactory {
public:
    QNetworkAccessManager *create(QObject *parent) override { return new UserAgentNam(parent); }
};
