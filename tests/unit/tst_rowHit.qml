import QtQuick
import QtTest
import "../../contents/code/rowHit.js" as RowHit

// The Plasmoid's right-click catcher lies above everything; a Recent row under it keeps its menu.
TestCase {
    name: "RowHit"
    width: 300
    height: 300
    // TestCase is invisible by default; the hit test skips invisible items.
    visible: true
    when: windowShown

    Item {
        id: tree
        width: 300
        height: 300

        Column {
            y: 100
            width: 300

            Item {
                id: favoriteRow
                property bool hasHistoryActions: false
                width: 300
                height: 40
            }
            Item {
                id: recentRow
                property bool hasHistoryActions: true
                width: 300
                height: 40

                Text { text: "Label inside the row" }
            }
            Item {
                id: hiddenRow
                property bool hasHistoryActions: true
                visible: false
                width: 300
                height: 40
            }
        }

        Item {
            id: catcher
            anchors.fill: parent
            property bool hasHistoryActions: true
            z: 1000
        }
    }

    function test_findsRecentRow() {
        compare(RowHit.historyRowAt(tree, 10, 150, catcher), recentRow)
    }

    function test_ignoresRowWithoutMenu() {
        compare(RowHit.historyRowAt(tree, 10, 110, catcher), null)
    }

    function test_ignoresEmptySpace() {
        compare(RowHit.historyRowAt(tree, 10, 20, catcher), null)
    }

    function test_skipsCatcher() {
        compare(RowHit.historyRowAt(tree, 10, 20, null), catcher)
    }
}
