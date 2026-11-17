import QtQuick
import QtTest
import "../../contents/code/kimaiApi.js" as KimaiApi
import "../../contents/code/providerUtil.js" as ProviderUtil

TestCase {
    name: "KimaiApi"

    function test_normalizeUrl() {
        compare(ProviderUtil.normalizeUrl("https://ki.example.com/"), "https://ki.example.com")
        compare(ProviderUtil.normalizeUrl("https://ki.example.com///"), "https://ki.example.com")
        compare(ProviderUtil.normalizeUrl(""), "")
    }

    function test_customerCreateDefaults() {
        var d = KimaiApi.customerCreateDefaults([])
        compare(d.currency, "EUR")
        var fromList = KimaiApi.customerCreateDefaults([
            { country: "AT", currency: "EUR", timezone: "Europe/Vienna" }
        ])
        compare(fromList.timezone, "Europe/Vienna")
        compare(fromList.country, "AT")
    }

    function test_serializeTimesheetWrite_tagsAreString() {
        var data = KimaiApi.serializeTimesheetWrite({
            begin: "2026-08-17T23:15:00",
            project: "4",
            activity: { id: 35 },
            billable: false,
            tags: ["ops", "night"]
        })
        compare(data.tags, "ops, night")
        compare(data.billable, false)
        compare(data.project, 4)
        compare(data.activity, 35)
        compare(KimaiApi.serializeTimesheetWrite({ tags: [] }).tags, "")
        compare(KimaiApi.serializeTimesheetWrite({ description: "hello" }).description, "hello")
        verify(!("billable" in KimaiApi.serializeTimesheetWrite({ description: "hello" })))
    }

    function test_parseApiError_flattensForm() {
        var payload = JSON.stringify({
            code: 400,
            message: "Validation Failed",
            errors: {
                errors: ["This form should not contain extra fields."],
                children: {
                    tags: { errors: ["This value should be of type string."] }
                }
            }
        })
        var err = KimaiApi.parseApiError(400, "Bad Request", payload)
        verify(err.detail.indexOf("extra fields") >= 0)
        verify(err.detail.indexOf("tags") >= 0)
        verify(KimaiApi.isFormErrorBody(JSON.parse(payload)))
        verify(!KimaiApi.isFormErrorBody({ id: 12, billable: true }))
    }

    function test_tagsFindEndpoint() {
        compare(KimaiApi.tagsFindEndpoint(""), "/api/tags/find?name=")
        compare(KimaiApi.tagsFindEndpoint("ops"), "/api/tags/find?name=ops")
        compare(KimaiApi.tagsFindEndpoint("a b"), "/api/tags/find?name=a%20b")
    }
}
