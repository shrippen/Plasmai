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

function saveCatalog(dataSource, payload) {
    return new Promise(function(resolve, reject) {
        _backend.saveCatalogCache(dataSource, payload,
            function(ok, err) {
                if (!ok) { reject(err) } else { resolve(true) }
            })
    })
}
