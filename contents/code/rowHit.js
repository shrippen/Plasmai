.pragma library

/**
 * Hit test for the Plasmoid's right-click catcher, a MouseArea above the whole popup: the
 * Recent row (ActivityListRow, `hasHistoryActions`) under the cursor keeps its entry menu.
 */

/** Topmost row with an entry menu at (x, y) in `item`, or null; `skip` (the catcher) is not searched. */
function historyRowAt(item, x, y, skip) {
    for (var i = item.children.length - 1; i >= 0; i--) {
        var child = item.children[i]
        if (child === skip || !child.visible) {
            continue
        }

        var p = item.mapToItem(child, x, y)
        if (!child.contains(p)) {
            continue
        }
        if (child.hasHistoryActions === true) {
            return child
        }

        var hit = historyRowAt(child, p.x, p.y, skip)
        if (hit) {
            return hit
        }
    }
    return null
}
