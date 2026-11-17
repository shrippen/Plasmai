.pragma library

/**
 * When the session tells the user something (a system notice), and what kind of notice.
 * The words are in EntryTexts.qml; widget and app only show them.
 */

var Kind = { Started: "started", Switched: "switched", Stopped: "stopped", IdleStopped: "idleStopped",
             InProgress: "inProgress", IdleDiscarded: "idleDiscarded", ForgotStart: "forgotStart" }

/** The start's origin, as Session.Origin names it (the QML enum is not visible here). */
var Origin = { Start: 0, Switch: 1, Continue: 2 }

/** A start or switch of this client; null: the settings say nothing. */
function forStart(origin, settings) {
    if (!settings.notifyOnStart) {
        return null
    }
    return origin === Origin.Switch ? Kind.Switched : Kind.Started
}

/** A stop of this client; idle: the idle stop made it. */
function forStop(idle, settings) {
    if (idle) {
        return settings.notifyOnIdleStop ? Kind.IdleStopped : null
    }
    return settings.notifyOnStop ? Kind.Stopped : null
}

/** A running timer the refresh found; local: a start of this client, told already. */
function forFound(local, settings) {
    if (local || !settings.notifyOnStart) {
        return null
    }
    return Kind.InProgress
}

/** Idle time was cut from the running entry. */
function forIdleDiscard(settings) {
    return settings.notifyOnIdleStop ? Kind.IdleDiscarded : null
}
