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

function patchShared(dataSource, configuration, patch) {
    return new Promise(function(resolve, reject) {
        _backend.loadSharedConfig(dataSource, function(existing) {
            var base = existing || SharedConfig.fromConfiguration(configuration)
            base = SharedConfig.sanitizeProfilesForPersistence(base, configuration)
            var shared = SharedConfig.merge(base, patch || {})
            _backend.saveSharedConfig(dataSource, shared,
                function(ok, err) {
                    if (!ok) { reject(err) } else { resolve(true) }
                })
        })
    })
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
