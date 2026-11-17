pragma Singleton
import QtQuick
import "../code/providerUtil.js" as ProviderUtil

QtObject {
    /**
     * @param error API / config error object
     * @param configContext when true, use connection-form wording for config errors
     */
    function text(error, configContext) {
        if (!error) {
            return configContext ? i18n("Unknown error") : ""
        }
        if (error.type === "config") {
            return configContext
                ? i18n("URL and API token are required")
                : i18n("Configure your time tracker URL and API token")
        }
        if (error.type === "offline") {
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
}
