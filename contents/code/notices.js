.pragma library

/**
 * When the session tells the user something (a system notice), and what kind of notice.
 * The words are in EntryTexts.qml; widget and app only show them.
 */

var Kind = { Started: "started", Switched: "switched", Stopped: "stopped", IdleStopped: "idleStopped",
             InProgress: "inProgress", IdleDiscarded: "idleDiscarded", ForgotStart: "forgotStart" }

/** What began: a fresh start (or a continued entry), or a switch from a running one. */
var Begin = { Start: "start", Switch: "switch" }

/** Why the timer stopped. */
var Cause = { Manual: "manual", Idle: "idle" }

/** Where a running timer came from: a start of this client, or one a refresh found. */
var Found = { Own: "own", Elsewhere: "elsewhere" }

/** A start or switch of this client; null: the settings say nothing. */
function forStart(begin, settings) {
    if (!settings.notifyOnStart) {
        return null
    }
    return begin === Begin.Switch ? Kind.Switched : Kind.Started
}

/** A stop of this client. */
function forStop(cause, settings) {
    if (cause === Cause.Idle) {
        return settings.notifyOnIdleStop ? Kind.IdleStopped : null
    }
    return settings.notifyOnStop ? Kind.Stopped : null
}

/** A running timer after a refresh; one of this client's own start was told already. */
function forFound(found, settings) {
    if (found === Found.Own || !settings.notifyOnStart) {
        return null
    }
    return Kind.InProgress
}

/** Idle time was cut from the running entry. */
function forIdleDiscard(settings) {
    return settings.notifyOnIdleStop ? Kind.IdleDiscarded : null
}
