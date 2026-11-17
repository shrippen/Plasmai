pragma Singleton
import QtQuick
import "../code/providerUtil.js" as ProviderUtil
import "../code/offlineState.js" as OfflineState

// The rule: where a server answered, show its own text (`withServer`); the translated kind
// (`text`) is the fallback, and the only text for errors without a server (setup, offline, network).
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
        if (error.detail) {
            return i18n("Request failed: %1", error.detail)
        }
        return i18n("Request failed (%1).", error.status)
    }

    /** The server's text if it sent one, else `text`. Every place that shows a service's error uses this. */
    function withServer(error, configContext) {
        return ProviderUtil.serverText(error) || text(error, configContext)
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
}
