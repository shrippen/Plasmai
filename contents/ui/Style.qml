pragma Singleton
import QtQuick
import org.kde.kirigami as Kirigami

/**
 * Colors, fonts and shapes of the popup views. Every view in contents/ui
 * reads them here instead of Kirigami.Theme, so the visual style is
 * switched in one place (see DESIGN.md "Visual style").
 *
 *   System  the Plasma theme, as before (default)
 *   Kante   opt-in, breaks with Breeze on purpose: shrippen Design Default
 *           (Gruvbox, Rajdhani headings, JetBrains Mono figures, top-right
 *           cut corners). Dark or light ("Leinen") follows the brightness of
 *           the Plasma theme; Plasma still paints the (blurred) popup ground.
 *
 * `kind` is bound from the `visualStyle` setting in main.qml.
 * Settings pages (contents/ui/config) stay on Kirigami.Theme on purpose;
 * they live in Plasma's own configuration dialog.
 */
QtObject {
    id: root

    enum Kind {
        System,
        Kante
    }

    property int kind: Style.Kind.System
    readonly property bool kante: kind === Style.Kind.Kante

    /** The app forces a dark look on Android; Kante follows it there. */
    property bool preferDark: false

    /** Kante follows the theme's brightness: Gruvbox dark or Leinen light. */
    readonly property bool kanteLight: !preferDark && Kirigami.Theme.backgroundColor.hslLightness > 0.5
    readonly property QtObject palette: kanteLight ? leinen : gruvbox

    // shrippen Design Default, dark (tokens/variables.css). Surfaces are
    // tints with alpha: Plasma's blurred popup ground shows through.
    readonly property QtObject gruvbox: QtObject {
        readonly property color text: "#ebdbb2"
        readonly property color strongText: "#fbf1c7"
        readonly property color mutedText: "#bdae93"
        readonly property color disabledText: "#a89984"
        readonly property color ground: "#1d2021"
        readonly property color accent: "#fabd2f"
        readonly property color accentText: "#fabd2f"
        readonly property color accentForeground: "#1d2021"
        readonly property color positive: "#8ec07c"
        readonly property color neutral: "#fe8019"
        readonly property color negative: "#fb4934"
        readonly property color info: "#83a598"
        readonly property color card: Qt.rgba(60 / 255, 56 / 255, 54 / 255, 0.6)
        readonly property color sunken: Qt.rgba(20 / 255, 19 / 255, 18 / 255, 0.5)
        readonly property color frame: Qt.rgba(235 / 255, 219 / 255, 178 / 255, 0.16)
        readonly property color rule: Qt.rgba(235 / 255, 219 / 255, 178 / 255, 0.14)
        readonly property color dialog: Qt.rgba(40 / 255, 40 / 255, 40 / 255, 0.97)
    }

    // Light theme "Leinen": darkened semantic colors so text pairs reach WCAG AA.
    readonly property QtObject leinen: QtObject {
        readonly property color text: "#3c3836"
        readonly property color strongText: "#282828"
        readonly property color mutedText: "#665c54"
        readonly property color disabledText: "#7c6f64"
        readonly property color ground: "#f0e9d6"
        readonly property color accent: "#d79921"
        readonly property color accentText: "#8a5a00"
        readonly property color accentForeground: "#282828"
        readonly property color positive: "#427b58"
        readonly property color neutral: "#af3a03"
        readonly property color negative: "#9d0006"
        readonly property color info: "#076678"
        readonly property color card: Qt.rgba(251 / 255, 248 / 255, 238 / 255, 0.7)
        readonly property color sunken: Qt.rgba(230 / 255, 222 / 255, 198 / 255, 0.6)
        readonly property color frame: Qt.rgba(60 / 255, 56 / 255, 54 / 255, 0.18)
        readonly property color rule: Qt.rgba(60 / 255, 56 / 255, 54 / 255, 0.14)
        readonly property color dialog: Qt.rgba(247 / 255, 242 / 255, 228 / 255, 0.98)
    }

    // ── Theme roles (both styles) ────────────────────────────────────────
    readonly property color textColor: kante ? palette.text : Kirigami.Theme.textColor
    readonly property color disabledTextColor: kante ? palette.disabledText : Kirigami.Theme.disabledTextColor
    readonly property color backgroundColor: kante ? palette.ground : Kirigami.Theme.backgroundColor
    readonly property color highlightColor: kante ? palette.accent : Kirigami.Theme.highlightColor
    readonly property color positiveTextColor: kante ? palette.positive : Kirigami.Theme.positiveTextColor
    readonly property color neutralTextColor: kante ? palette.neutral : Kirigami.Theme.neutralTextColor
    readonly property color negativeTextColor: kante ? palette.negative : Kirigami.Theme.negativeTextColor

    readonly property font defaultFont: Kirigami.Theme.defaultFont
    readonly property font smallFont: Kirigami.Theme.smallFont

    // Customer, project or tag without a color from the tracker.
    readonly property color entityFallbackColor: "#d2d6de"

    // Bars of charts without per-entity colors (time by hour).
    readonly property color chartColor: kante ? palette.info : "#3584e4"

    // ── Surfaces (System values match today's look where they are shared) ──
    readonly property color strongTextColor: kante ? palette.strongText : Kirigami.Theme.textColor
    readonly property color mutedTextColor: kante ? palette.mutedText : tint(Kirigami.Theme.textColor, 0.75)
    /** Fill of primary buttons and accent bars; the timer digits use accentTextColor. */
    readonly property color accentColor: kante ? palette.accent : Kirigami.Theme.highlightColor
    readonly property color accentTextColor: kante ? palette.accentText : Kirigami.Theme.positiveTextColor
    readonly property color accentForegroundColor: kante ? palette.accentForeground : Kirigami.Theme.highlightedTextColor
    readonly property color infoColor: kante ? palette.info : Kirigami.Theme.linkColor
    readonly property color cardColor: kante ? palette.card : tint(Kirigami.Theme.textColor, 0.04)
    readonly property color sunkenColor: kante ? palette.sunken : tint(Kirigami.Theme.textColor, 0.06)
    readonly property color frameColor: kante ? palette.frame : tint(Kirigami.Theme.textColor, 0.12)
    readonly property color ruleColor: kante ? palette.rule : tint(Kirigami.Theme.textColor, 0.12)
    readonly property color dialogColor: kante ? palette.dialog : Kirigami.Theme.backgroundColor

    /** Top-right corner cut of Kante cards (px); 0 in the System style. */
    readonly property int chamfer: kante ? Math.round(Kirigami.Units.gridUnit * 0.8) : 0
    readonly property int smallChamfer: kante ? Math.round(Kirigami.Units.gridUnit * 0.5) : 0

    function tint(c, alpha) {
        return Qt.rgba(c.r, c.g, c.b, alpha)
    }

    // ── Fonts ────────────────────────────────────────────────────────────
    // Bundled (SIL OFL, contents/fonts/OFL.txt); loaded for the process only.
    readonly property FontLoader headingFace: FontLoader { source: "../fonts/Rajdhani-700.ttf" }
    readonly property FontLoader monoFace: FontLoader { source: "../fonts/JetBrainsMono-400.ttf" }
    readonly property FontLoader monoMediumFace: FontLoader { source: "../fonts/JetBrainsMono-500.ttf" }

    readonly property string monoFamily: kante ? monoFace.font.family : "monospace"

    /** Uppercase heading (Kante: Rajdhani Bold); System: the default font, bold. */
    function headingFont(pointSize) {
        if (!kante) {
            return Qt.font({ family: defaultFont.family, pointSize: pointSize, bold: true })
        }
        return Qt.font({
            family: headingFace.font.family,
            pointSize: pointSize,
            weight: Font.Bold,
            capitalization: Font.AllUppercase,
            letterSpacing: pointSize * 0.08
        })
    }

    /** Figures (timer, durations, times): JetBrains Mono in Kante, "monospace" otherwise. */
    function monoFont(pointSize, bold) {
        if (!kante) {
            return Qt.font({ family: "monospace", pointSize: pointSize, bold: !!bold })
        }
        return Qt.font({
            family: (bold ? monoMediumFace : monoFace).font.family,
            pointSize: pointSize,
            weight: bold ? Font.Medium : Font.Normal
        })
    }

    /** Small uppercase label with letter spacing (section titles, field labels). */
    function labelFont() {
        if (!kante) {
            return smallFont
        }
        var size = Math.max(7, smallFont.pointSize * 0.9)
        return Qt.font({
            family: monoFace.font.family,
            pointSize: size,
            capitalization: Font.AllUppercase,
            letterSpacing: size * 0.14
        })
    }
}
