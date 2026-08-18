import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents3
import "../code/kimaiApi.js" as KimaiApi
import "../code/timesheetFields.js" as Fields
import "."

/**
 * Searchable multi-tag picker: Kimai tags as inline color pills, optional create.
 */
ColumnLayout {
    id: root

    property var selectedTagEntries: []
    property string kimaiUrl: ""
    property string apiToken: ""
    property bool enabled: true
    property Item pickerViewport: null

    /** Name list for timesheet writes (unchanged API for callers). */
    readonly property var normalizedTags: {
        var names = []
        for (var i = 0; i < selectedTagEntries.length; i++) {
            var entry = selectedTagEntries[i]
            if (entry && entry.name) {
                names.push(entry.name)
            }
        }
        return names
    }

    readonly property int tagRowHeight: Math.round(Kirigami.Units.gridUnit * 2.15)
    readonly property int popupMaxRows: 5

    /** name (lower) -> { name, color } from the last catalog fetch. */
    property var tagCatalog: ({})

    spacing: 0

    function catalogEntry(name) {
        var key = String(name || "").trim().toLowerCase()
        if (!key.length) {
            return null
        }
        return tagCatalog[key] || null
    }

    function entryFromName(name, colorHint) {
        var trimmed = String(name || "").trim()
        if (!trimmed.length) {
            return null
        }
        var cached = catalogEntry(trimmed)
        return {
            name: trimmed,
            color: colorHint || (cached && cached.color)
                     || KimaiApi.tagEntityColor(cached || { name: trimmed })
        }
    }

    function setTags(value) {
        var names = Fields.normalizeTags(value)
        var entries = []
        for (var i = 0; i < names.length; i++) {
            var entry = entryFromName(names[i], "")
            if (entry) {
                entries.push(entry)
            }
        }
        selectedTagEntries = entries
    }

    function addTag(name, colorHint) {
        var entry = entryFromName(name, colorHint)
        if (!entry) {
            return
        }
        var key = entry.name.toLowerCase()
        for (var i = 0; i < selectedTagEntries.length; i++) {
            if (String(selectedTagEntries[i].name).toLowerCase() === key) {
                return
            }
        }
        var next = selectedTagEntries.slice()
        next.push(entry)
        selectedTagEntries = next
        tagCatalog[key] = entry
    }

    function removeTag(name) {
        var key = String(name || "").trim().toLowerCase()
        var next = []
        for (var i = 0; i < selectedTagEntries.length; i++) {
            if (String(selectedTagEntries[i].name).toLowerCase() !== key) {
                next.push(selectedTagEntries[i])
            }
        }
        selectedTagEntries = next
    }

    function ingestCatalogItem(item) {
        var name = KimaiApi.tagEntityName(item)
        if (!name) {
            return null
        }
        var entry = {
            name: name,
            color: KimaiApi.tagEntityColor(item)
        }
        tagCatalog[name.toLowerCase()] = entry
        return entry
    }

    function refreshSuggestions() {
        if (!root.kimaiUrl || !root.apiToken) {
            suggestionModel = []
            return
        }
        loadingSuggestions = true
        KimaiApi.loadTags(root.kimaiUrl, root.apiToken, searchField.text, function(result) {
            loadingSuggestions = false
            if (!result || !result.ok) {
                suggestionModel = []
                return
            }
            var rows = []
            var seen = {}
            var selectedLower = {}
            for (var s = 0; s < root.selectedTagEntries.length; s++) {
                selectedLower[String(root.selectedTagEntries[s].name).toLowerCase()] = true
            }
            var raw = result.data || []
            for (var i = 0; i < raw.length; i++) {
                var entry = root.ingestCatalogItem(raw[i])
                if (!entry) {
                    continue
                }
                var lk = entry.name.toLowerCase()
                if (seen[lk] || selectedLower[lk]) {
                    continue
                }
                seen[lk] = true
                rows.push(entry)
            }
            suggestionModel = rows
        })
    }

    function openSuggestions() {
        root.refreshSuggestions()
        tagPopup.open()
    }

    function popupListHeight() {
        if (root.loadingSuggestions || root.emptyHintVisible) {
            return root.tagRowHeight
        }
        var rows = root.suggestionModel.length
        if (rows === 0) {
            return root.tagRowHeight
        }
        return Math.min(rows, root.popupMaxRows) * root.tagRowHeight
    }

    readonly property bool emptyHintVisible: !root.loadingSuggestions
                                         && root.suggestionModel.length === 0
                                         && searchField.text.trim().length === 0

    property var suggestionModel: []
    property bool loadingSuggestions: false

    readonly property bool canCreateCurrent: {
        var q = searchField.text.trim()
        if (q.length === 0) {
            return false
        }
        var lower = q.toLowerCase()
        for (var i = 0; i < suggestionModel.length; i++) {
            if (String(suggestionModel[i].name).toLowerCase() === lower) {
                return false
            }
        }
        for (var j = 0; j < selectedTagEntries.length; j++) {
            if (String(selectedTagEntries[j].name).toLowerCase() === lower) {
                return false
            }
        }
        return true
    }

    Rectangle {
        id: fieldChrome
        Layout.fillWidth: true
        radius: Kirigami.Units.smallSpacing
        color: Qt.rgba(Kirigami.Theme.textColor.r,
                       Kirigami.Theme.textColor.g,
                       Kirigami.Theme.textColor.b, 0.04)
        border.width: searchField.activeFocus ? 2 : 1
        border.color: searchField.activeFocus
                      ? Kirigami.Theme.highlightColor
                      : Qt.rgba(Kirigami.Theme.textColor.r,
                                Kirigami.Theme.textColor.g,
                                Kirigami.Theme.textColor.b, 0.18)
        implicitHeight: tagFlow.implicitHeight + Kirigami.Units.smallSpacing * 2

        Flow {
            id: tagFlow
            anchors {
                left: parent.left
                right: parent.right
                top: parent.top
                topMargin: Kirigami.Units.smallSpacing
                leftMargin: Kirigami.Units.smallSpacing
                rightMargin: Kirigami.Units.smallSpacing
            }
            spacing: Kirigami.Units.smallSpacing

            Repeater {
                model: root.selectedTagEntries
                delegate: Rectangle {
                    required property var modelData
                    readonly property color pillColor: Qt.color(modelData.color)
                    radius: Kirigami.Units.smallSpacing
                    color: Qt.rgba(Kirigami.Theme.textColor.r,
                                   Kirigami.Theme.textColor.g,
                                   Kirigami.Theme.textColor.b, 0.06)
                    border.width: 1
                    border.color: Qt.rgba(pillColor.r, pillColor.g, pillColor.b, 0.45)
                    implicitWidth: pillRow.implicitWidth + Kirigami.Units.smallSpacing * 2
                    implicitHeight: Math.max(pillRow.implicitHeight + Kirigami.Units.smallSpacing,
                                             searchField.implicitHeight - Kirigami.Units.smallSpacing)

                    TagPill {
                        id: pillRow
                        anchors.centerIn: parent
                        tagName: modelData.name
                        tagColor: pillColor
                        removable: root.enabled
                        onRemoveRequested: root.removeTag(modelData.name)
                    }
                }
            }

            QQC2.TextField {
                id: searchField
                width: Math.max(
                    Kirigami.Units.gridUnit * 8,
                    implicitWidth + Kirigami.Units.smallSpacing * 2)
                enabled: root.enabled
                placeholderText: root.selectedTagEntries.length > 0
                                 ? i18n("Add tag…")
                                 : i18n("Add tags…")
                placeholderTextColor: Qt.rgba(Kirigami.Theme.textColor.r,
                                              Kirigami.Theme.textColor.g,
                                              Kirigami.Theme.textColor.b, 0.45)
                background: Item {}
                Accessible.name: i18n("Tags")
                onActiveFocusChanged: {
                    if (activeFocus) {
                        root.openSuggestions()
                    }
                }
                onTextChanged: {
                    if (tagPopup.opened || activeFocus) {
                        suggestTimer.restart()
                    }
                }
                Keys.onReturnPressed: function(event) {
                    if (root.canCreateCurrent) {
                        root.addTag(text.trim())
                        text = ""
                        event.accepted = true
                    }
                }

                TapHandler {
                    onTapped: root.openSuggestions()
                }
            }
        }

        QQC2.Popup {
            id: tagPopup
            y: fieldChrome.height + 2
            width: Math.max(fieldChrome.width, Kirigami.Units.gridUnit * 14)
            padding: Kirigami.Units.smallSpacing / 2
            modal: false
            focus: false
            closePolicy: QQC2.Popup.CloseOnEscape | QQC2.Popup.CloseOnPressOutsideParent

            readonly property int listHeight: root.popupListHeight()

            contentItem: Column {
                width: parent.width
                spacing: 0

                Item {
                    width: parent.width
                    height: root.loadingSuggestions || root.emptyHintVisible
                            ? root.tagRowHeight : 0
                    visible: height > 0
                    clip: true

                    PlasmaComponents3.Label {
                        anchors.centerIn: parent
                        width: parent.width - Kirigami.Units.smallSpacing * 2
                        horizontalAlignment: Text.AlignHCenter
                        opacity: 0.75
                        font.pointSize: Kirigami.Theme.smallFont.pointSize
                        text: root.loadingSuggestions
                              ? i18n("Loading tags…")
                              : i18n("No tags on the server yet.")
                    }
                }

                ListView {
                    id: listView
                    width: parent.width
                    height: tagPopup.listHeight
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    model: root.suggestionModel
                    spacing: 0
                    visible: !root.loadingSuggestions && !root.emptyHintVisible

                    delegate: QQC2.ItemDelegate {
                        required property var modelData
                        width: listView.width
                        height: root.tagRowHeight
                        padding: Kirigami.Units.smallSpacing
                        onClicked: {
                            root.addTag(modelData.name, modelData.color)
                            searchField.text = ""
                            tagPopup.close()
                        }

                        contentItem: RowLayout {
                            spacing: Kirigami.Units.smallSpacing

                            CustomerColorDot {
                                customerColor: Qt.color(modelData.color)
                                sizeFactor: 0.45
                                Layout.preferredWidth: implicitWidth
                                Layout.preferredHeight: implicitHeight
                                Layout.fillHeight: true
                                Layout.alignment: Qt.AlignVCenter
                            }

                            PlasmaComponents3.Label {
                                Layout.fillWidth: true
                                Layout.preferredWidth: 0
                                text: modelData.name
                                elide: Text.ElideRight
                            }
                        }
                    }
                }

                QQC2.ItemDelegate {
                    id: createRow
                    width: parent.width
                    height: root.canCreateCurrent ? root.tagRowHeight : 0
                    visible: root.canCreateCurrent
                    padding: Kirigami.Units.smallSpacing / 2
                    text: i18n("Create tag “%1”", searchField.text.trim())
                    icon.name: "list-add"
                    enabled: root.enabled
                    onClicked: {
                        root.addTag(searchField.text.trim())
                        searchField.text = ""
                        tagPopup.close()
                    }
                }
            }
        }

        Timer {
            id: suggestTimer
            interval: 220
            repeat: false
            onTriggered: root.refreshSuggestions()
        }
    }
}
