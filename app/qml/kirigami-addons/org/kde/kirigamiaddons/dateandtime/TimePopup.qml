// SPDX-FileCopyrightText: 2023 Carl Schwan <carl@carlschwan.eu>
// SPDX-License-Identifier: LGPL-2.0-or-later

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import org.kde.kirigamiaddons.components as Components

QQC2.Dialog {
    id: root

    /**
     * @brief The current date and time selected by the user.
     */
    property date value: new Date()

    /**
     * Emitted when the user cancells the popup
     */
    signal cancelled()

    // Plasmai: a new Date, setHours on the property may change only a copy.
    function _keep(hours, minutes) {
        var next = new Date(_value);
        next.setHours(hours, minutes, 0, 0);
        _value = next;
    }

    property date _value: new Date()

    modal: true

    // Plasmai: start from the given time; without a tumbler change Select gave the current time.
    onAboutToShow: _value = new Date(value)

    contentItem: TimePicker {
        id: popupContent
        implicitWidth: applicationWindow().width
        minutes: root.value.getMinutes()
        hours: root.value.getHours()
        onMinutesChanged: root._keep(hours, minutes)
        onHoursChanged: root._keep(hours, minutes)
    }

    background: Components.DialogRoundedBackground {}

    footer: QQC2.DialogButtonBox {
        id: box

        QQC2.Button {
            text: i18ndc("kirigami-addons6", "@action:button", "Cancel")
            icon.name: "dialog-cancel"
            onClicked: {
                root.cancelled()
                root.close()
            }

            QQC2.DialogButtonBox.buttonRole: QQC2.DialogButtonBox.RejectRole
        }

        QQC2.Button {
            text: i18ndc("kirigami-addons6", "@action:button", "Select")
            icon.name: "dialog-ok-apply"
            // Plasmai: the AcceptRole already accepts and closes the dialog;
            // accepting here as well sent accepted twice.
            onClicked: root.value = root._value

            QQC2.DialogButtonBox.buttonRole: QQC2.DialogButtonBox.AcceptRole
        }
    }

    // black background, fades in and out
    QQC2.Overlay.modal: Rectangle {
        color: Qt.rgba(0, 0, 0, 0.3)

        // the opacity of the item is changed internally by QQuickPopup on open/close
        Behavior on opacity {
            OpacityAnimator {
                duration: Kirigami.Units.longDuration
                easing.type: Easing.InOutQuad
            }
        }
    }
}
