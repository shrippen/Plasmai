import QtQuick
import org.kde.kirigami as Kirigami
import "."

/**
 * Kante look for a Kirigami.InlineMessage: place inside it. Square callout
 * tinted with the message type's color (shrippen .callout). Nothing in the
 * System style.
 */
Item {
    id: skin

    required property var message

    visible: false

    readonly property color tone: {
        if (!message) {
            return Style.infoColor
        }
        switch (message.type) {
        case Kirigami.MessageType.Error:
            return Style.negativeTextColor
        case Kirigami.MessageType.Warning:
            return Style.neutralTextColor
        case Kirigami.MessageType.Positive:
            return Style.positiveTextColor
        default:
            return Style.infoColor
        }
    }

    // Not a child: only handed to `background` while Kante is on.
    readonly property Item kanteBackground: Rectangle {
        color: Style.tint(skin.tone, 0.14)
        border.width: 1
        border.color: Style.tint(skin.tone, 0.55)
    }

    Binding {
        target: skin.message
        property: "background"
        value: skin.kanteBackground
        when: Style.kante && skin.message !== null
        restoreMode: Binding.RestoreBindingOrValue
    }
}
