import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Shapes
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents3
import "Kante"
import "KantePlasma"

/**
 * Description of the running entry with its save button (saving, saved
 * check, dirty state). Shared by both timer cards; the text is the
 * session timer's draft, saved on Enter or the button.
 */
Item {
    id: descriptionFieldWrap

    // The session layer (Session.qml): data and actions.
    required property QtObject session
    // Widget root (main.qml): view state only (the saved flash).
    required property var view

    // Avoid anchors.fill ↔ implicitHeight feedback (zero-height field).
    height: descriptionEdit.implicitHeight
    implicitHeight: descriptionEdit.implicitHeight

    KanteTextField {
        id: descriptionEdit
        width: parent.width
        enabled: !session.timer.savingDescription
        placeholderText: i18n("Description")
        rightPadding: descriptionSaveButton.visible
            ? descriptionSaveButton.width + Kirigami.Units.smallSpacing * 2
            : leftPadding

        /** Typed, not saved yet. */
        readonly property bool dirty: session.timer.draft !== session.timer.description
        /** Set while the draft is written into the field (no echo back). */
        property bool applying: false

        function applyDraft() {
            if (text === session.timer.draft) {
                return
            }
            applying = true
            text = session.timer.draft
            applying = false
        }

        Connections {
            target: descriptionFieldWrap.session.timer
            function onDraftChanged() {
                descriptionEdit.applyDraft()
            }
        }

        Component.onCompleted: applyDraft()
        onVisibleChanged: {
            if (visible) {
                applyDraft()
            }
        }

        onTextChanged: {
            if (applying) {
                return
            }
            session.timer.setDraft(text)
            if (descriptionEdit.dirty && view.descriptionSavedFlash) {
                view.cancelDescriptionSavedFlash()
            }
        }

        onAccepted: view.saveCurrentDescription()
        Keys.onPressed: function(event) {
            if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                view.saveCurrentDescription()
                event.accepted = true
            } else if (event.key === Qt.Key_Escape) {
                session.timer.setDraft(session.timer.description)
                event.accepted = true
            }
        }
    }

    KantePlasmaToolButton {
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
        icon.name: view.descriptionSavedFlash
                   ? ""
                   : (session.timer.savingDescription ? "view-refresh"
                      : "document-save")
        text: i18n("Save description")
        opacity: view.descriptionSavedFlash
                 ? view.descriptionSaveFlashOpacity
                 : 1
        visible: view.descriptionSavedFlash
                 || session.timer.savingDescription
                 || descriptionEdit.dirty
        enabled: descriptionEdit.dirty
                 && !session.timer.savingDescription
                 && !view.descriptionSavedFlash
        onClicked: view.saveCurrentDescription()
        PlasmaComponents3.ToolTip.text: text
        PlasmaComponents3.ToolTip.visible: hovered
        PlasmaComponents3.ToolTip.delay: Kirigami.Units.toolTipDelay

        Rectangle {
            visible: view.descriptionSavedFlash
            anchors.centerIn: parent
            width: Kirigami.Units.iconSizes.small
            height: width
            radius: width / 2
            color: KanteStyle.tint(view.descriptionSaveMutedColor, 0.18)
            border.width: 1
            border.color: view.descriptionSaveMutedColor
        }

        // Theme icons ignore Kirigami.Icon.color; paint the check ourselves.
        Shape {
            id: descriptionSaveCheck
            visible: view.descriptionSavedFlash
            anchors.centerIn: parent
            width: Kirigami.Units.iconSizes.small
            height: width
            preferredRendererType: Shape.CurveRenderer

            ShapePath {
                fillColor: view.descriptionSaveSuccessColor
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
