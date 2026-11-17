import QtQuick
import QtTest
import "../../contents/code/providerUtil.js" as Util
import "../../contents/code/providers/clockify.js" as Clockify
import "../../contents/code/providers/toggl.js" as Toggl
import "../../contents/code/providers/solidtime.js" as SolidTime

/**
 * Request frame of Clockify, Toggl and SolidTime against a fake XMLHttpRequest:
 * no token, success, empty answer, 401/403/404/5xx, network error, and the
 * workspace/user context that is resolved once and reused. Differences between
 * the services are pinned as they are.
 * A queued response is { status, body } (body JSON-encoded), { status, text }
 * (raw text) or { netError: true }.
 */
TestCase {
    name: "ProviderRequests"

    property var requests: []
    property var responses: []
    readonly property string customerColor: "#d2d6de"

    function fakeXhr() {
        var xhr = {
            readyState: 0,
            status: 0,
            statusText: "",
            responseText: "",
            method: "",
            url: "",
            body: undefined,
            headers: {},
            onreadystatechange: null,
            onerror: null,
            open: function(method, url) {
                xhr.method = method
                xhr.url = url
            },
            setRequestHeader: function(name, value) {
                xhr.headers[name] = value
            },
            abort: function() {},
            send: function(body) {
                xhr.body = body
                requests.push(xhr)
                var next = responses.shift()
                if (!next) {
                    return
                }
                if (next.netError) {
                    xhr.onerror()
                    return
                }
                xhr.status = next.status
                xhr.responseText = next.text !== undefined ? next.text
                    : (next.body === undefined ? "" : JSON.stringify(next.body))
                xhr.readyState = 4
                xhr.onreadystatechange()
            }
        }
        return xhr
    }

    // Per service: how to reset, what the context calls and answers look like.
    function services() {
        return [
            {
                name: "clockify",
                mod: Clockify,
                url: "https://clockify.example/api/v1/",
                base: "https://clockify.example/api/v1",
                defaultBase: "https://api.clockify.me/api/v1",
                needsUrl: false,
                notFoundIsError: true,
                unwrapsData: false,
                emptyDetail: "Workspace or user not resolved",
                reset: function() { Clockify.setSession({ workspaceId: "", userId: "" }) },
                preset: function() { Clockify.setSession({ workspaceId: "w1", userId: "u1" }) },
                contextCalls: ["GET /user", "GET /workspaces"],
                contextAnswers: [
                    { status: 200, body: { id: "u1", activeWorkspace: "w1" } },
                    { status: 200, body: [{ id: "w1", name: "W" }] }
                ],
                unresolvedAnswers: [
                    { status: 200, body: { id: "u1" } },
                    { status: 200, body: [] }
                ],
                header: function(h, token) { compare(h["X-Api-Key"], token) },
                customersPath: "/workspaces/w1/clients",
                customersContext: true,
                deletePath: "/workspaces/w1/time-entries/5"
            },
            {
                name: "toggl",
                mod: Toggl,
                url: "https://toggl.example/api/v9/",
                base: "https://toggl.example/api/v9",
                defaultBase: "https://api.track.toggl.com/api/v9",
                needsUrl: false,
                notFoundIsError: false,
                unwrapsData: false,
                emptyDetail: "Workspace or user not resolved",
                reset: function() { Toggl.setSession({ workspaceId: 0, userId: 0 }) },
                preset: function() { Toggl.setSession({ workspaceId: 9, userId: 7 }) },
                contextCalls: ["GET /me"],
                contextAnswers: [
                    { status: 200, body: { id: 7, default_workspace_id: 9 } }
                ],
                unresolvedAnswers: [
                    { status: 200, body: { id: 7 } }
                ],
                header: function(h, token) { compare(h["Authorization"], Util.basicAuthHeader(token, "api_token")) },
                customersPath: "/me/clients",
                customersContext: false,
                deletePath: "/workspaces/9/time_entries/5"
            },
            {
                name: "solidtime",
                mod: SolidTime,
                url: "https://st.example/",
                base: "https://st.example/api/v1",
                defaultBase: "",
                needsUrl: true,
                notFoundIsError: false,
                unwrapsData: true,
                emptyDetail: "Organization or member not resolved",
                reset: function() { SolidTime.setSession({ organizationId: "", memberId: "" }) },
                preset: function() { SolidTime.setSession({ organizationId: "o1", memberId: "m1" }) },
                contextCalls: ["GET /users/me/memberships"],
                contextAnswers: [
                    { status: 200, body: { data: [{ id: "m1", organization: { id: "o1" } }] } }
                ],
                unresolvedAnswers: [
                    { status: 200, body: { data: [] } }
                ],
                header: function(h, token) { compare(h["Authorization"], "Bearer " + token) },
                customersPath: "/organizations/o1/clients?archived=false",
                customersContext: true,
                deletePath: "/organizations/o1/time-entries/5"
            }
        ]
    }

    function init() {
        requests = []
        responses = []
        Util.setRequestFactory(fakeXhr)
    }

    function cleanup() {
        Util.setRequestFactory(null)
    }

    // Fake answers synchronously, so the callback has run when the call returns.
    function call(svc, fn, args) {
        var out = { result: null, calls: 0 }
        args.push(function(result) {
            out.result = result
            out.calls++
        })
        svc.mod[fn].apply(null, args)
        compare(out.calls, 1, svc.name + " " + fn + " answers once")
        return out.result
    }

    function load(svc, token) {
        return call(svc, "loadCustomers", [svc.url, token === undefined ? "tok" : token])
    }

    function del(svc, token) {
        return call(svc, "deleteTimesheet", [svc.url, token === undefined ? "tok" : token, 5])
    }

    function pathOf(req, svc) {
        return req.method + " " + req.url.substring(svc.base.length)
    }

    function paths(svc) {
        return requests.map(function(r) { return pathOf(r, svc) })
    }

    function test_noToken() {
        var all = services()
        for (var i = 0; i < all.length; i++) {
            var svc = all[i]
            svc.reset()
            for (var t = 0; t < 2; t++) {
                var token = t === 0 ? "" : undefined
                var r = call(svc, "loadCustomers", [svc.url, token])
                verify(!r.ok, svc.name)
                compare(r.error.type, "config", svc.name)
                compare(r.error.status, 0)
                compare(r.error.detail, "")
            }
            compare(requests.length, 0, svc.name + ": nothing sent without token")

            r = call(svc, "testConnection", [svc.url, ""])
            compare(r.error.type, "config", svc.name)
            r = call(svc, "deleteTimesheet", [svc.url, "", 5])
            compare(r.error.type, "config", svc.name)
            compare(requests.length, 0, svc.name)
        }
    }

    function test_urlRequiredOnlyBySolidTime() {
        var all = services()
        for (var i = 0; i < all.length; i++) {
            var svc = all[i]
            svc.preset()
            requests = []
            responses = [{ status: 200, body: [] }]
            var r = call(svc, "loadCustomers", ["", "tok"])
            if (svc.needsUrl) {
                verify(!r.ok, svc.name)
                compare(r.error.type, "config", svc.name)
                compare(requests.length, 0, svc.name)
                continue
            }
            verify(r.ok, svc.name)
            compare(requests.length, 1, svc.name)
            verify(requests[0].url.indexOf(svc.defaultBase) === 0, svc.name + ": default base " + requests[0].url)
        }
    }

    function test_urlHandling() {
        var all = services()
        for (var i = 0; i < all.length; i++) {
            var svc = all[i]
            svc.preset()
            requests = []
            responses = [{ status: 200, body: [] }]
            load(svc)
            compare(requests[0].url, svc.base + svc.customersPath, svc.name + ": trailing slash dropped")
        }
        // SolidTime appends /api/v1 only when the address does not end in it.
        SolidTime.setSession({ organizationId: "o1", memberId: "m1" })
        requests = []
        responses = [{ status: 200, body: [] }]
        SolidTime.loadCustomers("https://st.example/api/v1", "tok", function() {})
        compare(requests[0].url, "https://st.example/api/v1/organizations/o1/clients?archived=false")
    }

    function test_headers() {
        var all = services()
        for (var i = 0; i < all.length; i++) {
            var svc = all[i]
            svc.preset()
            requests = []
            responses = [{ status: 200, body: [] }]
            load(svc, "secret")
            svc.header(requests[0].headers, "secret")
            compare(requests[0].headers["Accept"], "application/json", svc.name)
            compare(requests[0].headers["Content-Type"], undefined, svc.name + ": no body type on GET")
        }
    }

    function test_postSendsJson() {
        var all = services()
        for (var i = 0; i < all.length; i++) {
            var svc = all[i]
            svc.preset()
            requests = []
            responses = [{ status: 200, body: { id: "c1", name: "Acme" } }]
            var r = call(svc, "createCustomer", [svc.url, "tok", { name: "Acme" }])
            verify(r.ok, svc.name)
            compare(requests.length, 1, svc.name)
            compare(requests[0].method, "POST", svc.name)
            compare(requests[0].headers["Content-Type"], "application/json", svc.name)
            compare(JSON.parse(requests[0].body).name, "Acme", svc.name)
        }
    }

    function test_deleteSendsEmptyBody() {
        var all = services()
        for (var i = 0; i < all.length; i++) {
            var svc = all[i]
            svc.preset()
            requests = []
            responses = [{ status: 204, text: "" }]
            var r = del(svc)
            verify(r.ok, svc.name)
            compare(r.data, null, svc.name + ": empty answer reads as null")
            compare(requests[0].method, "DELETE", svc.name)
            compare(requests[0].url, svc.base + svc.deletePath, svc.name)
            compare(requests[0].body, "", svc.name)
            compare(requests[0].headers["Content-Type"], undefined, svc.name)
        }
    }

    function test_successRows() {
        var all = services()
        for (var i = 0; i < all.length; i++) {
            var svc = all[i]
            svc.preset()
            var list = [{ id: "c1", name: "Acme" }, { id: "c2" }]
            responses = [{ status: 200, body: svc.unwrapsData ? { data: list } : list }]
            var r = load(svc)
            verify(r.ok, svc.name)
            compare(r.data.length, 2, svc.name)
            compare(r.data[0].id, "c1", svc.name)
            compare(r.data[0].name, "Acme", svc.name)
            compare(r.data[0].color, customerColor, svc.name)
            compare(r.data[1].name, "", svc.name)
        }
    }

    function test_solidTimeAcceptsBodyWithoutDataKey() {
        SolidTime.setSession({ organizationId: "o1", memberId: "m1" })
        responses = [{ status: 200, body: [{ id: "c1", name: "A" }] }]
        var r = call({ name: "solidtime", mod: SolidTime }, "loadCustomers", ["https://st.example", "tok"])
        compare(r.data.length, 1)
    }

    function test_clockifyAndTogglDoNotUnwrapData() {
        // A { data: [...] } body is not a list for them: no rows, no error.
        var others = [services()[0], services()[1]]
        for (var i = 0; i < others.length; i++) {
            var svc = others[i]
            svc.preset()
            responses = [{ status: 200, body: { data: [{ id: "c1" }] } }]
            var r = load(svc)
            verify(r.ok, svc.name)
            compare(r.data.length, 0, svc.name)
        }
    }

    function test_emptyAnswerBecomesFallback() {
        var all = services()
        var answers = [
            { status: 200, text: "" },
            { status: 200, text: "null" },
            { status: 200, text: "not json" },
            { status: 204, text: "" }
        ]
        for (var i = 0; i < all.length; i++) {
            for (var a = 0; a < answers.length; a++) {
                var svc = all[i]
                svc.preset()
                responses = [answers[a]]
                var r = load(svc)
                verify(r.ok, svc.name + " " + a)
                compare(r.data.length, 0, svc.name + " " + a)
            }
        }
    }

    function test_activeWithoutEntry() {
        // Toggl and SolidTime answer "nothing running" with an empty body or 404.
        Toggl.setSession({ workspaceId: 9, userId: 7 })
        SolidTime.setSession({ organizationId: "o1", memberId: "m1" })
        var cases = [
            { mod: Toggl, answer: { status: 200, text: "null" } },
            { mod: Toggl, answer: { status: 404, text: "" } },
            { mod: SolidTime, answer: { status: 404, text: "" } }
        ]
        for (var i = 0; i < cases.length; i++) {
            responses = [cases[i].answer]
            var out = null
            cases[i].mod.fetchActiveTimesheet("https://st.example", "tok", function(r) { out = r })
            verify(out.ok, "case " + i)
            compare(out.data.length, 0, "case " + i)
        }
    }

    function test_solidTimeActiveWithNullDataIsNothing() {
        // { data: null } means nothing is running, not an entry without id.
        SolidTime.setSession({ organizationId: "o1", memberId: "m1" })
        responses = [{ status: 200, body: { data: null } }]
        var out = null
        SolidTime.fetchActiveTimesheet("https://st.example", "tok", function(r) { out = r })
        verify(out.ok)
        compare(out.data.length, 0)
    }

    function test_errorStatuses() {
        var all = services()
        var cases = [
            { status: 401, type: Util.ErrorType.Unauthorized },
            { status: 403, type: Util.ErrorType.Forbidden },
            { status: 500, type: Util.ErrorType.Server },
            { status: 503, type: Util.ErrorType.Server },
            { status: 422, type: Util.ErrorType.Unknown }
        ]
        for (var i = 0; i < all.length; i++) {
            for (var c = 0; c < cases.length; c++) {
                var svc = all[i]
                svc.preset()
                responses = [{ status: cases[c].status, body: { message: "boom" } }]
                var r = load(svc)
                var label = svc.name + " " + cases[c].status
                verify(!r.ok, label)
                compare(r.error.type, cases[c].type, label)
                compare(r.error.status, cases[c].status, label)
                compare(r.error.detail, "boom", label)
            }
        }
    }

    function test_notFound() {
        var all = services()
        for (var i = 0; i < all.length; i++) {
            var svc = all[i]
            svc.preset()
            responses = [{ status: 404, body: { message: "gone" } }]
            var r = load(svc)
            if (svc.notFoundIsError) {
                // Clockify reports 404 as an error ...
                verify(!r.ok, svc.name)
                compare(r.error.type, Util.ErrorType.NotFound, svc.name)
                compare(r.error.detail, "gone", svc.name)
            } else {
                // ... Toggl and SolidTime read it as an empty answer.
                verify(r.ok, svc.name)
                compare(r.data.length, 0, svc.name)
            }

            responses = [{ status: 404, text: "" }]
            r = del(svc)
            if (svc.notFoundIsError) {
                verify(!r.ok, svc.name + " delete")
                compare(r.error.type, Util.ErrorType.NotFound, svc.name)
                continue
            }
            verify(r.ok, svc.name + " delete")
            compare(r.data, null, svc.name + " delete")
        }
    }

    function test_unknownErrorFallsBackToStatusText() {
        var all = services()
        for (var i = 0; i < all.length; i++) {
            var svc = all[i]
            svc.preset()
            responses = [{ status: 400, text: "plain" }]
            var r = load(svc)
            compare(r.error.type, Util.ErrorType.Unknown, svc.name)
            compare(r.error.status, 400, svc.name)
        }
    }

    function test_networkError() {
        var all = services()
        for (var i = 0; i < all.length; i++) {
            var svc = all[i]
            svc.preset()
            responses = [{ netError: true }]
            var r = load(svc)
            verify(!r.ok, svc.name)
            compare(r.error.type, Util.ErrorType.Network, svc.name)
            compare(r.error.status, 0, svc.name)

            responses = [{ status: 0, text: "" }]
            r = load(svc)
            compare(r.error.type, Util.ErrorType.Network, svc.name + " status 0")
        }
        compare(Util.pendingRequestCount(), 0)
    }

    function test_contextResolvedOnceAndReused() {
        var all = services()
        for (var i = 0; i < all.length; i++) {
            var svc = all[i]
            svc.reset()
            requests = []
            responses = svc.contextAnswers.concat([{ status: 204, text: "" }, { status: 204, text: "" }])
            var r = del(svc)
            verify(r.ok, svc.name)
            var first = paths(svc)
            compare(first.length, svc.contextCalls.length + 1, svc.name)
            for (var k = 0; k < svc.contextCalls.length; k++) {
                compare(first[k], svc.contextCalls[k], svc.name)
            }
            compare(first[first.length - 1], "DELETE " + svc.deletePath, svc.name)

            // Second call: no context requests, same ids in the path.
            requests = []
            r = del(svc)
            verify(r.ok, svc.name)
            compare(paths(svc).length, 1, svc.name + ": context reused")
            compare(paths(svc)[0], "DELETE " + svc.deletePath, svc.name)
        }
    }

    function test_presetContextSkipsLookup() {
        var all = services()
        for (var i = 0; i < all.length; i++) {
            var svc = all[i]
            svc.preset()
            responses = [{ status: 204, text: "" }]
            del(svc)
            compare(requests.length, 1, svc.name)
            requests = []
        }
    }

    function test_contextFailurePassesErrorAndStops() {
        var all = services()
        var statuses = [401, 403, 500]
        for (var i = 0; i < all.length; i++) {
            for (var s = 0; s < statuses.length; s++) {
                var svc = all[i]
                svc.reset()
                requests = []
                responses = [{ status: statuses[s], body: { message: "no" } }]
                var r = del(svc)
                verify(!r.ok, svc.name)
                compare(r.error.status, statuses[s], svc.name)
                compare(requests.length, 1, svc.name + ": the call itself is not sent")
            }
        }
    }

    function test_contextNotResolvedIsConfigError() {
        var all = services()
        for (var i = 0; i < all.length; i++) {
            var svc = all[i]
            svc.reset()
            requests = []
            responses = svc.unresolvedAnswers
            var r = del(svc)
            verify(!r.ok, svc.name)
            compare(r.error.type, "config", svc.name)
            compare(r.error.status, 0, svc.name)
            if (svc.name === "solidtime") {
                // No membership at all has its own message.
                compare(r.error.detail, "No organization membership found")
            } else {
                compare(r.error.detail, svc.emptyDetail, svc.name)
            }
            verify(paths(svc).indexOf("DELETE " + svc.deletePath) < 0, svc.name)
        }
    }

    function test_togglContextNotFoundCountsAsEmpty() {
        // 404 on /me reads as an empty answer, so the context stays unresolved.
        Toggl.setSession({ workspaceId: 0, userId: 0 })
        responses = [{ status: 404, text: "" }]
        var r = del(services()[1])
        verify(!r.ok)
        compare(r.error.type, "config")
        compare(r.error.detail, "Workspace or user not resolved")
    }

    function test_clockifyContextNotFoundIsError() {
        Clockify.setSession({ workspaceId: "", userId: "" })
        responses = [{ status: 404, text: "" }]
        var r = del(services()[0])
        verify(!r.ok)
        compare(r.error.type, Util.ErrorType.NotFound)
    }

    function test_clockifyKeepsPresetWorkspace() {
        // Only the user is missing: the workspace list is not asked.
        Clockify.setSession({ workspaceId: "w9", userId: "" })
        responses = [
            { status: 200, body: { id: "u1", activeWorkspace: "w1" } },
            { status: 204, text: "" }
        ]
        var r = del(services()[0])
        verify(r.ok)
        compare(paths(services()[0]).join("|"), "GET /user|DELETE /workspaces/w9/time-entries/5")
    }

    function test_clockifyWorkspaceFallbacks() {
        var svc = services()[0]
        // activeWorkspace, then defaultWorkspace, then the first of the list.
        var users = [
            { user: { id: "u1", activeWorkspace: "a" }, ws: [{ id: "x" }], want: "a" },
            { user: { id: "u1", defaultWorkspace: "d" }, ws: [{ id: "x" }], want: "d" },
            { user: { id: "u1" }, ws: [{ id: "x" }], want: "x" }
        ]
        for (var i = 0; i < users.length; i++) {
            Clockify.setSession({ workspaceId: "", userId: "" })
            requests = []
            responses = [
                { status: 200, body: users[i].user },
                { status: 200, body: users[i].ws },
                { status: 204, text: "" }
            ]
            del(svc)
            compare(requests[2].url, svc.base + "/workspaces/" + users[i].want + "/time-entries/5", "case " + i)
        }
    }

    function test_solidTimePicksPresetOrganization() {
        var svc = services()[2]
        SolidTime.setSession({ organizationId: "o2", memberId: "" })
        responses = [
            { status: 200, body: { data: [
                { id: "m1", organization: { id: "o1" } },
                { id: "m2", organization: { id: "o2" } }
            ] } },
            { status: 204, text: "" }
        ]
        del(svc)
        compare(requests[1].url, svc.base + "/organizations/o2/time-entries/5")

        // Unknown preset organization: first membership wins, but the preset id stays.
        SolidTime.setSession({ organizationId: "zz", memberId: "" })
        requests = []
        responses = [
            { status: 200, body: { data: [{ id: "m1", organization: { id: "o1" } }] } },
            { status: 204, text: "" }
        ]
        del(svc)
        compare(requests[1].url, svc.base + "/organizations/zz/time-entries/5")
    }

    function test_togglCustomersNeedNoContext() {
        // Toggl lists through /me/...; Clockify and SolidTime need the context first.
        var all = services()
        for (var i = 0; i < all.length; i++) {
            var svc = all[i]
            svc.reset()
            requests = []
            responses = svc.contextAnswers.concat([{ status: 200, body: svc.unwrapsData ? { data: [] } : [] }])
            load(svc)
            compare(requests.length, svc.customersContext ? svc.contextCalls.length + 1 : 1, svc.name)
        }
    }

    function test_testConnectionFailureAndSuccess() {
        Clockify.setSession({ workspaceId: "", userId: "" })
        responses = [
            { status: 200, body: { id: "u1", activeWorkspace: "w1" } },
            { status: 200, body: [{ id: "w1", name: "W" }] }
        ]
        var r = call(services()[0], "testConnection", ["", "tok"])
        verify(r.ok)
        compare(r.data.version, "Clockify")
        compare(r.data.workspaceId, "w1")
        compare(r.data.userId, "u1")
        compare(r.data.workspaces[0].name, "W")

        Toggl.setSession({ workspaceId: 0, userId: 0 })
        responses = [{ status: 200, body: { id: 7, default_workspace_id: 9, email: "a@b" } }]
        r = call(services()[1], "testConnection", ["", "tok"])
        verify(r.ok)
        compare(r.data.workspaceId, 9)
        compare(r.data.email, "a@b")

        SolidTime.setSession({ organizationId: "", memberId: "" })
        responses = [
            { status: 200, body: { data: { id: "u1", name: "N" } } },
            { status: 200, body: { data: [{ id: "m1", organization: { id: "o1", name: "O" } }] } }
        ]
        r = call(services()[2], "testConnection", ["https://st.example", "tok"])
        verify(r.ok)
        compare(r.data.version, "SolidTime")

        // A 401 passes through unchanged.
        for (var i = 0; i < 3; i++) {
            var svc = services()[i]
            svc.reset()
            responses = [{ status: 401, text: "" }]
            r = call(svc, "testConnection", ["https://st.example", "tok"])
            compare(r.error.type, Util.ErrorType.Unauthorized, svc.name)
        }
    }
}
