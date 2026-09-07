.pragma library

/**
 * Desktop backend for platform.js.
 * Wraps secret.js (P5Support.DataSource + shell scripts).
 * Factory: pass resolved script paths, get a backend object.
 */
.import "secret.js" as Secret

function create(kwalletScript, idleScript, notifyScript,
                sharedConfigScript, catalogCacheScript) {
    return {
        loadToken: function(ds, id, cb) {
            Secret.load(ds, kwalletScript, id, cb)
        },
        saveToken: function(ds, id, token, cb) {
            Secret.save(ds, kwalletScript, id, token, cb)
        },
        clearToken: function(ds, id, cb) {
            Secret.clear(ds, kwalletScript, id, cb)
        },
        runIdle: function(ds, cb) {
            Secret.runIdle(ds, idleScript, cb)
        },
        notify: function(ds, summary, body, cb) {
            Secret.notify(ds, notifyScript, summary, body, cb)
        },
        loadSharedConfig: function(ds, cb) {
            Secret.loadSharedConfig(ds, sharedConfigScript, cb)
        },
        saveSharedConfig: function(ds, obj, cb) {
            Secret.saveSharedConfig(ds, sharedConfigScript, obj, cb)
        },
        loadCatalogCacheText: function(ds, cb) {
            Secret.loadCatalogCacheText(ds, catalogCacheScript, cb)
        },
        loadCatalogCache: function(ds, cb) {
            Secret.loadCatalogCache(ds, catalogCacheScript, cb)
        },
        saveCatalogCache: function(ds, payload, cb) {
            Secret.saveCatalogCache(ds, catalogCacheScript, payload, cb)
        }
    }
}
