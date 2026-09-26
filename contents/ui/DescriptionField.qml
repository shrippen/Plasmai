import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Shapes
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents3
import "."

/**
 * Description of the running entry with its save button (saving, saved
 * check, dirty state). Shared by both timer cards; state and actions live
 * in the widget root (main.qml).
 */
Item {
    id: descriptionFieldWrap

    // Widget root (main.qml): state and actions.
    required property var widget

    // Avoid anchors.fill ↔ implicitHeight feedback (zero-height field).
    height: descriptionEdit.implicitHeight
    implicitHeight: descriptionEdit.implicitHeight

    PTextField {
        id: descriptionEdit
        width: parent.width
        enabled: !widget.savingDescription
        placeholderText: i18n("Description")
        rightPadding: descriptionSaveButton.visible
            ? descriptionSaveButton.width + Kirigami.Units.smallSpacing * 2
            : leftPadding

        function applyDraftFromRoot() {
            if (text === widget.descriptionDraft) {
                return
            }
            widget.suppressDescHandler = true
            text = widget.descriptionDraft
            widget.suppressDescHandler = false
        }

        Connections {
            target: widget
            function onDescriptionDraftChanged() {
                descriptionEdit.applyDraftFromRoot()
            }
        }

        Component.onCompleted: applyDraftFromRoot()
        onVisibleChanged: {
            if (visible) {
                applyDraftFromRoot()
            }
        }

        onActiveFocusChanged: {
            widget.descriptionFieldFocused = activeFocus
        }

        onTextChanged: {
            if (widget.suppressDescHandler) {
                return
            }
            widget.descriptionDraft = text
            widget.descriptionDirty = (text !== widget.currentDescription)
            if (widget.descriptionDirty && widget.descriptionSavedFlash) {
                widget.cancelDescriptionSavedFlash()
            }
        }

        onAccepted: widget.saveCurrentDescription()
        Keys.onPressed: function(event) {
            if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                widget.saveCurrentDescription()
                event.accepted = true
            } else if (event.key === Qt.Key_Escape) {
                widget.syncDescriptionField(widget.currentDescription)
                event.accepted = true
            }
        }
    }

    PToolButton {
        id: descriptionSaveButton
        z: 10
        anchors.right: parent.right
        anchors.rightMargin: Kirigami.Units.smallSpacing / 2
        anchors.verticalCenter: descriptionEdit.verticalCenter
        width: Math.round(Kirigami.Units.iconSizes.small * 1.55)
        height: width
        padding: 0
        display: QQC2.AbstractButton.IconOnly
        icon.width: Kirigami.Units.iconSizes.small
        icon.height: Kirigami.Units.iconSizes.small
        icon.name: widget.descriptionSavedFlash
                   ? ""
                   : (widget.savingDescription ? "view-refresh"
                      : "document-save")
        text: i18n("Save description")
        opacity: widget.descriptionSavedFlash
                 ? widget.descriptionSaveFlashOpacity
                 : 1
        visible: widget.descriptionSavedFlash
                 || widget.savingDescription
                 || widget.descriptionDirty
        enabled: widget.descriptionDirty
                 && !widget.savingDescription
                 && !widget.descriptionSavedFlash
        onClicked: widget.saveCurrentDescription()
        PlasmaComponents3.ToolTip.text: text
        PlasmaComponents3.ToolTip.visible: hovered
        PlasmaComponents3.ToolTip.delay: Kirigami.Units.toolTipDelay

        Rectangle {
            visible: widget.descriptionSavedFlash
            anchors.centerIn: parent
            width: Kirigami.Units.iconSizes.small
            height: width
            radius: width / 2
            color: Qt.rgba(widget.descriptionSaveMutedColor.r,
                           widget.descriptionSaveMutedColor.g,
                           widget.descriptionSaveMutedColor.b, 0.18)
            border.width: 1
            border.color: widget.descriptionSaveMutedColor
        }

        // Theme icons ignore Kirigami.Icon.color; paint the check ourselves.
        Shape {
            id: descriptionSaveCheck
            visible: widget.descriptionSavedFlash
            anchors.centerIn: parent
            width: Kirigami.Units.iconSizes.small
            height: width
            preferredRendererType: Shape.CurveRenderer

            ShapePath {
                fillColor: widget.descriptionSaveSuccessColor
                strokeWidth: 0
                scale: Qt.size(descriptionSaveCheck.width / 16,
                               descriptionSaveCheck.height / 16)
                PathSvg {
                    path: "M13.273 3.5 5.637 11.061 2.727 8.18 2 8.9l2.908 2.879.729.721 1.09-1.08L14 4.221z"
                }
            }
        }
    }
}
