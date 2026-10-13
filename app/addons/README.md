Vendored from KDE kirigami-addons v1.6.0 (LGPL-2.0-or-later / BSD-2-Clause):
`dateandtime` (C++ models here, QML under qml/kirigami-addons/), plus the
`components` (DialogRoundedBackground, SegmentedButton) and `delegates`
QML types it depends on. Vendored instead of linked so the Android build
needs no full kirigami-addons cross-build (KF6 Config/GuiAddons/I18n).

Local changes (marked "Plasmai:" in the files):
- `dateandtime/TimePicker.qml`: 12-hour locales are found by any am/pm
  marker ("h:mm a", not only "AP"); 12:xx is PM and shows as 12; AM/PM
  sets the half instead of flipping it.
- `dateandtime/TimePopup.qml`: starts from `value` (Select without a
  change gave the current time) and accepts once (Select emitted
  `accepted` twice).
