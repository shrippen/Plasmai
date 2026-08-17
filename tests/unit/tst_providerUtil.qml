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
}
