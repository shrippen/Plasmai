pragma Singleton
import QtQuick

/**
 * ColorDistinct.js's maps live in `.pragma library` module state, which QML's
 * binding system cannot observe directly. Color computation runs off the GUI
 * thread (see platform/colorWorker.js) and applies its result to that module
 * state asynchronously, so bindings that read ColorDistinct.adjust(...) (in
 * CustomerColorDot) need an explicit, observable trigger to know a new result
 * landed. Bump `version` whenever main.qml applies a fresh result; anything
 * reading `version` inside its binding expression re-evaluates automatically.
 */
QtObject {
    property int version: 0
}
