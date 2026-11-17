pragma Singleton
import QtQuick
import "../code/entryText.js" as EntryText
import "../code/notices.js" as Notices
import "../code/dateTimeFormat.js" as DTF
import "../code/timesheetFields.js" as TimesheetFields

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

    /** Why a save was refused (TimesheetFields.TimeProblem). */
    function timeProblem(problem) {
        switch (problem) {
        case TimesheetFields.TimeProblem.DATES:
            return i18n("Enter valid begin and end date/time.")
        case TimesheetFields.TimeProblem.ORDER:
            return i18n("End must be after begin.")
        case TimesheetFields.TimeProblem.BEGIN:
            return i18n("Enter a valid start date/time.")
        case TimesheetFields.TimeProblem.FUTURE:
            return i18n("Start must not be in the future.")
        }
        return ""
    }

    readonly property string splitRange: i18n("Split time must be between begin and end.")
    readonly property string splitSecond: i18n("The first half was saved, but the second half could not be created.")

    /** The title of a system notice (Notices.Kind). */
    function noticeTitle(kind) {
        switch (kind) {
        case Notices.Kind.Started:
            return i18n("Tracking started")
        case Notices.Kind.Switched:
            return i18n("Switched activity")
        case Notices.Kind.Stopped:
            return i18n("Tracking stopped")
        case Notices.Kind.IdleStopped:
            return i18n("Tracking stopped (idle)")
        case Notices.Kind.InProgress:
            return i18n("Tracking in progress")
        case Notices.Kind.IdleDiscarded:
            return i18n("Idle time discarded")
        case Notices.Kind.ForgotStart:
            return i18n("Nothing is tracking")
        }
        return ""
    }

    /** The text of a system notice; names: { project, activity, elapsedSeconds }. */
    function noticeBody(kind, names) {
        if (kind === Notices.Kind.ForgotStart) {
            return i18n("Work hours have started. Start a timer when you begin.")
        }
        const what = names.project + " · " + names.activity
        if (kind === Notices.Kind.InProgress) {
            return what + " · " + DTF.formatDurationShort(names.elapsedSeconds)
        }
        return what
    }
}
