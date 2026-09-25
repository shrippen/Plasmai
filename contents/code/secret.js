.pragma library
.import "sharedConfig.js" as SharedConfig

function shQuote(value) {
    return "'" + String(value).replace(/'/g, "'\\''") + "'"
}

/** Strip file:// from Qt.resolvedUrl() results for shell scripts (percent-decoded). */
function fileUrlToPath(url) {
    var s = String(url)
    if (s.indexOf("file://") === 0) {
        s = s.substring(7)
        try {
            s = decodeURIComponent(s)
        } catch (e) {
        }
    }
    return s
}

var _pending = {}
var _job = 0

function handleData(dataSource, sourceName, data) {
    var entry = _pending[sourceName]
    if (!entry) {
        return
    }
    delete _pending[sourceName]
    dataSource.disconnectSource(sourceName)
    entry.callback(data)
}

function cancelAll(dataSource) {
    for (var cmd in _pending) {
        if (!Object.prototype.hasOwnProperty.call(_pending, cmd)) {
            continue
        }
        delete _pending[cmd]
        dataSource.disconnectSource(cmd)
    }
}

function _run(dataSource, command, callback) {
    // Unique source names: settings pages share this pragma-library pending map.
    // Append a shell comment so identical commands do not collide; avoid wrapping
    // in `env` (QProcess then shows as /usr/bin/env and can be destroyed early).
    _job += 1
    var source = command + " #plasmai-job-" + _job
    _pending[source] = { callback: callback }
    dataSource.connectSource(source)
}

function parseJsonPayload(text) {
    var s = String(text || "")
    var start = s.indexOf("{")
    var end = s.lastIndexOf("}")
    if (start < 0 || end <= start) {
        return null
    }
    try {
        return JSON.parse(s.substring(start, end + 1))
    } catch (e) {
        return null
    }
}

function load(dataSource, scriptPath, profileId, callback) {
    var id = profileId || "default"
    var cmd = "sh " + shQuote(scriptPath) + " load " + shQuote(id)
    _run(dataSource, cmd, function(data) {
        var stdout = (data["stdout"] || "").toString()
        if (stdout.length && stdout.charAt(stdout.length - 1) === "\n") {
            stdout = stdout.substring(0, stdout.length - 1)
        }
        var exitCode = data["exit code"]
        if (exitCode === 0) {
            callback(stdout, null)
        } else if (exitCode === 1) {
            callback("", null)
        } else {
            var stderr = (data["stderr"] || "").toString().trim()
            callback("", stderr || ("kwallet.sh load failed (exit " + exitCode + ")"))
        }
    })
}

function save(dataSource, scriptPath, profileId, token, callback) {
    if (!token) {
        callback(false, "Token is empty")
        return
    }
    var id = profileId || "default"
    // The command line is the argv of `sh -c` (world-readable in /proc).
    // `exec` replaces that shell right away, so the token only stays in the
    // environment of kwallet.sh (owner-only) and reaches secret-tool on stdin.
    var cmd = storeCommand("KIMAI_TOKEN", token, scriptPath, ["store", id])
    _run(dataSource, cmd, function(data) {
        var exitCode = data["exit code"]
        if (exitCode === 0) {
            callback(true, null)
        } else {
            var stderr = (data["stderr"] || "").toString().trim()
            callback(false, stderr || ("kwallet.sh store failed (exit " + exitCode + ")"))
        }
    })
}

function clear(dataSource, scriptPath, profileId, callback) {
    var id = profileId || "default"
    var cmd = "sh " + shQuote(scriptPath) + " clear " + shQuote(id)
    _run(dataSource, cmd, function(data) {
        var exitCode = data["exit code"]
        if (exitCode === 0) {
            callback(true, null)
        } else {
            var stderr = (data["stderr"] || "").toString().trim()
            callback(false, stderr || ("kwallet.sh clear failed (exit " + exitCode + ")"))
        }
    })
}

function runIdle(dataSource, scriptPath, callback) {
    var cmd = "sh " + shQuote(scriptPath)
    _run(dataSource, cmd, function(data) {
        var stdout = (data["stdout"] || "").toString().trim()
        var exitCode = data["exit code"]
        if (exitCode === 0 && stdout.length > 0) {
            var ms = parseInt(stdout)
            callback(isNaN(ms) ? -1 : ms, null)
        } else {
            var stderr = (data["stderr"] || "").toString().trim()
            callback(-1, stderr || ("idle.sh failed (exit " + exitCode + ")"))
        }
    })
}

function notify(dataSource, scriptPath, summary, body, callback) {
    var cmd = "sh " + shQuote(scriptPath) + " " + shQuote(summary) + " " + shQuote(body || "")
    _run(dataSource, cmd, function(data) {
        var exitCode = data["exit code"]
        if (callback) {
            callback(exitCode === 0, exitCode === 127 ? "notify-send not installed" : null)
        }
    })
}

function loadSharedConfig(dataSource, scriptPath, callback) {
    var cmd = "sh " + shQuote(scriptPath) + " load"
    _run(dataSource, cmd, function(data) {
        var stdout = (data["stdout"] || "").toString()
        if (stdout.length && stdout.charAt(stdout.length - 1) === "\n") {
            stdout = stdout.substring(0, stdout.length - 1)
        }
        var exitCode = data["exit code"]
        if (exitCode === 0 && stdout.length > 0) {
            try {
                callback(JSON.parse(stdout), null)
            } catch (e) {
                callback(null, "Invalid shared config JSON")
            }
        } else if (exitCode === 1) {
            callback(null, null)
        } else {
            var stderr = (data["stderr"] || "").toString().trim()
            callback(null, stderr || ("sharedConfig.sh load failed (exit " + exitCode + ")"))
        }
    })
}

function saveSharedConfig(dataSource, scriptPath, sharedObj, callback) {
    var json = JSON.stringify(sharedObj || {})
    var cmd = "env KIMAI_SHARED_JSON=" + shQuote(json) + " sh " + shQuote(scriptPath) + " store"
    _run(dataSource, cmd, function(data) {
        var exitCode = data["exit code"]
        if (callback) {
            if (exitCode === 0) {
                callback(true, null)
            } else {
                var stderr = (data["stderr"] || "").toString().trim()
                callback(false, stderr || ("sharedConfig.sh store failed (exit " + exitCode + ")"))
            }
        }
    })
}

/** Raw catalog JSON text. Parse off the UI thread (WorkerScript) so the KCM stays responsive. */
function loadCatalogCacheText(dataSource, scriptPath, callback) {
    var cmd = "sh " + shQuote(scriptPath) + " load"
    _run(dataSource, cmd, function(data) {
        var stdout = (data["stdout"] || "").toString()
        if (stdout.length && stdout.charAt(stdout.length - 1) === "\n") {
            stdout = stdout.substring(0, stdout.length - 1)
        }
        var exitCode = data["exit code"]
        if (exitCode === 0 && stdout.length > 0) {
            callback(stdout, null)
        } else if (exitCode === 1) {
            callback("", null)
        } else {
            var stderr = (data["stderr"] || "").toString().trim()
            callback("", stderr || ("catalogCache.sh load failed (exit " + exitCode + ")"))
        }
    })
}

function loadCatalogCache(dataSource, scriptPath, callback) {
    loadCatalogCacheText(dataSource, scriptPath, function(text, err) {
        if (err) {
            callback(null, err)
            return
        }
        if (!text) {
            callback(null, null)
            return
        }
        var parsed = parseJsonPayload(text)
        if (parsed) {
            callback(parsed, null)
        } else {
            callback(null, "Invalid catalog cache JSON")
        }
    })
}

/** `NAME='value' exec sh 'script' 'arg'…` — value passed via the environment. */
function storeCommand(envName, value, scriptPath, args) {
    var cmd = envName + "=" + shQuote(value) + " exec sh " + shQuote(scriptPath)
    for (var i = 0; i < (args || []).length; i++) {
        cmd += " " + shQuote(args[i])
    }
    return cmd
}

/**
 * Linux caps one argv string (the whole `sh -c` command) at 128 KiB.
 * Chars per chunk: ≤ 4 bytes each after UTF-8 / quote escaping.
 */
var CATALOG_CHUNK_CHARS = 30000
var _catalogJob = 0

function catalogChunks(json, size) {
    var n = size || CATALOG_CHUNK_CHARS
    var out = []
    var i = 0
    while (i < json.length) {
        var end = Math.min(json.length, i + n)
        // Do not split a UTF-16 surrogate pair across chunks.
        var last = json.charCodeAt(end - 1)
        if (end < json.length && last >= 0xD800 && last <= 0xDBFF) {
            end -= 1
        }
        out.push(json.substring(i, end))
        i = end
    }
    return out
}

function saveCatalogCache(dataSource, scriptPath, payload, callback) {
    var json = JSON.stringify(payload || {})
    function finish(data, what) {
        var exitCode = data["exit code"]
        if (callback) {
            if (exitCode === 0) {
                callback(true, null)
            } else {
                var stderr = (data["stderr"] || "").toString().trim()
                callback(false, stderr || ("catalogCache.sh " + what + " failed (exit " + exitCode + ")"))
            }
        }
    }
    if (json.length <= CATALOG_CHUNK_CHARS) {
        _run(dataSource, storeCommand("PLASMAI_CATALOG_JSON", json, scriptPath, ["store"]), function(data) {
            finish(data, "store")
        })
        return
    }
    _catalogJob += 1
    var job = Date.now() + "-" + _catalogJob
    var chunks = catalogChunks(json)
    var index = 0
    function next() {
        if (index >= chunks.length) {
            _run(dataSource, "exec sh " + shQuote(scriptPath) + " commit " + shQuote(job), function(data) {
                finish(data, "commit")
            })
            return
        }
        var cmd = storeCommand("PLASMAI_CATALOG_JSON", chunks[index], scriptPath, ["append", job])
        index += 1
        _run(dataSource, cmd, function(data) {
            if (data["exit code"] !== 0) {
                finish(data, "append")
                return
            }
            next()
        })
    }
    next()
}

/** Load shared.json, merge patch, and save. configuration is plasmoid.configuration. */
function persistSharedPatch(dataSource, scriptPath, configuration, patch, callback) {
    loadSharedConfig(dataSource, scriptPath, function(existing) {
        var base = existing || SharedConfig.fromConfiguration(configuration)
        base = SharedConfig.sanitizeProfilesForPersistence(base, configuration)
        var shared = SharedConfig.merge(
            base,
            patch || {}
        )
        saveSharedConfig(dataSource, scriptPath, shared, callback)
    })
}
