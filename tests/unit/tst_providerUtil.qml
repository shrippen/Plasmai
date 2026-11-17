import QtQuick
import QtTest
import "../../contents/code/providerUtil.js" as Util

TestCase {
    name: "ProviderUtil"

    function test_normalizeUrl() {
        compare(Util.normalizeUrl("https://a.example/"), "https://a.example")
        compare(Util.normalizeUrl(""), "")
    }

    function test_parseJson() {
        compare(Util.parseJson('{"a":1}', {}).a, 1)
        compare(Util.parseJson("not-json", 7), 7)
    }

    function test_parseApiError() {
        compare(Util.parseApiError(0, "x", "").type, Util.ErrorType.Network)
        compare(Util.parseApiError(401, "x", "").type, Util.ErrorType.Unauthorized)
        compare(Util.parseApiError(403, "x", "").type, Util.ErrorType.Forbidden)
        compare(Util.parseApiError(404, "x", "").type, Util.ErrorType.NotFound)
        compare(Util.parseApiError(502, "x", "").type, Util.ErrorType.Server)
        var err = Util.parseApiError(400, "Bad", '{"message":"nope"}')
        compare(err.type, Util.ErrorType.Unknown)
        compare(err.detail, "nope")
    }

    function test_parseIsoDuration() {
        compare(Util.parseIsoDurationToSeconds("PT1H2M3S"), 3723)
        compare(Util.parseIsoDurationToSeconds("P1DT2H"), 93600)
        compare(Util.parseIsoDurationToSeconds("90"), 90)
        compare(Util.parseIsoDurationToSeconds(""), 0)
    }

    function test_okFail() {
        verify(Util.ok(1).ok)
        verify(!Util.fail({ type: "x" }).ok)
    }

    function test_serverText() {
        compare(Util.serverText({ type: Util.ErrorType.Server, detail: "Disk full" }), "Disk full")
        compare(Util.serverText({ type: Util.ErrorType.Unauthorized }), "")
        compare(Util.serverText(null), "")
        // The app's own errors carry no server text, even with a detail.
        compare(Util.serverText({ type: Util.ErrorType.NotConfigured, detail: "no url" }), "")
        compare(Util.serverText({ type: Util.ErrorType.InvalidInput, detail: "projectId" }), "")
        compare(Util.serverText({ type: Util.ErrorType.Offline, detail: "x" }), "")
        compare(Util.serverText({ type: Util.ErrorType.Network, detail: "x" }), "")
    }

    function show(status, statusText, body) {
        return Util.errorShow(Util.parseApiError(status, statusText, body))
    }

    function test_parseApiErrorKeepsStatusTextApart() {
        const err = Util.parseApiError(429, "Too Many Requests", "")
        compare(err.detail, "")
        compare(err.statusText, "Too Many Requests")
    }

    function test_errorShow() {
        const S = Util.ErrorShow
        // SolidTime (Laravel) 401 and 5xx: the hint with the server's words.
        compare(show(401, "Unauthorized", '{"message":"Unauthenticated."}'), S.Both)
        compare(show(500, "Internal Server Error", '{"message":"Server Error"}'), S.Both)
        // Kimai 403 and 404.
        compare(show(403, "Forbidden", '{"code":403,"message":"Access denied."}'), S.Both)
        compare(show(404, "Not Found", '{"code":404,"message":"Not Found"}'), S.Both)
        // No text of its own: the hint alone.
        compare(show(401, "Unauthorized", ""), S.Hint)
        compare(show(503, "Service Unavailable", "<html>"), S.Hint)
        compare(show(429, "Too Many Requests", ""), S.Hint)
        // A plugin's text on a 400 is the useful part.
        compare(show(400, "Bad Request", '{"message":"This month of the logbook is closed."}'), S.Server)
        compare(Util.errorShow({ type: Util.ErrorType.Conflict, status: 409, detail: "begin" }), S.Server)
        // The app's own errors and no error: the hint.
        compare(Util.errorShow({ type: Util.ErrorType.InvalidInput, detail: "projectId" }), S.Hint)
        compare(Util.errorShow({ type: Util.ErrorType.Offline, detail: "x" }), S.Hint)
        compare(Util.errorShow({ type: Util.ErrorType.NotConfigured, detail: "x" }), S.Hint)
        compare(Util.errorShow(null), S.Hint)
    }
}
