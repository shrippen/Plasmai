#include "i18nfallback.h"

#include <QFile>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QLocale>

namespace {
// Key prefix of plural entries and of the rule (gettext's context separator,
// never part of a msgid).
const QChar PLURAL_PREFIX(0x0004);
const QString PLURAL_FORMS_KEY = QString(PLURAL_PREFIX) + QStringLiteral("Plural-Forms");

const QString RULE_NOT_ONE = QStringLiteral("(n!=1)");
const QString RULE_ABOVE_ONE = QStringLiteral("(n>1)");
const QString RULE_SINGLE = QStringLiteral("0");
const QString RULE_EAST_SLAVIC = QStringLiteral("(n%10==1&&n%100!=11?0:n%10>=2&&n%10<=4&&(n%100<10||n%100>=20)?1:2)");
const QString RULE_POLISH = QStringLiteral("(n==1?0:n%10>=2&&n%10<=4&&(n%100<10||n%100>=20)?1:2)");
}

I18nFallback::I18nFallback(const QString &language, QObject *parent)
    : QObject(parent)
    , m_rule(RULE_NOT_ONE)
{
    if (!language.isEmpty()) {
        loadLanguage(language);
        return;
    }

    // First UI language with a catalog; English (no file) stops the search.
    const QStringList uiLanguages = QLocale::system().uiLanguages();
    for (const QString &ui : uiLanguages) {
        const QString name = QString(ui).replace(QLatin1Char('-'), QLatin1Char('_'));
        if (name.section(QLatin1Char('_'), 0, 0) == QLatin1String("en")) {
            return;
        }
        if (loadLanguage(name)) {
            return;
        }
    }
}

int I18nFallback::pluralIndex(const QString &rule, qlonglong n)
{
    const qlonglong abs = n < 0 ? -n : n;
    const qlonglong n10 = abs % 10;
    const qlonglong n100 = abs % 100;
    const bool few = n10 >= 2 && n10 <= 4 && (n100 < 10 || n100 >= 20);

    if (rule == RULE_SINGLE) {
        return 0;
    }
    if (rule == RULE_ABOVE_ONE) {
        return abs > 1 ? 1 : 0;
    }
    if (rule == RULE_EAST_SLAVIC) {
        return (n10 == 1 && n100 != 11) ? 0 : (few ? 1 : 2);
    }
    if (rule == RULE_POLISH) {
        return abs == 1 ? 0 : (few ? 1 : 2);
    }
    return abs != 1 ? 1 : 0;
}

QString I18nFallback::plural_(const QString &singular, const QString &plural, const QVariant &n) const
{
    const qlonglong count = n.toLongLong();
    const QStringList forms = m_plurals.value(singular);
    if (forms.isEmpty()) {
        return count == 1 ? singular : plural;
    }

    // A catalog with fewer forms than the rule names: the last one is the closest.
    const int index = pluralIndex(m_rule, count);
    return forms.value(index, forms.constLast());
}

// %N always takes args[N-1], in one pass (QString::arg would fill the lowest
// marker present, and a plural form may lack %1).
QString I18nFallback::subst(const QString &text, const QVariantList &args)
{
    QString out;
    out.reserve(text.size());
    for (qsizetype i = 0; i < text.size(); ++i) {
        const QChar c = text.at(i);
        if (c == QLatin1Char('%') && i + 1 < text.size() && text.at(i + 1).isDigit()) {
            const int idx = text.at(i + 1).digitValue();
            if (idx >= 1 && idx <= args.size()) {
                out += args.at(idx - 1).toString();
                ++i;
                continue;
            }
        }
        out += c;
    }
    return out;
}

// "pt_BR" tries pt_BR, then pt; pt and zh fall back to the shipped variant.
bool I18nFallback::loadLanguage(const QString &language)
{
    const QString base = language.section(QLatin1Char('_'), 0, 0);
    QStringList candidates{language, base};
    if (base == QLatin1String("pt")) {
        candidates << QStringLiteral("pt_BR");
    }
    if (base == QLatin1String("zh")) {
        candidates << QStringLiteral("zh_CN");
    }

    for (const QString &c : std::as_const(candidates)) {
        QFile f(QStringLiteral(":/i18n/%1.json").arg(c));
        if (!f.open(QIODevice::ReadOnly)) {
            continue;
        }

        const QJsonObject obj = QJsonDocument::fromJson(f.readAll()).object();
        for (auto it = obj.constBegin(); it != obj.constEnd(); ++it) {
            if (it.key() == PLURAL_FORMS_KEY) {
                m_rule = it.value().toString();
                continue;
            }
            if (it.key().startsWith(PLURAL_PREFIX)) {
                QStringList forms;
                for (const QJsonValue &v : it.value().toArray()) {
                    forms << v.toString();
                }
                m_plurals.insert(it.key().mid(1), forms);
                continue;
            }
            m_catalog.insert(it.key(), it.value().toString());
        }
        return true;
    }
    return false;
}
