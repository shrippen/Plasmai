import QtQuick
import QtTest
import "../../contents/ui" as Ui

/**
 * Changes parked for another server or account: the status line counts them apart, the list
 * shows one block per group (read only, foldable) with "Send here" (same account only) and
 * "Discard", each after one question that names the addresses. The words stand once, in ApiErrors.
 */
TestCase {
    name: "UnsyncedGroups"
    visible: true
    when: windowShown
    width: 400
    height: 600

    readonly property var op: ({ opId: "local:1", kind: "delete", entryId: 5, state: "failed",
        error: { type: "unknown", status: 500, detail: "x" }, base: { project: "1", activity: "2" } })
    readonly property var sendable: ({ id: "g1", name: "Ann", server: "https://old.test", to: "https://new.test",
        account: "7", sameServer: false, count: 2, canAdopt: true, ops: [op, op] })
    readonly property var foreign: ({ id: "g2", name: "Bob", server: "https://new.test", to: "https://new.test",
        account: "8", sameServer: true, count: 1, canAdopt: false, ops: [op] })
    // Made on an address the token was not checked on, and the token is not the one in use.
    readonly property var orphan: ({ id: "g3", name: "", server: "https://b.test", to: "https://new.test",
        account: "", sameServer: false, count: 1, canAdopt: false, ops: [op] })

    Component {
        id: listComponent
        Ui.UnsyncedList { width: 360 }
    }

    Component {
        id: statusComponent
        Ui.OfflineStatus { width: 360 }
    }

    SignalSpy { id: adoptSpy; signalName: "adoptRequested" }
    SignalSpy { id: dropSpy; signalName: "discardGroupRequested" }

    function list(groups) {
        const l = createTemporaryObject(listComponent, this, { groups: groups, ops: [] })
        adoptSpy.target = l
        adoptSpy.clear()
        dropSpy.target = l
        dropSpy.clear()
        return l
    }

    function test_wordsNameBothAddresses() {
        compare(Ui.ApiErrors.heldStatusText(2), "2 changes wait for another server or account")
        compare(Ui.ApiErrors.heldGroupText(sendable), "2 changes wait for Ann on https://old.test")
        compare(Ui.ApiErrors.heldGroupText(foreign), "1 change waits for Bob on https://new.test")
        compare(Ui.ApiErrors.heldHint(foreign), "Sign in as Bob to send them.")
        compare(Ui.ApiErrors.heldHint(sendable), "")
        // No name to show: the words do not leave a hole, and say what brings the changes back.
        compare(Ui.ApiErrors.heldGroupText(orphan), "1 change waits on https://b.test")
        compare(Ui.ApiErrors.heldHint(orphan), "Enter the old address or token again to send them.")
        const question = Ui.ApiErrors.adoptQuestion(sendable)
        verify(question.indexOf("https://old.test") >= 0 && question.indexOf("https://new.test") >= 0)
    }

    function test_statusCountsParkedChangesApart() {
        const status = createTemporaryObject(statusComponent, this, {})
        verify(!status.visible)
        status.held = 3
        verify(status.visible, "also online with nothing else waiting")
        verify(status.text().indexOf("3 changes wait for another server or account") >= 0)
        status.unsynced = 1
        verify(status.text().indexOf("1 change not synced yet") >= 0)
        verify(status.text().indexOf("3 changes wait") >= 0)
    }

    function test_groupBlockShowsTheOpsOnlyWhenOpened() {
        const l = list([sendable])
        compare(findChild(l, "heldGroupTitle").text, "2 changes wait for Ann on https://old.test")
        compare(findChild(l, "heldOps").visible, false)
        findChild(l, "heldToggle").clicked()
        compare(findChild(l, "heldOps").visible, true)
        compare(findChild(l, "heldOps").children.length >= 2, true)
        verify(!findChild(l, "emptyLabel").visible)
    }

    function test_sendHereAsksOnceThenSends() {
        const l = list([sendable])
        verify(findChild(l, "adoptButton").visible)
        verify(!findChild(l, "confirmRow").visible)
        findChild(l, "adoptButton").clicked()
        verify(findChild(l, "confirmRow").visible)
        compare(adoptSpy.count, 0)
        verify(findChild(l, "confirmText").text.indexOf("https://new.test") >= 0)
        findChild(l, "confirmButton").clicked()
        compare(adoptSpy.count, 1)
        compare(adoptSpy.signalArguments[0][0], "g1")
    }

    function test_cancelSendsNothing() {
        const l = list([sendable])
        findChild(l, "discardGroupButton").clicked()
        verify(findChild(l, "confirmRow").visible)
        findChild(l, "cancelButton").clicked()
        verify(!findChild(l, "confirmRow").visible)
        compare(dropSpy.count, 0)
        compare(adoptSpy.count, 0)
    }

    function test_discardAsksThenDiscards() {
        const l = list([sendable])
        findChild(l, "discardGroupButton").clicked()
        verify(findChild(l, "confirmText").text.indexOf("2") >= 0)
        findChild(l, "confirmButton").clicked()
        compare(dropSpy.count, 1)
        compare(dropSpy.signalArguments[0][0], "g1")
    }

    // Another account on the same server (the owner's decision): no way to send, only the hint.
    function test_otherAccountOffersOnlyDiscardAndHint() {
        const l = list([foreign])
        verify(!findChild(l, "adoptButton").visible)
        verify(findChild(l, "discardGroupButton").visible)
        compare(findChild(l, "heldHint").text, "Sign in as Bob to send them.")
        verify(findChild(l, "heldHint").visible)
    }

    function test_groupWithoutNameOffersOnlyDiscardAndTheWayBack() {
        const l = list([orphan])
        compare(findChild(l, "heldGroupTitle").text, "1 change waits on https://b.test")
        verify(!findChild(l, "adoptButton").visible)
        verify(findChild(l, "heldHint").visible)
    }
}
