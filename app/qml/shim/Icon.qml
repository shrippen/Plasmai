import QtQuick
import QtQuick.Controls as QQC2

// Kirigami Icon shim → Image
Image {
    property string name: ""
    source: name ? "qrc:/qt-project.org/imports/org/kde/kirigami/icons/" + name + ".svg" : ""
    sourceSize.width: width
    sourceSize.height: height
    fillMode: Image.PreserveAspectFit
    asynchronous: true
}
