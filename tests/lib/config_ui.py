"""AT-SPI helpers for the Plasmai Display settings dialog (EN + DE)."""

from __future__ import annotations

# Plasma chrome (i18nd from plasma_shell) plus applet i18n.
APPLY = ["Apply", "Anwenden"]
OK = ["OK"]
DISPLAY_TAB = ["Display", "Anzeige"]
FAVORITES_TAB = ["Favorites", "Favoriten"]
CONNECTION_TAB = ["Connection", "Verbindung"]
LOADING_PROJECTS = [
    "Loading projects",
    "Loading projects…",
    "Projekte werden geladen…",
]
CONFIGURE = [
    "Configure Plasmai",
    "Plasmai einrichten",
    "Configure",
    "Einrichten",
    "Configure…",
    "Configure...",
    "Einstellungen",
    "Plasmai konfigurieren",
]

CHECKBOX_ROLES = {"check box", "checkbox", "toggle button"}
TAB_ROLES = {
    "page tab",
    "push button",
    "list item",
    "toggle button",
    "radio button",
    "menu item",
}
BUTTON_ROLES = {"push button", "button"}

# Unique-enough checkbox labels on the Display page (panel / flyout / desktop).
# Duplicate labels (Favorites, Day sparkline) click the first showing match.
DISPLAY_OPTIONS: dict[str, list[str]] = {
    "elapsed": ["Elapsed time", "Vergangene Zeit"],
    "project": ["Project name", "Projektname"],
    "activity": ["Activity name", "Tätigkeitsname"],
    "customer_pill": ["Customer color pill", "Kundenfarbe-Pille", "Kundenfarb-Pille"],
    "project_pill": ["Project color pill", "Projektfarbe-Pille", "Projektfarb-Pille"],
    "popup_summary": [
        "Work summary (today / week / remaining)",
        "Arbeitsübersicht (heute / Woche / Rest)",
    ],
    "popup_continue": ["Continue last activity", "Letzte Tätigkeit fortsetzen"],
    "desktop_new": [
        "New activity picker",
        "Auswahl für neue Tätigkeit",
        "Neue-Tätigkeit-Auswahl",
    ],
}

# Manual entry / running-edit extras (EN + DE).
BILLABLE = ["Billable", "Abrechenbar"]
TAGS = ["Add tags…", "Add tag…", "Tags", "Tags (comma-separated)", "Tags (kommagetrennt)"]
ADD_ENTRY = ["Add entry", "Eintrag hinzufügen"]
