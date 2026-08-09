pragma Singleton
import QtQuick
import "../code/kimaiApi.js" as KimaiApi

QtObject {
    /**
     * @param error Kimai API / config error object
     * @param configContext when true, use connection-form wording for config errors
     */
    function text(error, configContext) {
        if (!error) {
            return configContext ? i18n("Unknown error") : ""
        }
        if (error.type === "config") {
            return configContext
                ? i18n("URL and API token are required")
                : i18n("Configure Kimai URL and API token")
        }
        if (error.type === KimaiApi.ErrorType.Network) {
            return i18n("Cannot reach Kimai. Check your network, URL, or TLS certificate.")
        }
        if (error.type === KimaiApi.ErrorType.Unauthorized) {
            return i18n("Authentication failed. Check your API token.")
        }
        if (error.type === KimaiApi.ErrorType.NotFound) {
            return i18n("Server not found. Check your Kimai URL.")
        }
        if (error.type === KimaiApi.ErrorType.Forbidden) {
            return i18n("Access denied. Your token may lack required permissions.")
        }
        if (error.type === KimaiApi.ErrorType.Server) {
            return i18n("Kimai server error (%1).", error.status)
        }
        if (error.detail) {
            return i18n("Request failed: %1", error.detail)
        }
        return i18n("Request failed (%1).", error.status)
    }
}
