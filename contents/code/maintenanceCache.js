.pragma library

/**
 * Session cache for Maintenance (and reusable entity catalog TTL).
 * Survives tab switches within the same settings / plasmashell process.
 * Widget and System Settings do not share memory with each other.
 */

var _profileId = ""
var _customers = []
var _projects = []
var _activities = []
var _entityFingerprint = ""
var _customerGroups = []
var _projectGroups = []
var _activityGroups = []
var _shiftedCount = 0
var _groupCount = 0
var _settingsKey = ""
var _loadedAt = 0
var _statusText = ""
var _fetching = false

/**
 * Skip the API when the catalog is younger than this.
 * Stale entries are still shown immediately and refreshed in the background.
 */
var FRESH_MS = 10 * 60 * 1000

function entityFingerprint(customers, projects, activities) {
    function pack(list) {
        var parts = []
        for (var i = 0; i < (list || []).length; i++) {
            var item = list[i]
            if (!item || item.id === null || item.id === undefined) {
                continue
            }
            var color = item.color || ""
            parts.push(String(item.id) + "=" + String(color).toLowerCase())
        }
        parts.sort()
        return parts.join(";")
    }
    return "c:" + pack(customers)
        + "|p:" + pack(projects)
        + "|a:" + pack(activities)
}

function hasCatalog(profileId) {
    if (!_loadedAt || String(profileId || "") !== String(_profileId || "")) {
        return false
    }
    return (_customers && _customers.length)
        || (_projects && _projects.length)
        || (_activities && _activities.length)
}

function isFresh(profileId) {
    if (!hasCatalog(profileId)) {
        return false
    }
    return (Date.now() - _loadedAt) < FRESH_MS
}

function ageMs() {
    if (!_loadedAt) {
        return -1
    }
    return Date.now() - _loadedAt
}

function shouldRefresh(profileId, force) {
    if (force) {
        return true
    }
    if (!hasCatalog(profileId)) {
        return true
    }
    return !isFresh(profileId)
}

function groupsMatch(settingsKey) {
    return !!_settingsKey && String(settingsKey || "") === String(_settingsKey)
}

function isFetching() {
    return !!_fetching
}

function setFetching(value) {
    _fetching = !!value
}

function store(profileId, payload) {
    _profileId = String(profileId || "")
    _customers = payload.customers || []
    _projects = payload.projects || []
    _activities = payload.activities || []
    _entityFingerprint = payload.entityFingerprint
        || entityFingerprint(_customers, _projects, _activities)
    _customerGroups = payload.customerGroups || []
    _projectGroups = payload.projectGroups || []
    _activityGroups = payload.activityGroups || []
    _shiftedCount = payload.shiftedCount || 0
    _groupCount = payload.groupCount || 0
    _settingsKey = payload.settingsKey || ""
    _statusText = payload.statusText || ""
    _loadedAt = Date.now()
    _fetching = false
}

/** Store catalog entities only (widget); keep existing groups if fingerprint unchanged. */
function storeEntities(profileId, customers, projects, activities) {
    var fp = entityFingerprint(customers, projects, activities)
    var sameProfile = String(profileId || "") === String(_profileId || "")
    var sameEntities = sameProfile && fp === _entityFingerprint
    _profileId = String(profileId || "")
    _customers = customers || []
    _projects = projects || []
    _activities = activities || []
    if (!sameEntities) {
        _customerGroups = []
        _projectGroups = []
        _activityGroups = []
        _shiftedCount = 0
        _groupCount = 0
        _settingsKey = ""
        _statusText = ""
    }
    _entityFingerprint = fp
    _loadedAt = Date.now()
    _fetching = false
    return !sameEntities
}

function load() {
    return {
        customers: _customers,
        projects: _projects,
        activities: _activities,
        entityFingerprint: _entityFingerprint,
        customerGroups: _customerGroups,
        projectGroups: _projectGroups,
        activityGroups: _activityGroups,
        shiftedCount: _shiftedCount,
        groupCount: _groupCount,
        settingsKey: _settingsKey,
        statusText: _statusText,
        loadedAt: _loadedAt
    }
}

function clear() {
    _profileId = ""
    _customers = []
    _projects = []
    _activities = []
    _entityFingerprint = ""
    _customerGroups = []
    _projectGroups = []
    _activityGroups = []
    _shiftedCount = 0
    _groupCount = 0
    _settingsKey = ""
    _loadedAt = 0
    _statusText = ""
    _fetching = false
}
