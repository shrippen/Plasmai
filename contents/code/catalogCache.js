.pragma library

/**
 * Session cache for the entity catalog (customers, projects, activities).
 * Survives tab switches within the same settings / plasmashell process.
 * Widget and System Settings do not share memory with each other.
 */

var _profileId = ""
var _customers = []
var _projects = []
var _activities = []
var _loadedAt = 0
var _fetching = false

/**
 * Skip the API when the catalog is younger than this.
 * Stale entries are still shown immediately and refreshed in the background.
 */
var FRESH_MS = 10 * 60 * 1000

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
    _loadedAt = payload.loadedAt || Date.now()
    _fetching = false
}

/** Restore from disk / another process. Preserves original loadedAt for TTL. */
function hydrate(payload) {
    if (!payload) {
        return false
    }
    store(payload.profileId, payload)
    return hasCatalog(_profileId)
}

function exportPayload() {
    return {
        profileId: _profileId,
        customers: _customers,
        projects: _projects,
        activities: _activities,
        loadedAt: _loadedAt
    }
}

function storeEntities(profileId, customers, projects, activities) {
    store(profileId, {
        customers: customers,
        projects: projects,
        activities: activities
    })
}

function load() {
    return {
        customers: _customers,
        projects: _projects,
        activities: _activities,
        loadedAt: _loadedAt
    }
}

function clear() {
    _profileId = ""
    _customers = []
    _projects = []
    _activities = []
    _loadedAt = 0
    _fetching = false
}
