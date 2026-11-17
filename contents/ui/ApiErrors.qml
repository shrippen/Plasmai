pragma Singleton
import QtQuick
import "../code/providerUtil.js" as ProviderUtil
import "../code/offlineState.js" as OfflineState

// The rule: a kind with a hint (token, URL, permissions, server error) shows the hint and the server's
// own text after it; any other kind shows the server's text; the app's own errors only the hint (`withServer`).
QtObject {
    /** The words for the offline layer's storage problem (OfflineState.StorageError); "" for none. */
    function storageText(storageError) {
        if (storageError === OfflineState.StorageError.SAVE) {
            return i18n("Waiting changes could not be saved on this device")
        }
        if (storageError === OfflineState.StorageError.LOAD) {
            return i18n("Waiting changes could not be read; new ones are kept in memory only")
        }
        if (storageError === OfflineState.StorageError.BROKEN) {
            return i18n("The saved list of waiting changes was damaged and set aside")
        }
        return ""
    }

    /**
     * @param error API / config error object
     * @param configContext when true, use connection-form wording for NotConfigured
     */
    function text(error, configContext) {
        if (!error) {
            return configContext ? i18n("Unknown error") : ""
        }
        if (error.type === ProviderUtil.ErrorType.NotConfigured) {
            return configContext
                ? i18n("URL and API token are required")
                : i18n("Configure your time tracker URL and API token")
        }
        if (error.type === ProviderUtil.ErrorType.InvalidInput) {
            return error.detail
                ? i18n("Missing or invalid input: %1", error.detail)
                : i18n("Missing or invalid input.")
        }
        if (error.type === ProviderUtil.ErrorType.Offline) {
            return i18n("This needs a connection to the server.")
        }
        if (error.type === ProviderUtil.ErrorType.Network) {
            return i18n("Cannot reach the server. Check your network, URL, or TLS certificate.")
        }
        if (error.type === ProviderUtil.ErrorType.Unauthorized) {
            return i18n("Authentication failed. Check your API token.")
        }
        if (error.type === ProviderUtil.ErrorType.NotFound) {
            return i18n("Server not found. Check your URL.")
        }
        if (error.type === ProviderUtil.ErrorType.Forbidden) {
            return i18n("Access denied. Your token may lack required permissions.")
        }
        if (error.type === ProviderUtil.ErrorType.Server) {
            return i18n("Server error (%1).", error.status)
        }
        const reason = error.detail || error.statusText
        if (reason) {
            return i18n("Request failed: %1", reason)
        }
        return i18n("Request failed (%1).", error.status)
    }

    /** The error as every place that shows a service's error words it; see the rule at the top. */
    function withServer(error, configContext) {
        const show = ProviderUtil.errorShow(error)
        if (show === ProviderUtil.ErrorShow.Hint) {
            return text(error, configContext)
        }
        const server = ProviderUtil.serverText(error)
        if (show === ProviderUtil.ErrorShow.Server) {
            return server
        }
        return i18n("%1 (%2)", text(error, configContext), server)
    }

    /** The line under "Test connection": `result` as the session's test hands it, `service` the service's name. */
    function testText(result, service) {
        if (!result.ok) {
            return withServer(result.error, true)
        }
        const data = result.data
        const version = (data && (data.version || data.name)) || i18n("ok")
        return i18n("Connected to %1 (%2).", service, version)
    }

    // -- Waiting changes (offline layer) ---------------------------------------------

    /** What a waiting change is. */
    function opKindText(op) {
        if (op.kind === OfflineState.Op.CREATE) {
            return op.fields.end ? i18n("New entry") : i18n("Timer started")
        }
        if (op.kind === OfflineState.Op.PATCH) {
            const keys = Object.keys(op.fields || {})
            return keys.length === 1 && keys[0] === "end" ? i18n("Timer stopped") : i18n("Entry changed")
        }
        if (op.kind === OfflineState.Op.DELETE) {
            return i18n("Entry deleted")
        }
        if (op.kind === OfflineState.Op.TRIP_CREATE) {
            return i18n("Trip added")
        }
        if (op.kind === OfflineState.Op.TRIP_PATCH) {
            return i18n("Trip changed")
        }
        if (op.kind === OfflineState.Op.TRIP_DELETE) {
            return i18n("Trip deleted")
        }
        if (op.kind === OfflineState.Op.FILM_DAY) {
            return i18n("Film day details of %1",
                        new Date(op.dateStr + "T12:00:00").toLocaleDateString(Qt.locale(), Locale.ShortFormat))
        }
        return op.kind
    }

    /** The fields a conflict names, in the words of the forms. */
    function fieldNames(detail) {
        const names = { begin: i18n("Begin"), end: i18n("End"), description: i18n("Description"),
                        project: i18n("Project"), activity: i18n("Activity") }
        return String(detail || "").split(", ").map(function(k) { return names[k] || k }).join(", ")
    }

    /** Why a waiting change waits: the connection, a refusal, a change on the server. */
    function opStateText(op) {
        if (op.state === OfflineState.State.FAILED) {
            return i18n("Not accepted: %1", withServer(op.error))
        }
        if (op.state === OfflineState.State.CONFLICT) {
            return i18n("Changed on the server meanwhile (%1). Overwrite it with this change, or discard this change?",
                        fieldNames(op.error ? op.error.detail : ""))
        }
        return i18n("Waiting for the connection")
    }

    /** The status line's words for changes parked for another server or account. */
    function heldStatusText(count) {
        return i18np("%1 change waits for another server or account", "%1 changes wait for another server or account", count)
    }

    /** A parked group (Offline.groups): "2 changes wait for Ann on https://kimai.test". */
    function heldGroupText(group) {
        return i18np("%1 change waits for %2 on %3", "%1 changes wait for %2 on %3", group.count, group.name, group.server)
    }

    /** What to do with a group that cannot be sent here ("" for one that can). */
    function heldHint(group) {
        return group.canAdopt ? "" : i18n("Sign in as %1 to send them.", group.name)
    }

    /** The question before a group is sent to the address in use; it names both addresses. */
    function adoptQuestion(group) {
        return i18n("Send these changes to %1 instead of %2? Each entry is checked on the server first.", group.to, group.server)
    }

    function discardGroupQuestion(group) {
        return i18np("Discard %1 change for %2?", "Discard %1 changes for %2?", group.count, group.name)
    }
}
