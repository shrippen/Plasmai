import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents3

/**
 * Tag chip: Kimai color dot + name. Optional remove on click when removable.
 */
Item {
    id: root

    property string tagName: ""
    property color tagColor: "#d2d6de"
    property bool removable: false

    signal removeRequested()

    implicitWidth: row.implicitWidth
    implicitHeight: row.implicitHeight

    RowLayout {
        id: row
        anchors.fill: parent
        spacing: Kirigami.Units.smallSpacing

        CustomerColorDot {
            customerColor: root.tagColor
            sizeFactor: 0.45
            Layout.preferredWidth: implicitWidth
            Layout.preferredHeight: implicitHeight
            Layout.fillHeight: true
            Layout.alignment: Qt.AlignVCenter
        }

        PlasmaComponents3.Label {
            Layout.preferredWidth: implicitWidth
            Layout.maximumWidth: Kirigami.Units.gridUnit * 12
            text: root.tagName
            elide: Text.ElideRight
        }
    }

    MouseArea {
        anchors.fill: parent
        enabled: root.removable
        cursorShape: root.removable ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: root.removeRequested()
    }
}
