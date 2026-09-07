.pragma library

/**
 * App backend for platform.js.
 * Uses C++ TokenStore (QtKeychain) and FileStore (QStandardPaths).
 * These are set as context properties by main.cpp.
 *
 * In a .pragma library we cannot access context properties directly,
 * so the factory receives them and returns a plain object.
 *
 * @param {QObject} tokenStore - C++ TokenStore singleton
 * @param {QObject} fileStore  - C++ FileStore singleton
 * @returns {Object} backend object matching the platform.js interface
 */
function create(tokenStore, fileStore) {
    function _connectOnce(signal, handler) {
        var wrapper = function() {
            signal.disconnect(wrapper)
            handler.apply(null, arguments)
        }
        signal.connect(wrapper)
    }

    return {
        loadToken: function(_ds, profileId, cb) {
            _connectOnce(tokenStore.loaded, function(id, token) {
                if (id === profileId) {
                    cb(token || "", null)
                }
            })
            tokenStore.load(profileId)
        },

        saveToken: function(_ds, profileId, token, cb) {
            _connectOnce(tokenStore.saved, function(id, ok) {
                if (id === profileId) {
                    cb(ok, ok ? null : "Failed to save token")
                }
            })
            tokenStore.save(profileId, token)
        },

        clearToken: function(_ds, profileId, cb) {
            _connectOnce(tokenStore.removed, function(id, ok) {
                if (id === profileId) {
                    cb(ok, ok ? null : "Failed to remove token")
                }
            })
            tokenStore.remove(profileId)
        },

        runIdle: function(_ds, cb) {
            cb(-1, null)
        },

        notify: function(_ds, _summary, _body, cb) {
            if (cb) { cb() }
        },

        loadSharedConfig: function(_ds, cb) {
            _connectOnce(fileStore.loaded, function(_name, data) {
                if (!data) { cb(null); return }
                try {
                    cb(JSON.parse(data))
                } catch (e) {
                    cb(null)
                }
            })
            fileStore.load("shared.json")
        },

        saveSharedConfig: function(_ds, obj, cb) {
            _connectOnce(fileStore.saved, function(_name, ok) {
                if (cb) { cb(ok, ok ? null : "Failed to save") }
            })
            fileStore.save("shared.json", JSON.stringify(obj || {}))
        },

        loadCatalogCacheText: function(_ds, cb) {
            _connectOnce(fileStore.loaded, function(_name, data) {
                cb(data || "", null)
            })
            fileStore.load("catalog.json")
        },

        loadCatalogCache: function(_ds, cb) {
            _connectOnce(fileStore.loaded, function(_name, data) {
                if (!data) { cb(null); return }
                try {
                    var obj = JSON.parse(data)
                    cb(obj)
                } catch (e) {
                    cb(null)
                }
            })
            fileStore.load("catalog.json")
        },

        saveCatalogCache: function(_ds, payload, cb) {
            _connectOnce(fileStore.saved, function(_name, ok) {
                if (cb) { cb(ok, ok ? null : "Failed to save catalog") }
            })
            fileStore.save("catalog.json", JSON.stringify(payload || {}))
        }
    }
}
