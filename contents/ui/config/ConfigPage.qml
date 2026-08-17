import QtQuick

/**
 * Root for settings pages that do not alias controls to cfg_*.
 * Plasma injects every main.xml key as cfg_* (plus cfg_*Default and title).
 * Declaring them here stops journal spam; unused keys are written back as
 * the values Plasma just loaded.
 */
ConfigPageBase {
    property var cfg_kimaiUrl
    property var cfg_kimaiUrlDefault
    property var cfg_profilesJson
    property var cfg_profilesJsonDefault
    property var cfg_activeProfileId
    property var cfg_activeProfileIdDefault
    property var cfg_refreshInterval
    property var cfg_refreshIntervalDefault
    property var cfg_recentCount
    property var cfg_recentCountDefault
    property var cfg_useBlurBackground
    property var cfg_useBlurBackgroundDefault
    property var cfg_workDayBegin
    property var cfg_workDayBeginDefault
    property var cfg_workDayEnd
    property var cfg_workDayEndDefault
    property var cfg_latitude
    property var cfg_latitudeDefault
    property var cfg_longitude
    property var cfg_longitudeDefault
    property var cfg_popupShowSparkline
    property var cfg_popupShowSparklineDefault
    property var cfg_desktopShowSparkline
    property var cfg_desktopShowSparklineDefault
    property var cfg_showSparklineArcs
    property var cfg_showSparklineArcsDefault
    property var cfg_showElapsedInPanel
    property var cfg_showElapsedInPanelDefault
    property var cfg_showProjectInPanel
    property var cfg_showProjectInPanelDefault
    property var cfg_showActivityInPanel
    property var cfg_showActivityInPanelDefault
    property var cfg_showCustomerColorInPanel
    property var cfg_showCustomerColorInPanelDefault
    property var cfg_showProjectColorInPanel
    property var cfg_showProjectColorInPanelDefault
    property var cfg_popupShowWorkSummary
    property var cfg_popupShowWorkSummaryDefault
    property var cfg_popupShowFavorites
    property var cfg_popupShowFavoritesDefault
    property var cfg_popupShowRecent
    property var cfg_popupShowRecentDefault
    property var cfg_popupShowContinue
    property var cfg_popupShowContinueDefault
    property var cfg_popupShowNewActivity
    property var cfg_popupShowNewActivityDefault
    property var cfg_desktopShowWorkSummary
    property var cfg_desktopShowWorkSummaryDefault
    property var cfg_desktopShowFavorites
    property var cfg_desktopShowFavoritesDefault
    property var cfg_desktopShowRecent
    property var cfg_desktopShowRecentDefault
    property var cfg_desktopShowNewActivity
    property var cfg_desktopShowNewActivityDefault
    property var cfg_showFavorites
    property var cfg_showFavoritesDefault
    property var cfg_confirmBeforeStop
    property var cfg_confirmBeforeStopDefault
    property var cfg_pinnedActivities
    property var cfg_pinnedActivitiesDefault
    property var cfg_idleStopEnabled
    property var cfg_idleStopEnabledDefault
    property var cfg_idleStopMinutes
    property var cfg_idleStopMinutesDefault
    property var cfg_notifyOnStart
    property var cfg_notifyOnStartDefault
    property var cfg_notifyOnStop
    property var cfg_notifyOnStopDefault
    property var cfg_notifyOnIdleStop
    property var cfg_notifyOnIdleStopDefault
    property var cfg_locationName
    property var cfg_locationNameDefault
    property var cfg_colorDistinctionEnabled
    property var cfg_colorDistinctionEnabledDefault
    property var cfg_colorSimilarityPercent
    property var cfg_colorSimilarityPercentDefault
    property var cfg_touchMode
    property var cfg_touchModeDefault
}
