#include <QTest>

#include "i18nfallback.h"

// Plural rules and catalogs of I18nFallback (the app's translations on every platform).
class TstI18nFallback : public QObject {
    Q_OBJECT

private slots:
    void pluralIndex_data()
    {
        QTest::addColumn<QString>("lang");
        QTest::addColumn<qlonglong>("n");
        QTest::addColumn<int>("index");

        // ru / uk: one (1, 21, 101), few (2–4, 22–24), many (0, 5–20, 11–14, 25)
        const QList<QPair<qlonglong, int>> ru{{1, 0}, {21, 0}, {101, 0}, {2, 1}, {4, 1}, {22, 1},
                                              {0, 2}, {5, 2}, {11, 2}, {12, 2}, {14, 2}, {25, 2}, {111, 2}};
        for (const auto &c : ru) {
            QTest::addRow("ru %lld", c.first) << QStringLiteral("ru") << c.first << c.second;
        }
        // pl: one only for 1 (21 is "many", unlike ru)
        const QList<QPair<qlonglong, int>> pl{{1, 0}, {2, 1}, {22, 1}, {0, 2}, {5, 2}, {12, 2}, {21, 2}};
        for (const auto &c : pl) {
            QTest::addRow("pl %lld", c.first) << QStringLiteral("pl") << c.first << c.second;
        }
        // fr: 0 and 1 singular; de: only 1; ja: one form
        QTest::addRow("fr 0") << QStringLiteral("fr") << 0LL << 0;
        QTest::addRow("fr 1") << QStringLiteral("fr") << 1LL << 0;
        QTest::addRow("fr 2") << QStringLiteral("fr") << 2LL << 1;
        QTest::addRow("de 0") << QStringLiteral("de") << 0LL << 1;
        QTest::addRow("de 1") << QStringLiteral("de") << 1LL << 0;
        QTest::addRow("ja 5") << QStringLiteral("ja") << 5LL << 0;
    }

    void pluralIndex()
    {
        QFETCH(QString, lang);
        QFETCH(qlonglong, n);
        QFETCH(int, index);

        const QHash<QString, QString> rules{
            {QStringLiteral("ru"), QStringLiteral("(n%10==1&&n%100!=11?0:n%10>=2&&n%10<=4&&(n%100<10||n%100>=20)?1:2)")},
            {QStringLiteral("pl"), QStringLiteral("(n==1?0:n%10>=2&&n%10<=4&&(n%100<10||n%100>=20)?1:2)")},
            {QStringLiteral("fr"), QStringLiteral("(n>1)")},
            {QStringLiteral("de"), QStringLiteral("(n!=1)")},
            {QStringLiteral("ja"), QStringLiteral("0")},
        };
        QCOMPARE(I18nFallback::pluralIndex(rules.value(lang), n), index);
    }

    // The shipped catalogs: the language's own form, not the English two.
    void catalogPlurals()
    {
        const I18nFallback ru(QStringLiteral("ru"));
        QCOMPARE(ru.i18np(QStringLiteral("%1 minute"), QStringLiteral("%1 minutes"), 1), QStringLiteral("1 минута"));
        QCOMPARE(ru.i18np(QStringLiteral("%1 minute"), QStringLiteral("%1 minutes"), 3), QStringLiteral("3 минуты"));
        QCOMPARE(ru.i18np(QStringLiteral("%1 minute"), QStringLiteral("%1 minutes"), 5), QStringLiteral("5 минут"));
        QCOMPARE(ru.i18np(QStringLiteral("%1 minute"), QStringLiteral("%1 minutes"), 11), QStringLiteral("11 минут"));

        const I18nFallback ja(QStringLiteral("ja"));
        QCOMPARE(ja.i18np(QStringLiteral("%1 minute"), QStringLiteral("%1 minutes"), 5), QStringLiteral("5 分"));

        const I18nFallback de(QStringLiteral("de"));
        QCOMPARE(de.i18np(QStringLiteral("%1 minute"), QStringLiteral("%1 minutes"), 60), QStringLiteral("60 Minuten"));
        QCOMPARE(de.i18n(QStringLiteral("Film day")), QStringLiteral("Drehtag"));
    }

    // No catalog (English, unknown language): the source strings, English plural rule.
    void englishFallback()
    {
        const I18nFallback none(QStringLiteral("xx"));
        QCOMPARE(none.i18np(QStringLiteral("%1 minute"), QStringLiteral("%1 minutes"), 1), QStringLiteral("1 minute"));
        QCOMPARE(none.i18np(QStringLiteral("%1 minute"), QStringLiteral("%1 minutes"), 2), QStringLiteral("2 minutes"));
        QCOMPARE(none.i18n(QStringLiteral("%2 of %1"), 10, 3), QStringLiteral("3 of 10"));
    }
};

QTEST_GUILESS_MAIN(TstI18nFallback)
#include "tst_i18nfallback.moc"
