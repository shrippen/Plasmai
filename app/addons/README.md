Vendored from KDE kirigami-addons v1.6.0 (LGPL-2.0-or-later / BSD-2-Clause):
`dateandtime` (C++ models here, QML under qml/kirigami-addons/), plus the
`components` (DialogRoundedBackground, SegmentedButton) and `delegates`
QML types it depends on. Vendored instead of linked so the Android build
needs no full kirigami-addons cross-build (KF6 Config/GuiAddons/I18n).
