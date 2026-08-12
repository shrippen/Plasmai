import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import QtQuick.Window
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents3
import "../code/kimaiApi.js" as KimaiApi
import "."

Item {
    id: root

    property var items: []
    property int currentIndex: -1
    property string placeholderText: ""
    property bool enabled: true
    property int highlightedIndex: -1
    property var sectionTitleMap: ({})
    /**
     * Shared open direction for paired pickers.
     * true = below, false = above. Set by the parent after computing once for both.
     */
    property bool openBelow: true
    /** When set, parent owns direction; otherwise this combo decides alone. */
    property bool useSharedDirection: false

    readonly property var currentItem: (currentIndex >= 0 && currentIndex < items.length) ? items[currentIndex] : null
    readonly property string currentLabel: currentItem ? currentItem.label : ""
    readonly property int minVisibleEntries: TouchUi.pickerMinVisibleEntries
    /** Rows worth of space required before preferring that open direction. */
    readonly property int directionVisibleEntries: TouchUi.pickerDirectionEntries
    readonly property bool popupOpen: popup.opened

    /** Scroll view for measuring visible space inside panel flyouts. */
    property Item viewportItem: null

    signal activated(int index)
    signal aboutToOpen()

    function sectionLabel(section) {
        if (!section) {
            return ""
        }
        if (sectionTitleMap && sectionTitleMap[section]) {
            return sectionTitleMap[section]
        }
        return section
    }

    function sectionColor(section) {
        if (!section) {
            return ""
        }
        for (var i = 0; i < items.length; i++) {
            if (items[i].section === section && items[i].color) {
                return String(items[i].color)
            }
        }
        return ""
    }

    function sectionColorCategory(section) {
        for (var i = 0; i < items.length; i++) {
            if (items[i].section === section && items[i].colorCategory) {
                return String(items[i].colorCategory)
            }
        }
        return ""
    }

    function sectionEntityId(section) {
        for (var i = 0; i < items.length; i++) {
            if (items[i].section === section
                    && items[i].entityId !== null && items[i].entityId !== undefined) {
                return items[i].entityId
            }
        }
        return null
    }

    function closePopup() {
        if (popup.opened) {
            popup.close()
        }
    }

    /**
     * Visible area used for open-direction decisions.
     * Prefer the ScrollView viewport (panel flyout); fall back to the window.
     * Never use Flickable.contentItem — that is the full scrollable content height.
     */
    function spaceBoundsItem() {
        if (viewportItem) {
            return viewportItem
        }
        var win = Window.window
        return (win && win.contentItem) ? win.contentItem : null
    }

    function spaceBelow() {
        var spacing = Kirigami.Units.smallSpacing / 2
        var bounds = spaceBoundsItem()
        if (!bounds) {
            return Number.MAX_VALUE
        }
        var origin = root.mapToItem(bounds, 0, 0)
        var bottomPad = bounds.bottomPadding !== undefined ? bounds.bottomPadding : 0
        return Math.max(0, bounds.height - bottomPad - (origin.y + root.height) - spacing)
    }

    function spaceAbove() {
        var spacing = Kirigami.Units.smallSpacing / 2
        var bounds = spaceBoundsItem()
        if (!bounds) {
            return Number.MAX_VALUE
        }
        var origin = root.mapToItem(bounds, 0, 0)
        var topPad = bounds.topPadding !== undefined ? bounds.topPadding : 0
        return Math.max(0, origin.y - topPad - spacing)
    }

    function idealPopupHeight() {
        return estimatePopupHeight(root.minVisibleEntries)
    }

    function directionThresholdHeight() {
        return estimatePopupHeight(root.directionVisibleEntries)
    }

    function listEntryHeight() {
        return TouchUi.pickerEntryHeight
    }

    function listSectionHeight() {
        return TouchUi.pickerSectionHeight
    }

    implicitHeight: Math.max(field.implicitHeight, TouchUi.controlMinHeight)
    implicitWidth: Kirigami.Units.gridUnit * 12
    Layout.fillWidth: true
    Layout.preferredHeight: implicitHeight

    function filterItems(query) {
        var q = String(query || "").trim().toLowerCase()
        var result = []
        for (var i = 0; i < items.length; i++) {
            var item = items[i]
            var hay = String(item.searchText || item.label || "").toLowerCase()
            if (!q || hay.indexOf(q) !== -1) {
                result.push({
                    sourceIndex: i,
                    label: item.label,
                    section: item.section || "",
                    color: item.rowColor || item.color || "",
                    colorCategory: item.rowColorCategory || item.colorCategory || "",
                    entityId: (item.rowEntityId !== undefined && item.rowEntityId !== null)
                              ? item.rowEntityId
                              : (item.entityId !== undefined ? item.entityId : null),
                    searchText: item.searchText || item.label
                })
            }
        }
        return result
    }

    function estimatePopupHeight(visibleEntryLimit) {
        var entryH = listEntryHeight()
        var sectionH = listSectionHeight()
        var padding = popup.topPadding + popup.bottomPadding + Kirigami.Units.smallSpacing
        var count = filteredModel.length
        if (count === 0) {
            return entryH + padding
        }

        var limit = visibleEntryLimit !== undefined ? visibleEntryLimit : root.minVisibleEntries
        var visible = Math.min(count, limit)
        var visibleSections = 0
        var seenVisible = ({})
        for (var j = 0; j < visible; j++) {
            var s = filteredModel[j].section || ""
            if (s.length > 0 && !seenVisible[s]) {
                seenVisible[s] = true
                visibleSections++
            }
        }

        var estimated = visible * entryH + visibleSections * sectionH + padding
        if (listView.contentHeight > 0 && limit >= root.minVisibleEntries) {
            var full = listView.contentHeight + padding
            if (count <= root.minVisibleEntries) {
                return full
            }
            return Math.min(full, estimated)
        }
        return estimated
    }

    function placePopup() {
        var spacing = Kirigami.Units.smallSpacing / 2
        var idealHeight = estimatePopupHeight()
        var openBelow = root.openBelow
        var available

        if (!root.useSharedDirection) {
            var below = root.spaceBelow()
            var above = root.spaceAbove()
            var threshold = root.directionThresholdHeight()
            if (below >= threshold) {
                openBelow = true
                available = below
            } else if (above >= threshold) {
                openBelow = false
                available = above
            } else {
                openBelow = below >= above
                available = openBelow ? below : above
            }
        } else {
            available = openBelow ? root.spaceBelow() : root.spaceAbove()
        }

        popup.height = Math.max(
            Math.max(field.height, Kirigami.Units.gridUnit * 2),
            Math.min(idealHeight, Math.max(available, Kirigami.Units.gridUnit * 2))
        )
        popup.y = openBelow ? (root.height + spacing) : (-popup.height - spacing)
        popup.width = Math.max(field.width, Kirigami.Units.gridUnit * 14)
    }

    function openPopup() {
        if (!root.enabled) {
            return
        }
        filteredModel = filterItems(field.text === currentLabel ? "" : field.text)
        highlightedIndex = filteredModel.length > 0 ? 0 : -1
        aboutToOpen()
        placePopup()
        popup.open()
        Qt.callLater(placePopup)
        field.forceActiveFocus()
    }

    function selectFiltered(filteredIndex) {
        if (filteredIndex < 0 || filteredIndex >= filteredModel.length) {
            return
        }
        var sourceIndex = filteredModel[filteredIndex].sourceIndex
        currentIndex = sourceIndex
        suppressTextHandler = true
        field.text = items[sourceIndex].label
        suppressTextHandler = false
        popup.close()
        activated(sourceIndex)
    }

    function moveHighlight(delta) {
        if (filteredModel.length === 0) {
            return
        }
        if (!popup.opened) {
            openPopup()
        }
        var next = highlightedIndex + delta
        if (next < 0) {
            next = filteredModel.length - 1
        } else if (next >= filteredModel.length) {
            next = 0
        }
        highlightedIndex = next
        listView.positionViewAtIndex(highlightedIndex, ListView.Contain)
    }

    property var filteredModel: []
    property bool suppressTextHandler: false

    onItemsChanged: {
        if (currentIndex >= items.length) {
            currentIndex = -1
        }
        if (currentIndex >= 0 && currentIndex < items.length) {
            suppressTextHandler = true
            field.text = items[currentIndex].label
            suppressTextHandler = false
        } else if (!popup.opened) {
            suppressTextHandler = true
            field.text = ""
            suppressTextHandler = false
        }
    }

    onCurrentIndexChanged: {
        if (suppressTextHandler) {
            return
        }
        if (currentIndex >= 0 && currentIndex < items.length) {
            suppressTextHandler = true
            field.text = items[currentIndex].label
            suppressTextHandler = false
        }
    }

    QQC2.TextField {
        id: field
        anchors.fill: parent
        enabled: root.enabled
        placeholderText: root.placeholderText
        selectByMouse: true

        onTextEdited: {
            if (root.suppressTextHandler) {
                return
            }
            filteredModel = root.filterItems(text)
            highlightedIndex = filteredModel.length > 0 ? 0 : -1
            if (!popup.opened) {
                root.aboutToOpen()
                popup.open()
            }
            root.placePopup()
            Qt.callLater(root.placePopup)
        }

        onActiveFocusChanged: {
            if (activeFocus && root.enabled) {
                root.openPopup()
                if (text === root.currentLabel) {
                    selectAll()
                }
            }
        }

        Keys.onPressed: function(event) {
            if (event.key === Qt.Key_Down) {
                root.moveHighlight(1)
                event.accepted = true
            } else if (event.key === Qt.Key_Up) {
                root.moveHighlight(-1)
                event.accepted = true
            } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                if (popup.opened && root.highlightedIndex >= 0) {
                    root.selectFiltered(root.highlightedIndex)
                    event.accepted = true
                }
            } else if (event.key === Qt.Key_Escape) {
                popup.close()
                if (root.currentIndex >= 0) {
                    root.suppressTextHandler = true
                    text = root.currentLabel
                    root.suppressTextHandler = false
                }
                event.accepted = true
            }
        }

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton
            propagateComposedEvents: true
            onPressed: function(mouse) {
                mouse.accepted = false
                if (root.enabled) {
                    root.openPopup()
                }
            }
        }
    }

    QQC2.Popup {
        id: popup
        parent: root
        y: field.height + Kirigami.Units.smallSpacing / 2
        width: Math.max(field.width, Kirigami.Units.gridUnit * 14)
        height: Kirigami.Units.gridUnit * 12
        padding: Kirigami.Units.smallSpacing / 2
        closePolicy: QQC2.Popup.CloseOnEscape | QQC2.Popup.CloseOnPressOutsideParent

        onAboutToShow: root.placePopup()
        onOpened: Qt.callLater(root.placePopup)

        contentItem: ListView {
            id: listView
            clip: true
            model: root.filteredModel
            boundsBehavior: Flickable.StopAtBounds
            section.property: "section"
            section.criteria: ViewSection.FullString

            QQC2.ScrollBar.vertical: QQC2.ScrollBar {
                id: pickerScrollBar
                policy: QQC2.ScrollBar.AsNeeded
                width: 4
                padding: 0
                contentItem: Rectangle {
                    implicitWidth: 4
                    radius: 2
                    color: Kirigami.Theme.textColor
                    opacity: pickerScrollBar.pressed ? 0.55
                             : (pickerScrollBar.hovered ? 0.4 : 0.28)
                }
                background: Item {}
            }

            section.delegate: Item {
                width: ListView.view.width
                height: Math.max(sectionRow.implicitHeight, TouchUi.pickerSectionHeight)
                visible: section && section.length > 0

                ColorLabelRow {
                    id: sectionRow
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.leftMargin: Kirigami.Units.smallSpacing
                    anchors.rightMargin: Kirigami.Units.smallSpacing
                    customerRole: true
                    showDot: root.sectionColor(section).length > 0
                    customerColor: root.sectionColor(section) || KimaiApi.DEFAULT_CUSTOMER_COLOR
                    colorCategory: root.sectionColorCategory(section)
                    entityId: root.sectionEntityId(section)
                    label: root.sectionLabel(section)
                }
            }

            delegate: QQC2.ItemDelegate {
                width: ListView.view.width
                height: Math.max(implicitHeight, TouchUi.pickerEntryHeight)
                leftPadding: Kirigami.Units.smallSpacing
                rightPadding: Kirigami.Units.smallSpacing
                topPadding: TouchUi.listRowPadding / 2
                bottomPadding: TouchUi.listRowPadding / 2
                spacing: 0
                highlighted: index === root.highlightedIndex
                onClicked: root.selectFiltered(index)
                onHoveredChanged: {
                    if (hovered) {
                        root.highlightedIndex = index
                    }
                }

                contentItem: ColorLabelRow {
                    width: parent ? parent.width : implicitWidth
                    customerRole: false
                    showDot: modelData.color && String(modelData.color).length > 0
                    customerColor: modelData.color || KimaiApi.DEFAULT_CUSTOMER_COLOR
                    colorCategory: modelData.colorCategory || ""
                    entityId: modelData.entityId !== undefined ? modelData.entityId : null
                    label: modelData.label
                    labelBold: false
                }
            }
        }
    }
}
