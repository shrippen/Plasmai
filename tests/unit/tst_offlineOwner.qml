import QtQuick
import QtTest
import "../../contents/code/offline.js" as Offline
import "../../contents/code/offlineOutbox.js" as Outbox
import "../../contents/code/offlineState.js" as OfflineState
import "../../contents/code/offlineOwner.js" as Owner
import "../../contents/code/localFile.js" as LocalFile
import "../../contents/code/providerUtil.js" as ProviderUtil

/**
 * The owner of the waiting changes (offlineOwner.js): a server and an account. Changes of
 * another server or account are parked, never sent and never laid over the answers of
 * the new one; the user sends or discards them. A fake Kimai answers at once.
 */
TestCase {
    name: "OfflineOwner"

    OfflineFakes { id: fakes }

    readonly property string outboxName: "offline-outbox-p1"
    readonly property string stateName: "offline-state-p1"
    readonly property string urlA: "https://kimai.test"
    readonly property string urlB: "https://other.test"
    readonly property int markTok: Owner.markOf("tok")
    readonly property var ownerA: ({ server: "https://kimai.test", mark: markTok, account: "7", name: "User 7" })
    readonly property var ownerB: ({ server: "https://other.test", mark: markTok, account: "7", name: "User 7" })
    readonly property var keyA: ({ server: "https://kimai.test", mark: markTok })

    /** What settle gets: the connection (address, token) and the account the server named ("" = not checked). */
    function idOf(url, token, account, name) {
        return { server: Owner.serverOf(url), mark: Owner.markOf(token), account: account || "", name: name || "" }
    }

    function stamp(h, m) { return fakes.stamp(h, m) }
    function fakeKimai() { return fakes.fakeKimai() }
    function fakeHost(files) { return fakes.fakeHost(files) }
    function call(fn) { return fakes.call(fn) }

    function createOp(id, state, by) {
        return { opId: "local:op-" + id, kind: "create", entryId: "local:" + id, state: state || "pending", attempts: 0,
                 maybeSent: false, error: null, createdAt: fakes.t0, by: by || keyA,
                 fields: { begin: stamp(9, 0), end: stamp(10, 0), project: 10, activity: 20 } }
    }

    function patchOp(entryId, fields, base) {
        return { opId: "local:patch-" + entryId, kind: "patch", entryId: entryId, state: "pending", attempts: 0,
                 error: null, createdAt: fakes.t0, by: keyA, fields: fields, base: base || null }
    }

    function outboxFile(owner, ops, held) {
        const file = { v: 1, counter: 9, owner: owner, ops: ops, held: held || [] }
        if (!owner) {
            delete file.owner
        }
        return JSON.stringify(file)
    }

    /** A session on `url` over the files of `h`, read and its account checked. */
    function open(k, h, url, token) {
        h.currentUrl = url
        h.currentToken = token || "tok"
        const s = fakes.session(k, h)
        fakes.loaded(s, this)
        Offline.verify(s)
        return s
    }

    function saved(h) { return JSON.parse(h.files[outboxName]) }

    // -- serverOf, settle -----------------------------------------------------------

    function test_sameServerSpellings_data() {
        return [
            { a: "https://Kimai.Test/", b: "https://kimai.test", same: true },
            { a: "HTTPS://kimai.test", b: "https://kimai.test", same: true },
            { a: "https://kimai.test:443", b: "https://kimai.test", same: true },
            { a: "http://kimai.test:80/", b: "http://kimai.test", same: true },
            { a: "https://kimai.test:8443", b: "https://kimai.test", same: false },
            { a: "http://kimai.test", b: "https://kimai.test", same: false },
            { a: "https://10.0.0.5", b: "https://kimai.test", same: false },
            { a: "https://kimai.test/kimai", b: "https://kimai.test", same: false },
            { a: "https://kimai.test/Kimai/", b: "https://kimai.test/kimai", same: false }
        ]
    }

    function test_sameServerSpellings(data) {
        compare(Owner.serverOf(data.a) === Owner.serverOf(data.b), data.same)
    }

    function sessionOf(owner, ops, held) {
        return { owner: owner, ops: ops || [], held: held || [], counter: 0, snapshot: OfflineState.emptySnapshot() }
    }

    function test_noServerSettlesNothing() {
        const s = sessionOf(ownerA, [createOp(1)])
        compare(Owner.settle(s, idOf("", "tok"), 0), Owner.Result.NONE)
        compare(s.ops.length, 1)
        compare(s.held.length, 0)
        compare(s.owner.server, ownerA.server)
    }

    function test_noOwnerWaitsForTheAccount() {
        const s = sessionOf(null, [createOp(1)])
        compare(Owner.settle(s, idOf(urlA, "tok"), 0), Owner.Result.NONE)
        verify(!s.owner)
        compare(Owner.settle(s, ownerA, 0), Owner.Result.CLAIMED)
        compare(s.owner.account, "7")
        compare(s.ops.length, 1)
    }

    function test_sameServerUnknownAccountChangesNothing() {
        const s = sessionOf(ownerA, [createOp(1)])
        compare(Owner.settle(s, idOf(urlA, "tok"), 0), Owner.Result.NONE)
        compare(s.ops.length, 1)
        compare(Owner.settle(s, ownerA, 0), Owner.Result.NONE)
        compare(s.ops.length, 1)
    }

    function test_otherServerParksTheOps() {
        const s = sessionOf(ownerA, [createOp(1), createOp(2)])
        s.snapshot.entries["5"] = { id: 5 }
        const b = idOf(urlB, "tok")
        compare(Owner.settle(s, b, 0), Owner.Result.PARKED)
        compare(s.ops.length, 0)
        compare(s.held.length, 1)
        compare(s.held[0].ops.length, 2)
        compare(s.held[0].owner.server, ownerA.server)
        compare(s.owner.server, b.server)
        compare(Object.keys(s.snapshot.entries).length, 0, "the snapshot of the other server is gone")
    }

    function test_otherAccountParksTheOps() {
        const s = sessionOf(ownerA, [createOp(1)])
        const other = idOf(urlA, "tok", "8", "User 8")
        compare(Owner.settle(s, other, 0), Owner.Result.PARKED)
        compare(s.held.length, 1)
        compare(s.owner.account, "8")
    }

    function test_noOpsLeavesNoGroup() {
        const s = sessionOf(ownerA, [])
        compare(Owner.settle(s, idOf(urlB, "tok"), 0), Owner.Result.PARKED)
        compare(s.held.length, 0)
    }

    function test_backToTheOwnerResumesItsGroup() {
        const s = sessionOf(ownerA, [createOp(1), patchOp("local:1", { description: "x" })])
        Owner.settle(s, idOf(urlB, "tok"), 0)
        Owner.settle(s, idOf(urlB, "tok", "3", "Three"), 0)
        compare(s.ops.length, 0)
        compare(Owner.settle(s, ownerA, 0), Owner.Result.PARKED, "B's own ops (none) park, A's group is resumed")
        compare(s.held.length, 0)
        compare(s.ops.length, 2)
        compare(s.ops[0].kind, "create")
        compare(s.ops[1].kind, "patch")
    }

    function test_unknownAccountFillsInOnVerify() {
        const s = sessionOf({ server: urlB, mark: markTok, account: "", name: "" }, [createOp(3, "pending", { server: urlB, mark: markTok })])
        compare(Owner.settle(s, idOf(urlB, "tok", "3", "Three"), 0), Owner.Result.FILLED)
        compare(s.owner.account, "3")
        compare(s.ops.length, 1)
    }

    // -- Files ----------------------------------------------------------------------

    // A start without an address decides nothing and writes nothing; with it, everything is there.
    function test_emptyUrlStartKeepsTheFile() {
        const k = fakeKimai()
        const h = fakeHost()
        h.files[outboxName] = outboxFile(ownerA, [createOp(1)])
        const before = h.files[outboxName]
        const s = open(k, h, "")
        compare(h.files[outboxName], before)
        compare(h.saves.length, 0)
        compare(Outbox.pendingCount(s), 1)
        compare(k.meCalls, 0, "no address, no account check")
        compare(k.calls.length, 0)

        const again = open(k, fakeHost(h.files), urlA)
        compare(Offline.heldCount(again), 0)
        compare(k.calls.indexOf("create") >= 0, true, "all there, and sent")
        compare(Outbox.pendingCount(again), 0)
    }

    function test_oldFileIsClaimedAfterTheCheckAndSent() {
        const k = fakeKimai()
        const h = fakeHost()
        h.files[outboxName] = outboxFile(null, [createOp(1)])
        const s = Offline.createSession(k, h)
        fakes.loaded(s, this)
        compare(h.saves.length, 0, "unknown account: nothing claimed")
        Outbox.replay(s)
        compare(k.calls.length, 0, "nothing is sent before the check")

        Offline.verify(s)
        compare(saved(h).owner.account, "7")
        compare(saved(h).owner.server, urlA)
        compare(k.calls.indexOf("create") >= 0, true, "sent after the claim")
        compare(Outbox.pendingCount(s), 0)
    }

    // A changed address parks the changes: nothing goes there, only "discard" is offered. Entering
    // the old address again brings them back, and they are sent.
    function test_changedSpellingParksAndTheOldAddressSends() {
        const k = fakeKimai()
        const h = fakeHost()
        h.files[outboxName] = outboxFile(ownerA, [createOp(1), createOp(2)])
        const s = open(k, h, "https://kimai.test/kimai")
        compare(Outbox.pendingCount(s), 0)
        compare(Offline.groups(s).length, 1)
        compare(Offline.heldCount(s), 2)
        compare(k.calls.indexOf("create"), -1, "nothing went to the new address")
        compare(saved(h).held.length, 1)
        compare(Offline.groups(s)[0].canAdopt, undefined, "there is no sending to another address")
        compare(Offline.adopt, undefined)

        const back = open(k, fakeHost(h.files), urlA)
        compare(Offline.groups(back).length, 0)
        compare(k.calls.filter(function(c) { return c === "create" }).length, 2)
        compare(saved(h).held.length, 0)
    }

    // The save of the parking fails: the file still holds the ops under the old owner,
    // so the next start parks them again. Nothing twice, nothing lost.
    function test_failedSaveWhileParkingParksAgainAfterRestart() {
        const k = fakeKimai()
        const h = fakeHost()
        h.files[outboxName] = outboxFile(ownerA, [createOp(1)])
        const before = h.files[outboxName]
        h.failSave = true
        const s = open(k, h, urlB)
        compare(Offline.heldCount(s), 1)
        compare(h.files[outboxName], before)
        tryCompare(s, "storageError", OfflineState.StorageError.SAVE)

        const restarted = open(k, fakeHost(h.files), urlB)
        compare(Offline.heldCount(restarted), 1)
        compare(Outbox.pendingCount(restarted), 0)
        compare(saved(h).held.length, 1)
        compare(saved(h).held[0].ops.length, 1)
        compare(saved(h).ops.length, 0)
        compare(saved(h).owner.server, urlB)
    }

    // -- What B sees ----------------------------------------------------------------

    // #84 round 2: changes made on A are never laid over B's answers.
    function test_changesOfAAreNotLaidOverB() {
        const ka = fakeKimai()
        ka.server[5] = { id: 5, begin: stamp(8, 0), end: stamp(9, 0), project: 10, activity: 20, description: "a" }
        ka.server[7] = { id: 7, begin: stamp(9, 0), end: stamp(10, 0), project: 10, activity: 20 }
        const ha = fakeHost()
        const a = open(ka, ha, urlA)
        call(function(cb) { a.tracker.fetchRecentTimesheets("u", "t", 10, cb) })
        ka.net = false
        call(function(cb) { a.tracker.patchTimesheet("u", "t", 5, { end: stamp(9, 30) }, cb) })
        call(function(cb) { a.tracker.deleteTimesheet("u", "t", 7, cb) })
        call(function(cb) { a.tracker.startTracking("u", "t", 10, 20, "", cb, {}) })
        compare(Outbox.pendingCount(a), 3)

        const kb = fakeKimai()
        kb.userId = 7
        kb.server[5] = { id: 5, begin: stamp(8, 0), end: stamp(8, 45), project: 10, activity: 20, description: "b" }
        kb.server[7] = { id: 7, begin: stamp(10, 0), end: stamp(11, 0), project: 10, activity: 20 }
        const b = open(kb, fakeHost(ha.files), urlB)
        compare(Outbox.pendingCount(b), 0)
        compare(Offline.heldCount(b), 3)

        const recent = call(function(cb) { b.tracker.fetchRecentTimesheets("u", "t", 10, cb) })
        compare(recent.data.length, 2)
        compare(recent.data.filter(function(ts) { return ts.id === 5 })[0].end, stamp(8, 45))
        verify(recent.data.some(function(ts) { return ts.id === 7 }))
        const active = call(function(cb) { b.tracker.fetchActiveTimesheet("u", "t", cb) })
        compare(active.data.length, 0)
    }

    // The parked group blocks nothing: a start on B goes straight to the server.
    function test_startOnBAfterParkingIsNotQueued() {
        const k = fakeKimai()
        const h = fakeHost()
        h.files[outboxName] = outboxFile(ownerA, [createOp(1)])
        const s = open(k, h, urlB)
        const result = call(function(cb) { s.tracker.startTracking("u", "t", 10, 20, "", cb, {}) })
        verify(result.ok)
        verify(!result.queued)
        compare(k.calls[k.calls.length - 1], "start")
    }

    // A refusal waits in the group as it is; on the old address it is the queue's again, still refused.
    function test_refusedOpKeepsItsStateThroughAGroup() {
        const k = fakeKimai()
        const h = fakeHost()
        const failed = createOp(1, "failed")
        failed.error = { type: "unknown", status: 500, detail: "x" }
        h.files[outboxName] = outboxFile(ownerA, [failed])
        const b = open(k, h, urlB)
        compare(Offline.groups(b).length, 1)
        const a = open(k, fakeHost(h.files), urlA)
        compare(Outbox.ops(a)[0].state, OfflineState.State.FAILED)
        compare(Outbox.ops(a)[0].error.status, 500)
        compare(k.calls.indexOf("create"), -1)
    }

    function test_backToAResumesTheGroupInOrder() {
        const ka = fakeKimai()
        const h = fakeHost()
        h.files[outboxName] = outboxFile(ownerA, [createOp(1), patchOp("local:1", { description: "later" })])
        const kb = fakeKimai()
        const b = open(kb, h, urlB)
        compare(Offline.heldCount(b), 2)

        const a = open(ka, fakeHost(h.files), urlA)
        compare(Offline.heldCount(a), 0)
        compare(Outbox.pendingCount(a), 0, "sent on the way back")
        compare(ka.calls.filter(function(c) { return c === "create" || c.indexOf("patch") === 0 }).length, 2)
        compare(ka.calls.indexOf("create") < ka.calls.indexOf("patch 100"), true, "create first, then its patch")
    }

    // -- Accounts -------------------------------------------------------------------

    function test_otherAccountOnTheSameServerStaysParked() {
        const k = fakeKimai()
        k.userId = 8
        const h = fakeHost()
        h.files[outboxName] = outboxFile(ownerA, [createOp(1)])
        const s = open(k, h, urlA)
        compare(Offline.groups(s).length, 1)
        const group = Offline.groups(s)[0]
        compare(group.name, "User 7")
        compare(Offline.heldCount(s), 1, "still parked")
        compare(k.calls.indexOf("create"), -1)
        compare(Outbox.pendingCount(s), 0)
    }

    function test_unauthorizedCheckParksAndSendsNothing() {
        const k = fakeKimai()
        k.meError = { type: "unauthorized", status: 401, detail: "" }
        const h = fakeHost()
        h.files[outboxName] = outboxFile(ownerA, [createOp(1)])
        const s = open(k, h, urlA)
        verify(!s.verified)
        compare(Offline.heldCount(s), 0)
        compare(Outbox.pendingCount(s), 1)
        Outbox.replay(s)
        compare(k.calls.indexOf("create"), -1)
        compare(h.saves.length, 0)
    }

    function test_noNetworkCheckWaits() {
        const k = fakeKimai()
        k.net = false
        const h = fakeHost()
        h.files[outboxName] = outboxFile(ownerA, [createOp(1)])
        const s = open(k, h, urlA)
        verify(!s.verified)
        k.net = true
        // The first good answer of the server checks the account, then the outbox goes out.
        call(function(cb) { s.tracker.fetchActiveTimesheet("u", "t", cb) })
        verify(s.verified)
        compare(k.calls.indexOf("create") >= 0, true)
        compare(Outbox.pendingCount(s), 0)
    }

    function test_answersAreNotRememberedBeforeTheCheck() {
        const k = fakeKimai()
        k.meError = { type: "unauthorized", status: 401, detail: "" }
        k.server[1] = { id: 1, begin: stamp(9, 0), end: stamp(10, 0), project: 10, activity: 20 }
        const h = fakeHost()
        const s = open(k, h, urlA)
        call(function(cb) { s.tracker.fetchRecentTimesheets("u", "t", 10, cb) })
        compare(Object.keys(s.snapshot.entries).length, 0)
    }

    // -- Replay ---------------------------------------------------------------------

    // A change of address during a replay waits for it: the op on its way is neither
    // sent twice nor parked while it is still being sent.
    function test_settleWaitsForTheReplay() {
        const h = fakeHost()
        h.files[outboxName] = outboxFile(ownerA, [createOp(3), createOp(4)])
        const slow = fakeKimai()
        const held = []
        slow.createTimesheet = function(u, t, f, cb) { held.push(cb) }
        slow.fetchTimesheetsRange = function(u, t, b, e, cb) { cb({ ok: true, data: [] }) }
        const h2 = h
        const s2 = open(slow, h2, urlA)
        compare(held.length, 1)

        h2.currentUrl = urlB
        Offline.retarget(s2)
        compare(Outbox.pendingCount(s2), 2, "not parked while the op is on its way")
        compare(Offline.heldCount(s2), 0)

        held.shift()({ ok: true, data: { id: 99 } })
        compare(Outbox.pendingCount(s2), 0)
        compare(Offline.heldCount(s2), 1, "the rest is parked once the replay stopped")
        compare(held.length, 0, "the second op did not go to the new address")
        compare(s2.owner.server, urlB)
    }

    function test_ownerChangeIsSignalled() {
        const k = fakeKimai()
        const h = fakeHost()
        h.files[outboxName] = outboxFile(ownerA, [createOp(1)])
        open(k, h, urlB)
        compare(h.ownerChanges, 1)
    }

    // -- Terminal: an op that failed no longer blocks everything --------------------

    function test_discardingAFailedOpFreesTheQueue() {
        const k = fakeKimai()
        const h = fakeHost()
        const failed = createOp(1, "failed")
        failed.error = { type: "unknown", status: 500, detail: "x" }
        h.files[outboxName] = outboxFile(ownerA, [failed])
        const s = open(k, h, urlA)
        const queued = call(function(cb) { s.tracker.startTracking("u", "t", 10, 20, "", cb, {}) })
        verify(queued.queued, "behind the failed op")
        Outbox.discard(s, "local:op-1")
        Outbox.discard(s, Outbox.ops(s)[0].opId)
        const direct = call(function(cb) { s.tracker.startTracking("u", "t", 10, 20, "", cb, {}) })
        verify(direct.ok)
        verify(!direct.queued)
    }

    function test_discardGroup() {
        const k = fakeKimai()
        const h = fakeHost()
        h.files[outboxName] = outboxFile(ownerA, [createOp(1)])
        const s = open(k, h, urlB)
        compare(Offline.heldCount(s), 1)
        Offline.discardGroup(s, Offline.groups(s)[0].id)
        compare(Offline.heldCount(s), 0)
        compare(saved(h).held.length, 0)
        compare(k.calls.indexOf("create"), -1)
    }

    // -- Closed session -------------------------------------------------------------

    // #89 round 4: a closed session that sends a waiting delete writes the snapshot too, so the
    // entry does not come back after a restart without network.
    function test_closedSessionWritesTheSnapshotOfASentOp() {
        const k = fakeKimai()
        k.server[5] = { id: 5, begin: stamp(8, 0), end: stamp(9, 0), project: 10, activity: 20 }
        const h = fakeHost()
        const s = open(k, h, urlA)
        call(function(cb) { s.tracker.fetchRecentTimesheets("u", "t", 10, cb) })
        k.net = false
        call(function(cb) { s.tracker.deleteTimesheet("u", "t", 5, cb) })
        k.net = true
        const held = []
        const del = k.deleteTimesheet
        k.deleteTimesheet = function(u, t, id, cb) { held.push(function() { del(u, t, id, cb) }) }
        Outbox.observe(s, { ok: true, data: [] })
        compare(held.length, 1)
        Offline.close(s)
        held.shift()()
        verify(!JSON.parse(h.files[stateName]).entries["5"])
    }

    // The film day plugin call of a waiting change goes through the same gate: no check, no send.
    function test_filmDayOpWaitsForTheCheck() {
        const k = fakeKimai()
        k.putFilmDay = function(u, t, pid, day, patch, cb) { k.calls.push("film"); cb({ ok: true, data: null }) }
        const h = fakeHost()
        const op = { opId: "local:film", kind: "filmDay", projectId: 10, dateStr: "2026-09-28", patch: { note: "x" },
                     state: "pending", attempts: 0, error: null, createdAt: fakes.t0 }
        h.files[outboxName] = outboxFile(ownerA, [op])
        const s = Offline.createSession(k, h)
        fakes.loaded(s, this)
        Outbox.replay(s)
        compare(k.calls.indexOf("film"), -1)
        Offline.verify(s)
        compare(k.calls.indexOf("film") >= 0, true)
        compare(Outbox.pendingCount(s), 0)
    }

    // -- The key of a connection: address and token; the account is what the server says of it --

    function keyOf(url, token) { return { server: Owner.serverOf(url), mark: Owner.markOf(token) } }

    /** A session that started offline on A, then went through the addresses (and tokens) given. */
    function wander(k, h, steps) {
        k.net = false
        const s = open(k, h, urlA)
        for (let i = 0; i < steps.length; i++) {
            h.currentUrl = steps[i].url
            h.currentToken = steps[i].token || "tok"
            Offline.retarget(s)
            if (steps[i].start) {
                call(function(cb) { s.tracker.startTracking("u", "t", 10, 20, steps[i].start, cb, {}) })
            }
        }
        return s
    }

    // Review: A, B (unchecked), C, B again with the same token: the group of B has no account
    // yet and still comes back by itself; after the check it is sent.
    function test_groupWithoutAccountResumesOnTheSameConnection() {
        const k = fakeKimai()
        const h = fakeHost()
        h.files[outboxName] = outboxFile(ownerA, [createOp(1)])
        const s = wander(k, h, [{ url: urlB, start: "b" }, { url: "https://c.test" }, { url: urlB }])
        compare(Outbox.pendingCount(s), 1, "B's own start is back")
        compare(Outbox.ops(s)[0].fields.description, "b")
        compare(Offline.groups(s).length, 1)
        compare(Offline.groups(s)[0].server, urlA)
        k.net = true
        Offline.verify(s)
        compare(k.calls.filter(function(c) { return c === "create" }).length, 1, "only B's start went out")
        compare(Outbox.pendingCount(s), 0)
        compare(Offline.heldCount(s), 1)
    }

    // The same way with another token the second time: the group stays, nothing offers to send
    // it, and its words do not name nobody.
    function test_groupWithoutAccountStaysForAnotherToken() {
        const k = fakeKimai()
        const h = fakeHost()
        h.files[outboxName] = outboxFile(ownerA, [createOp(1)])
        const s = wander(k, h, [{ url: urlB, start: "b" }, { url: "https://c.test" }, { url: urlB, token: "other" }])
        compare(Outbox.pendingCount(s), 0)
        const groups = Offline.groups(s)
        compare(groups.length, 2)
        const orphan = groups.filter(function(g) { return g.server === urlB })[0]
        compare(orphan.name, "")
        compare(orphan.account, "")
    }

    // Review: Ann is checked, offline Bob's token (same server) goes in and Bob starts a timer.
    // The check says account 2: Bob's start is Bob's, Ann's changes wait under account 1.
    function test_changeOfTheTokenKeepsEachOneTheirOwn() {
        const k = fakeKimai()
        const h = fakeHost()
        const ann = { server: urlA, mark: Owner.markOf("annToken") }
        h.files[outboxName] = outboxFile({ server: urlA, mark: ann.mark, account: "1", name: "Ann" }, [createOp(1, "pending", ann)])
        k.userId = 1
        const s = wander(k, h, [])
        h.currentUrl = urlA
        h.currentToken = "bobToken"
        Offline.retarget(s)
        call(function(cb) { s.tracker.startTracking("u", "t", 10, 20, "bob", cb, {}) })
        compare(Outbox.pendingCount(s), 1)
        compare(Offline.groups(s).length, 1)
        compare(Offline.groups(s)[0].account, "1")

        k.net = true
        k.userId = 2
        Offline.verify(s)
        compare(Outbox.pendingCount(s), 0, "Bob's start went out as Bob")
        compare(k.calls.filter(function(c) { return c === "create" }).length, 1)
        compare(Offline.groups(s).length, 1, "Ann's change was not sent")
        compare(Offline.groups(s)[0].account, "1")
        compare(Offline.groups(s)[0].name, "Ann")
    }

    // Back to Ann's token: only Ann's changes go out, Bob's wait under account 2.
    function test_backToTheOwnerSendsOnlyTheirs() {
        const k = fakeKimai()
        const h = fakeHost()
        const ann = { server: urlA, mark: Owner.markOf("annToken") }
        h.files[outboxName] = outboxFile({ server: urlA, mark: ann.mark, account: "1", name: "Ann" }, [createOp(1, "pending", ann)])
        k.userId = 1
        const s = wander(k, h, [{ url: urlA, token: "bobToken", start: "bob" }, { url: urlA, token: "annToken" }])
        compare(Outbox.pendingCount(s), 1)
        compare(Outbox.ops(s)[0].fields.description, undefined, "Ann's create")
        k.net = true
        Offline.verify(s)
        compare(k.calls.filter(function(c) { return c === "create" }).length, 1)
        compare(Outbox.pendingCount(s), 0)
        const bob = Offline.groups(s)
        compare(bob.length, 1)
        compare(bob[0].count, 1)
    }

    // Review: a write while the file is read must not land in the group of the file's owner.
    function test_writeWhileLoadingIsNotParkedWithTheFile() {
        const k = fakeKimai()
        k.net = false
        const h = fakeHost()
        h.files[outboxName] = outboxFile(ownerA, [createOp(1)])
        h.holdLoad = true
        h.currentUrl = urlB
        const s = fakes.session(k, h)
        let done = false
        Offline.load(s).then(function() { done = true })
        call(function(cb) { s.tracker.startTracking("u", "t", 10, 20, "new", cb, {}) })
        h.release()
        tryVerify(function() { return done })
        compare(Outbox.pendingCount(s), 1)
        compare(Outbox.ops(s)[0].fields.description, "new")
        compare(Outbox.ops(s)[0].by.server, urlB)
        compare(Offline.heldCount(s), 1)
        compare(Offline.groups(s)[0].server, urlA)
    }

    // Review: a write after the connection changed in the middle of a replay is neither sent
    // over the old connection nor parked for the old owner.
    function test_writeDuringReplayAfterAChangeOfConnection() {
        const slow = fakeKimai()
        const held = []
        slow.createTimesheet = function(u, t, f, cb) { held.push(cb) }
        const h = fakeHost()
        h.files[outboxName] = outboxFile(ownerA, [createOp(3), createOp(4)])
        const s = open(slow, h, urlA)
        compare(held.length, 1)

        h.currentUrl = urlB
        Offline.retarget(s)
        slow.net = false
        call(function(cb) { s.tracker.startTracking("u", "t", 10, 20, "new", cb, {}) })
        held.shift()({ ok: true, data: { id: 99 } })

        compare(held.length, 0, "nothing went to the old connection again")
        compare(Outbox.pendingCount(s), 1)
        compare(Outbox.ops(s)[0].fields.description, "new")
        compare(Offline.heldCount(s), 1, "the second op of A is parked")
        compare(s.owner.server, urlB)
    }

    // Replay sends an op only over the connection it was made for.
    function test_foreignOpInTheQueueStopsTheReplay() {
        const k = fakeKimai()
        const h = fakeHost()
        const s = open(k, h, urlA)
        s.ops.push(createOp(1, "pending", keyOf("https://zzz.test", "tok")))
        Outbox.replay(s)
        compare(k.calls.indexOf("create"), -1)
        compare(s.ops.length, 1)
    }

    // The same user id on another server and another token is somebody else: only discarding.
    function test_otherServerOtherTokenStaysParked() {
        const k = fakeKimai()
        k.userId = 7
        const h = fakeHost()
        h.files[outboxName] = outboxFile(ownerA, [createOp(1)])
        const s = open(k, h, urlB, "otherToken")
        const groups = Offline.groups(s)
        compare(groups.length, 1)
        compare(k.calls.indexOf("create"), -1)
        compare(Offline.heldCount(s), 1)
        Offline.discardGroup(s, groups[0].id)
        compare(Offline.heldCount(s), 0)
    }

    // Another server with the same token is not the same database either (Kimai counts users and
    // projects from 1 on every server): parked, only discarding is offered; the old address
    // brings the group back and it is sent.
    function test_otherServerSameTokenIsNotSentThere() {
        const k = fakeKimai()
        const h = fakeHost()
        h.files[outboxName] = outboxFile(ownerA, [createOp(1)])
        const s = open(k, h, urlB)
        compare(Offline.groups(s).length, 1)
        compare(Offline.groups(s)[0].canAdopt, undefined)
        compare(k.calls.indexOf("create"), -1)
        compare(Outbox.pendingCount(s), 0)
        const back = open(k, fakeHost(h.files), urlA)
        compare(Offline.heldCount(back), 0)
        compare(k.calls.indexOf("create") >= 0, true)
    }

    // A renewed token of the same account: parked at first, active by itself after the check.
    function test_renewedTokenOfTheSameAccountResumes() {
        const k = fakeKimai()
        k.net = false
        const h = fakeHost()
        h.files[outboxName] = outboxFile(ownerA, [createOp(1)])
        const s = open(k, h, urlA, "renewed")
        compare(Outbox.pendingCount(s), 0)
        compare(Offline.heldCount(s), 1)
        k.net = true
        Offline.verify(s)
        compare(Offline.heldCount(s), 0)
        compare(k.calls.indexOf("create") >= 0, true)
        compare(Outbox.pendingCount(s), 0)
    }

    // The same key and another account (the database was swapped): parked, no way back by
    // itself and no loop when it is asked again.
    function test_sameKeyOtherAccountDoesNotLoop() {
        const k = fakeKimai()
        k.userId = 8
        const h = fakeHost()
        h.files[outboxName] = outboxFile(ownerA, [createOp(1)])
        const s = open(k, h, urlA)
        Offline.verify(s)
        Offline.retarget(s)
        Offline.verify(s)
        compare(Offline.groups(s).length, 1)
        compare(Outbox.pendingCount(s), 0)
        compare(k.calls.indexOf("create"), -1)
    }

    // A file of version 2.7.0 has neither owner nor stamps on its ops.
    function test_oldFileGetsItsStamps() {
        const k = fakeKimai()
        const h = fakeHost()
        const old = createOp(1)
        delete old.by
        h.files[outboxName] = outboxFile(null, [old])
        k.net = false
        const s = open(k, h, urlA)
        compare(Outbox.pendingCount(s), 1)
        k.net = true
        Offline.verify(s)
        compare(saved(h).owner.mark, markTok)
        compare(k.calls.indexOf("create") >= 0, true)
    }

    // The settling happens before a write is queued, so it is stamped for what is asked now.
    function test_writeSettlesBeforeQueueing() {
        const k = fakeKimai()
        k.net = false
        const h = fakeHost()
        h.files[outboxName] = outboxFile(ownerA, [createOp(1)])
        const s = open(k, h, urlA)
        h.currentToken = "changed"
        call(function(cb) { s.tracker.startTracking("u", "t", 10, 20, "x", cb, {}) })
        compare(s.owner.mark, Owner.markOf("changed"))
        compare(Outbox.pendingCount(s), 1)
        compare(Outbox.ops(s)[0].by.mark, Owner.markOf("changed"))
        compare(Offline.heldCount(s), 1)
    }

    // Groups keep their id: the one asked about stays the one that is meant.
    function test_groupIdsAreStable() {
        const k = fakeKimai()
        const h = fakeHost()
        h.files[outboxName] = outboxFile(ownerA, [createOp(1)])
        const s = open(k, h, urlB, "x")
        h.currentUrl = "https://c.test"
        Offline.retarget(s)
        const ids = Offline.groups(s).map(function(g) { return g.id })
        compare(ids.length, 1)
        k.net = false
        call(function(cb) { s.tracker.startTracking("u", "t", 10, 20, "x", cb, {}) })
        h.currentUrl = urlA
        h.currentToken = "again"
        Offline.retarget(s)
        verify(Offline.groups(s).some(function(g) { return g.id === ids[0] }))
        Offline.discardGroup(s, "nope")
        compare(Offline.groups(s).length, 2)
    }

    // Review: before the check the first read is not asked twice.
    function test_noDoubleReadBeforeTheCheck() {
        const k = fakeKimai()
        k.meError = { type: "unauthorized", status: 401, detail: "" }
        const h = fakeHost()
        h.files[outboxName] = outboxFile(ownerA, [createOp(1)])
        const s = open(k, h, urlA)
        call(function(cb) { s.tracker.fetchActiveTimesheet("u", "t", cb) })
        compare(k.calls.filter(function(c) { return c === "active" }).length, 1)
    }

    // Review: nor are the film day's answers kept before the check.
    function test_filmDaysAreNotKeptBeforeTheCheck() {
        const k = fakeKimai()
        k.meError = { type: "unauthorized", status: 401, detail: "" }
        const h = fakeHost()
        const s = open(k, h, urlA)
        OfflineState.rememberFilmDays(s, { day: { x: 1 } })
        compare(Object.keys(s.snapshot.filmDays).length, 0)
    }
}
