pragma Singleton
import QtQuick
import "../code/entryText.js" as EntryText
import "../code/dateTimeFormat.js" as DTF

/** Texts about entries and the day that widget and app both show; the logic is in entryText.js. */
QtObject {
    /** "5 minutes ago", "yesterday", or the date after a week; "" without a valid stamp. */
    function ago(isoDate) {
        const a = EntryText.age(isoDate, Date.now())
        switch (a.kind) {
        case EntryText.Age.Now:
            return i18n("just now")
        case EntryText.Age.Minutes:
            return i18np("%1 minute ago", "%1 minutes ago", a.n)
        case EntryText.Age.Hours:
            return i18np("%1 hour ago", "%1 hours ago", a.n)
        case EntryText.Age.Yesterday:
            return i18n("yesterday")
        case EntryText.Age.Days:
            return i18np("%1 day ago", "%1 days ago", a.n)
        case EntryText.Age.Date:
            return DTF.parseStamp(isoDate).toLocaleDateString(Qt.locale())
        }
        return ""
    }

    /** "Project · Activity · date time" of an entry, for a link or a row. */
    function summary(ts, catalog) {
        return EntryText.summary(ts, catalog)
    }

    /** Time left today, or over it (seconds < 0). */
    function leftToday(seconds) {
        if (seconds >= 0) {
            return i18n("%1 left today", DTF.formatDurationShort(seconds))
        }
        return i18n("%1 over today", DTF.formatDurationShort(-seconds))
    }

    function leftWeek(seconds) {
        if (seconds >= 0) {
            return i18n("%1 left this week", DTF.formatDurationShort(seconds))
        }
        return i18n("%1 over this week", DTF.formatDurationShort(-seconds))
    }

    readonly property string splitRange: i18n("Split time must be between begin and end.")
    readonly property string splitSecond: i18n("The first half was saved, but the second half could not be created.")
}
