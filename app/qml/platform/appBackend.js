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
 * @param {QObject} [idleWatcher] - C++ IdleWatcher singleton (Linux/Plasma Mobile only, undefined on Android)
 * @param {QObject} [notifier] - C++ Notifier singleton (Linux/Plasma Mobile only, undefined on Android)
 * @returns {Object} backend object matching the platform.js interface
 */
function create(tokenStore, fileStore, idleWatcher, notifier) {
    // Handles the first emission whose first argument (profile id / file
    // name) is `key`. Keychain jobs finish async: a reply for another
    // profile must not consume this listener, or its callback never runs.
    function _connectOnce(signal, key, handler) {
        var wrapper = function() {
            if (key !== undefined && arguments[0] !== key) {
                return
            }
            signal.disconnect(wrapper)
            handler.apply(null, arguments)
        }
        signal.connect(wrapper)
    }

    return {
        loadToken: function(_ds, profileId, cb) {
            _connectOnce(tokenStore.loaded, profileId, function(id, token) {
                cb(token || "", null)
            })
            tokenStore.load(profileId)
        },

        saveToken: function(_ds, profileId, token, cb) {
            _connectOnce(tokenStore.saved, profileId, function(id, ok) {
                cb(ok, ok ? null : "Failed to save token")
            })
            tokenStore.save(profileId, token)
        },

        clearToken: function(_ds, profileId, cb) {
            _connectOnce(tokenStore.removed, profileId, function(id, ok) {
                cb(ok, ok ? null : "Failed to remove token")
            })
            tokenStore.remove(profileId)
        },

        runIdle: function(_ds, cb) {
            if (!idleWatcher) { cb(-1, null); return }
            _connectOnce(idleWatcher.idleChecked, undefined, function(idleMs, ok) {
                cb(ok ? idleMs : -1, null)
            })
            idleWatcher.checkIdle()
        },

        notify: function(_ds, summary, body, cb) {
            if (!notifier) { if (cb) cb(); return }
            if (cb) {
                _connectOnce(notifier.notified, undefined, function(_ok) { cb() })
            }
            notifier.notify(summary || "", body || "")
        },

        loadSharedConfig: function(_ds, cb) {
            _connectOnce(fileStore.loaded, "shared.json", function(_name, data) {
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
            _connectOnce(fileStore.saved, "shared.json", function(_name, ok) {
                if (cb) { cb(ok, ok ? null : "Failed to save") }
            })
            fileStore.save("shared.json", JSON.stringify(obj || {}))
        },

        loadCatalogCacheText: function(_ds, cb) {
            _connectOnce(fileStore.loaded, "catalog.json", function(_name, data) {
                cb(data || "", null)
            })
            fileStore.load("catalog.json")
        },

        loadCatalogCache: function(_ds, cb) {
            _connectOnce(fileStore.loaded, "catalog.json", function(_name, data) {
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
            _connectOnce(fileStore.saved, "catalog.json", function(_name, ok) {
                if (cb) { cb(ok, ok ? null : "Failed to save catalog") }
            })
            fileStore.save("catalog.json", JSON.stringify(payload || {}))
        }
    }
}
