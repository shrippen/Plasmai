#pragma once

#include <QHash>
#include <QObject>
#include <QString>
#include <QStringList>
#include <QVariant>

// -- I18nFallback: i18n() for QML from JSON catalogs --------------------------
//
// The app has no gettext runtime on any platform (Android, Windows, macOS, and Linux
// for one code path). Messages come from JSON catalogs generated from translate/*.po
// by translate/po2json.py and bundled under :/i18n/<lang>.json:
//
//   {msgid: msgstr}                    plain messages
//   {"\u0004" + msgid: [form0, ...]}   plural forms, picked by the language's rule
//   {"\u0004Plural-Forms": "<rule>"}   gettext plural rule, whitespace removed
//
// English source strings are the fallback.
class I18nFallback : public QObject {
    Q_OBJECT
public:
    // language: "de", "pt_BR", …; empty = the system's UI languages.
    explicit I18nFallback(const QString &language = QString(), QObject *parent = nullptr);

    Q_INVOKABLE QString i18n(const QString &text) const { return tr(text); }

    // Domain / context variants used by the vendored kirigami-addons QML
    Q_INVOKABLE QString i18nd(const QString &, const QString &text) const { return tr(text); }
    Q_INVOKABLE QString i18ndc(const QString &, const QString &, const QString &text) const { return tr(text); }

    // Plural: n fills %1; further args fill %2, %3 like KI18n.
    Q_INVOKABLE QString i18np(const QString &singular, const QString &plural, const QVariant &n) const {
        return subst(plural_(singular, plural, n), {n});
    }
    Q_INVOKABLE QString i18np(const QString &singular, const QString &plural, const QVariant &n, const QVariant &a2) const {
        return subst(plural_(singular, plural, n), {n, a2});
    }
    Q_INVOKABLE QString i18np(const QString &singular, const QString &plural, const QVariant &n, const QVariant &a2, const QVariant &a3) const {
        return subst(plural_(singular, plural, n), {n, a2, a3});
    }

    Q_INVOKABLE QString i18n(const QString &text, const QVariant &a1) const {
        return subst(tr(text), {a1});
    }
    Q_INVOKABLE QString i18n(const QString &text, const QVariant &a1, const QVariant &a2) const {
        return subst(tr(text), {a1, a2});
    }
    Q_INVOKABLE QString i18n(const QString &text, const QVariant &a1, const QVariant &a2, const QVariant &a3) const {
        return subst(tr(text), {a1, a2, a3});
    }
    Q_INVOKABLE QString i18n(const QString &text, const QVariant &a1, const QVariant &a2, const QVariant &a3, const QVariant &a4) const {
        return subst(tr(text), {a1, a2, a3, a4});
    }

    // Index into the plural forms for n under a gettext rule (whitespace removed).
    // Only the rules of the shipped languages; po2json.py refuses any other.
    //   "(n!=1)" de, en, …   "(n>1)" fr, pt_BR   "0" ja, zh_CN
    //   East Slavic (ru, uk) and Polish: one / few / many
    static int pluralIndex(const QString &rule, qlonglong n);

private:
    QString tr(const QString &text) const { return m_catalog.value(text, text); }
    QString plural_(const QString &singular, const QString &plural, const QVariant &n) const;
    static QString subst(const QString &text, const QVariantList &args);
    bool loadLanguage(const QString &language);

    QHash<QString, QString> m_catalog;
    QHash<QString, QStringList> m_plurals;
    QString m_rule;
};
