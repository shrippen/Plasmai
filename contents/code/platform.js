.pragma library

/**
 * Backend-agnostic Promise facade.
 * Call setBackend() once with an object implementing the raw storage
 * interface; all public methods delegate to it via Promises.
 */
.import "sharedConfig.js" as SharedConfig

var _backend = null

function setBackend(backend) {
    _backend = backend
    _savedCatalogText = ""
}

// -- Token (kwallet / qtkeychain / …)

function loadToken(dataSource, profileId) {
    return new Promise(function(resolve, reject) {
        _backend.loadToken(dataSource, profileId,
            function(token, err) {
                if (err) { reject(err) } else { resolve(token) }
            })
    })
}

function saveToken(dataSource, profileId, token) {
    return new Promise(function(resolve, reject) {
        _backend.saveToken(dataSource, profileId, token,
            function(ok, err) {
                if (!ok) { reject(err) } else { resolve(true) }
            })
    })
}

function clearToken(dataSource, profileId) {
    return new Promise(function(resolve, reject) {
        _backend.clearToken(dataSource, profileId,
            function(ok, err) {
                if (!ok) { reject(err) } else { resolve(true) }
            })
    })
}

// -- System check (first-start wizard)

/**
 * What blocks or limits Plasmai here, as setupWizard.js assess() reads it.
 * Backends without a check (the app: QtKeychain needs nothing installed) give {}.
 */
function checkSystem(dataSource) {
    return new Promise(function(resolve) {
        if (!_backend.checkSystem) {
            resolve({})
            return
        }
        _backend.checkSystem(dataSource, function(result) { resolve(result || {}) })
    })
}

// -- Idle detection

function checkIdle(dataSource) {
    return new Promise(function(resolve, reject) {
        _backend.runIdle(dataSource,
            function(idleMs, err) {
                if (err) { reject(err) } else { resolve(idleMs) }
            })
    })
}

// -- Notifications

function sendNotification(dataSource, summary, body) {
    return new Promise(function(resolve) {
        _backend.notify(dataSource, summary, body,
            function() { resolve(true) })
    })
}

// -- Shared config (~/.config/…/shared.json)

function loadShared(dataSource) {
    return new Promise(function(resolve) {
        _backend.loadSharedConfig(dataSource,
            function(shared) { resolve(shared) })
    })
}

function saveShared(dataSource, sharedObj) {
    return new Promise(function(resolve, reject) {
        _backend.saveSharedConfig(dataSource, sharedObj,
            function(ok, err) {
                if (!ok) { reject(err) } else { resolve(true) }
            })
    })
}

// One read-modify-write of shared.json at a time (see secret.js).
var _sharedChain = null

/**
 * Load shared.json, merge patch, save. With `bases` ({ key: json last seen }),
 * data-map keys (SharedConfig.DATA_MAP_KEYS) are three-way merged onto the
 * file (B9). Resolves with the patch that was written.
 */
function patchShared(dataSource, configuration, patch, bases) {
    function run() {
        return new Promise(function(resolve, reject) {
            _backend.loadSharedConfig(dataSource, function(existing) {
                var base = existing || SharedConfig.fromConfiguration(configuration)
                base = SharedConfig.sanitizeProfilesForPersistence(base, configuration)
                var effective = bases ? SharedConfig.mergeDataPatch(base, bases, patch || {}) : (patch || {})
                var shared = SharedConfig.merge(base, effective)
                // Nothing new (startup patches mostly repeat the file): no write.
                if (existing && JSON.stringify(shared) === JSON.stringify(existing)) {
                    resolve(effective)
                    return
                }
                _backend.saveSharedConfig(dataSource, shared,
                    function(ok, err) {
                        if (!ok) { reject(err) } else { resolve(effective) }
                    })
            })
        })
    }
    var p = _sharedChain ? _sharedChain.then(run, run) : run()
    _sharedChain = p.then(function() {}, function() {})
    return p
}

// -- Catalog cache (projects / activities / colors)

function loadCatalog(dataSource) {
    return new Promise(function(resolve) {
        _backend.loadCatalogCache(dataSource,
            function(payload) { resolve(payload || null) })
    })
}

function loadCatalogText(dataSource) {
    return new Promise(function(resolve) {
        _backend.loadCatalogCacheText(dataSource,
            function(text) { resolve(text || "") })
    })
}

/** The last payload written: the same one again is not written. */
var _savedCatalogText = ""

function saveCatalog(dataSource, payload) {
    var text = JSON.stringify(payload)
    if (text === _savedCatalogText) {
        return Promise.resolve(true)
    }
    return new Promise(function(resolve, reject) {
        _backend.saveCatalogCache(dataSource, payload,
            function(ok, err) {
                if (!ok) { reject(err) } else { _savedCatalogText = text; resolve(true) }
            })
    })
}

// -- Client-private files (offline snapshot, outbox; not shared with the other client)

function loadLocal(dataSource, name) {
    return new Promise(function(resolve) {
        _backend.loadLocal(dataSource, name, function(payload) { resolve(payload || null) })
    })
}

/**
 * Writes of one name run one after the other, and only the newest waiting
 * payload is written (a desktop store is an async process: an older write
 * must never land after a newer one).
 */
var _localWrites = {}

function saveLocal(dataSource, name, payload) {
    var slot = _localWrites[name] || (_localWrites[name] = { running: false, next: null, waiters: [] })
    return new Promise(function(resolve, reject) {
        slot.next = payload
        slot.waiters.push({ resolve: resolve, reject: reject })
        if (!slot.running) {
            writeNext(dataSource, name, slot)
        }
    })
}

function writeNext(dataSource, name, slot) {
    if (slot.next === null) {
        slot.running = false
        return
    }
    var payload = slot.next
    var waiters = slot.waiters
    slot.next = null
    slot.waiters = []
    slot.running = true
    _backend.saveLocal(dataSource, name, payload, function(ok, err) {
        for (var i = 0; i < waiters.length; i++) {
            if (ok) {
                waiters[i].resolve(true)
            } else {
                waiters[i].reject(err)
            }
        }
        writeNext(dataSource, name, slot)
    })
}
