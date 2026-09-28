import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import "../contents/code/buildInfo.js" as BuildInfo
import "Kante"

Kirigami.Page {
    id: page
    KantePageTitle { page: page }
    title: i18n("About")

    readonly property string repoUrl: "https://github.com/shrippen/Plasmai"
    readonly property string websiteUrl: "https://shrippen.github.io/"

    QQC2.ScrollView {
        id: pageScroll
        anchors.fill: parent
        // The scroll bar sits at the screen edge; the content keeps the page margin.
        anchors.rightMargin: -page.rightPadding
        contentWidth: availableWidth
        QQC2.ScrollBar.horizontal.policy: QQC2.ScrollBar.AlwaysOff

        ColumnLayout {
            id: content
            width: Math.min((pageScroll.availableWidth - page.rightPadding), Kirigami.Units.gridUnit * 28)
            x: Math.max(0, ((pageScroll.availableWidth - page.rightPadding) - width) / 2)
            spacing: Kirigami.Units.largeSpacing

            RowLayout {
                Layout.fillWidth: true
                spacing: Kirigami.Units.largeSpacing

                Image {
                    source: "qrc:/qml/icons/plasmai.png"
                    sourceSize.width: Kirigami.Units.iconSizes.huge
                    sourceSize.height: Kirigami.Units.iconSizes.huge
                    Layout.preferredWidth: Kirigami.Units.iconSizes.huge
                    Layout.preferredHeight: Kirigami.Units.iconSizes.huge
                    smooth: true
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Kirigami.Units.smallSpacing
                    KanteHeading {
                        Layout.fillWidth: true
                        level: 1
                        pageTitle: true
                        text: "Plasmai"
                    }
                    QQC2.Label {
                        Layout.fillWidth: true
                        font.family: KanteStyle.active ? KanteStyle.monoFamily : Kirigami.Theme.defaultFont.family
                        opacity: 0.7
                        text: i18n("Version %1", BuildInfo.VERSION)
                    }
                }
            }

            QQC2.Label {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                text: i18n("Track time with Kimai, Clockify, Toggl Track, or SolidTime")
            }

            QQC2.Label {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                font.pointSize: KanteStyle.smallFont.pointSize
                opacity: 0.7
                text: i18n("License: %1", "GPL-3.0-or-later")
            }

            KanteHeading {
                Layout.fillWidth: true
                Layout.topMargin: Kirigami.Units.largeSpacing
                level: 4
                text: i18n("Links")
            }

            Repeater {
                model: [
                    { label: i18n("Source code"), url: page.repoUrl },
                    { label: i18n("More projects"), url: page.websiteUrl }
                ]
                delegate: ColumnLayout {
                    required property var modelData
                    Layout.fillWidth: true
                    spacing: 0
                    KanteButton {
                        text: modelData.label
                        onClicked: Qt.openUrlExternally(modelData.url)
                    }
                    QQC2.Label {
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                        font.pointSize: KanteStyle.smallFont.pointSize
                        opacity: 0.7
                        text: modelData.url.replace(/^https:\/\//, "").replace(/\/$/, "")
                    }
                }
            }
        }
    }
}
