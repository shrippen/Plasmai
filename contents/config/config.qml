import QtQuick
import org.kde.plasma.configuration

ConfigModel {
    ConfigCategory {
        name: i18n("Connection")
        icon: "network-connect"
        source: "config/ConfigConnection.qml"
    }
    ConfigCategory {
        name: i18n("Favorites")
        icon: "favorites"
        source: "config/ConfigFavorites.qml"
    }
    ConfigCategory {
        name: i18n("Display")
        icon: "preferences-desktop-display"
        source: "config/ConfigDisplay.qml"
    }
    ConfigCategory {
        name: i18n("Maintenance")
        icon: "tools-wizard"
        source: "config/ConfigMaintenance.qml"
    }
    ConfigCategory {
        name: i18n("Behavior")
        icon: "preferences-system"
        source: "config/ConfigBehavior.qml"
    }
}
