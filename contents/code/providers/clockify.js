.pragma library
.import "../providerUtil.js" as Util

var ErrorType = Util.ErrorType
var DEFAULT_CUSTOMER_COLOR = Util.DEFAULT_CUSTOMER_COLOR

var DEFAULT_BASE_URL = "https://api.clockify.me/api/v1"

var _session = {
    workspaceId: "",
    userId: "",
    projectsById: {},
    clientsById: {},
    tasksById: {}
}

function setSession(s) {
    _session = s || {}
    if (!_session.projectsById) {
        _session.projectsById = {}
    }
    if (!_session.clientsById) {
        _session.clientsById = {}
    }
    if (!_session.tasksById) {
        _session.tasksById = {}
    }
}

function normalizeUrl(url) {
    return Util.normalizeUrl(url)
}

function baseUrl(url) {
    var u = Util.normalizeUrl(url)
    return u || DEFAULT_BASE_URL
}

function createRequest(method, url, endpoint, token, isJson) {
    var xhr = new XMLHttpRequest()
    xhr.open(method, baseUrl(url) + endpoint, true)
    xhr.setRequestHeader("X-Api-Key", token)
    xhr.setRequestHeader("Accept", "application/json")
    if (isJson) {
        xhr.setRequestHeader("Content-Type", "application/json")
    }
    return xhr
}

function request(method, url, token, endpoint, body, isJson, callback) {
    if (!token) {
        callback(Util.fail({ type: "config", status: 0, detail: "" }))
        return
    }
    var xhr = createRequest(method, url, endpoint, token, isJson)
    Util.runRequest(xhr, body, function(status, responseText, statusText) {
        if (status >= 200 && status < 300) {
            callback(Util.ok(Util.parseJson(responseText, null)))
        } else {
            callback(Util.fail(Util.parseApiError(status, statusText, responseText)))
        }
    })
}

function getJson(url, token, endpoint, emptyValue, callback) {
    request("GET", url, token, endpoint, undefined, false, function(result) {
        if (result.ok) {
            callback(Util.ok(result.data !== null && result.data !== undefined ? result.data : emptyValue))
        } else {
            callback(result)
        }
    })
}

function resolveSession(url, token, callback) {
    if (_session.workspaceId && _session.userId) {
        callback(Util.ok(_session))
        return
    }
    getJson(url, token, "/user", {}, function(userResult) {
        if (!userResult.ok) {
            callback(userResult)
            return
        }
        var user = userResult.data || {}
        _session.userId = _session.userId || user.id || ""
        if (_session.workspaceId) {
            callback(Util.ok(_session))
            return
        }
        getJson(url, token, "/workspaces", [], function(wsResult) {
            if (!wsResult.ok) {
                callback(wsResult)
                return
            }
            var workspaces = wsResult.data || []
            var wid = user.activeWorkspace || user.defaultWorkspace || ""
            if (!wid && workspaces.length > 0) {
                wid = workspaces[0].id || ""
            }
            _session.workspaceId = wid
            callback(Util.ok(_session))
        })
    })
}

function withSession(url, token, callback) {
    resolveSession(url, token, function(result) {
        if (!result.ok) {
            callback(result)
            return
        }
        if (!_session.workspaceId || !_session.userId) {
            callback(Util.fail({ type: "config", status: 0, detail: "Workspace or user not resolved" }))
            return
        }
        callback(Util.ok(_session))
    })
}

function wsPath(suffix) {
    return "/workspaces/" + _session.workspaceId + suffix
}

function userTePath(suffix) {
    return wsPath("/user/" + _session.userId + "/time-entries" + (suffix || ""))
}

function clientName(clientId) {
    if (!clientId) {
        return ""
    }
    var c = _session.clientsById[clientId]
    return c ? (c.name || "") : ""
}

/** Accept Kimai-local or ISO strings and emit Clockify UTC Z format. */
function toClockifyTime(value) {
    if (!value) {
        return Util.isoUtc(new Date())
    }
    var d = new Date(value)
    if (isNaN(d.getTime())) {
        d = new Date(String(value).replace(" ", "T"))
    }
    if (isNaN(d.getTime())) {
        return Util.isoUtc(new Date())
    }
    return Util.isoUtc(d)
}

function projectFromId(projectId, fallbackName) {
    if (!projectId) {
        return { id: "", name: "", customer: "", color: DEFAULT_CUSTOMER_COLOR }
    }
    var p = _session.projectsById[projectId]
    if (p) {
        return {
            id: p.id,
            name: p.name || fallbackName || "",
            customer: clientName(p.clientId) || p.customer || "",
            color: Util.normalizeCustomerColor(p.color)
        }
    }
    return {
        id: projectId,
        name: fallbackName || "",
        customer: "",
        color: DEFAULT_CUSTOMER_COLOR
    }
}

function activityFromIds(projectId, taskId, fallbackName) {
    if (!taskId) {
        return { id: "", name: fallbackName || "" }
    }
    var t = _session.tasksById[taskId]
    return {
        id: taskId,
        name: (t && t.name) || fallbackName || ""
    }
}

function normalizeTimesheet(entry) {
    if (!entry) {
        return null
    }
    var interval = entry.timeInterval || {}
    var begin = interval.start || entry.start || ""
    var end = interval.end || entry.end || null
    var duration = Util.parseIsoDurationToSeconds(interval.duration)
    if (!duration && begin) {
        duration = Util.durationSecondsFromRange(begin, end)
    }
    return {
        id: entry.id,
        begin: begin,
        end: end,
        duration: duration,
        description: entry.description || "",
        billable: !!entry.billable,
        project: projectFromId(entry.projectId, entry.projectName),
        activity: activityFromIds(entry.projectId, entry.taskId, entry.taskName)
    }
}

function normalizeTimesheets(entries) {
    var out = []
    for (var i = 0; i < (entries || []).length; i++) {
        var row = normalizeTimesheet(entries[i])
        if (row) {
            out.push(row)
        }
    }
    return out
}

function testConnection(url, token, callback) {
    if (!token) {
        callback(Util.fail({ type: "config", status: 0, detail: "" }))
        return
    }
    getJson(url, token, "/user", {}, function(userResult) {
        if (!userResult.ok) {
            callback(userResult)
            return
        }
        var user = userResult.data || {}
        _session.userId = user.id || ""
        getJson(url, token, "/workspaces", [], function(wsResult) {
            if (!wsResult.ok) {
                callback(wsResult)
                return
            }
            var workspaces = wsResult.data || []
            var wid = _session.workspaceId || user.activeWorkspace || user.defaultWorkspace || ""
            if (!wid && workspaces.length > 0) {
                wid = workspaces[0].id || ""
            }
            _session.workspaceId = wid
            var summary = []
            for (var i = 0; i < workspaces.length; i++) {
                summary.push({ id: workspaces[i].id, name: workspaces[i].name || "" })
            }
            callback(Util.ok({
                version: "Clockify",
                workspaceId: _session.workspaceId,
                userId: _session.userId,
                workspaces: summary
            }))
        })
    })
}

function fetchActiveTimesheet(url, token, callback) {
    withSession(url, token, function(sessionResult) {
        if (!sessionResult.ok) {
            callback(sessionResult)
            return
        }
        getJson(url, token, userTePath("?in-progress=true"), [], function(result) {
            if (!result.ok) {
                callback(result)
                return
            }
            var rows = normalizeTimesheets(result.data || [])
            callback(Util.ok(rows.length > 0 ? [rows[0]] : []))
        })
    })
}

function fetchRecentTimesheets(url, token, size, callback) {
    withSession(url, token, function(sessionResult) {
        if (!sessionResult.ok) {
            callback(sessionResult)
            return
        }
        var pageSize = size || 10
        getJson(url, token, userTePath("?page-size=" + pageSize), [], function(result) {
            if (!result.ok) {
                callback(result)
                return
            }
            var rows = normalizeTimesheets(result.data || [])
            rows.sort(function(a, b) {
                return String(b.begin).localeCompare(String(a.begin))
            })
            callback(Util.ok(rows.slice(0, pageSize)))
        })
    })
}

function startTracking(url, token, projectId, activityId, description, callback) {
    withSession(url, token, function(sessionResult) {
        if (!sessionResult.ok) {
            callback(sessionResult)
            return
        }
        var data = {
            start: toClockifyTime(new Date()),
            description: description || "",
            projectId: projectId || null,
            billable: false
        }
        if (activityId) {
            data.taskId = activityId
        }
        request("POST", url, token, wsPath("/time-entries"), JSON.stringify(data), true, function(result) {
            if (result.ok) {
                callback(Util.ok(normalizeTimesheet(result.data)))
            } else {
                callback(result)
            }
        })
    })
}

function stopTracking(url, token, timesheetId, callback) {
    withSession(url, token, function(sessionResult) {
        if (!sessionResult.ok) {
            callback(sessionResult)
            return
        }
        var body = { end: Util.isoUtc(new Date()) }
        request("PATCH", url, token, userTePath(), JSON.stringify(body), true, function(result) {
            if (result.ok) {
                callback(Util.ok(normalizeTimesheet(result.data)))
            } else {
                callback(result)
            }
        })
    })
}

function restartTimesheet(url, token, timesheetId, callback) {
    if (!timesheetId) {
        callback(Util.fail({ type: "config", status: 0, detail: "" }))
        return
    }
    withSession(url, token, function(sessionResult) {
        if (!sessionResult.ok) {
            callback(sessionResult)
            return
        }
        getJson(url, token, wsPath("/time-entries/" + timesheetId), {}, function(entryResult) {
            if (!entryResult.ok) {
                callback(entryResult)
                return
            }
            var entry = entryResult.data || {}
            startTracking(
                url,
                token,
                entry.projectId || "",
                entry.taskId || "",
                entry.description || "",
                callback
            )
        })
    })
}

function patchTimesheet(url, token, timesheetId, fields, callback) {
    if (!timesheetId) {
        callback(Util.fail({ type: "config", status: 0, detail: "" }))
        return
    }
    withSession(url, token, function(sessionResult) {
        if (!sessionResult.ok) {
            callback(sessionResult)
            return
        }
        getJson(url, token, wsPath("/time-entries/" + timesheetId), {}, function(entryResult) {
            if (!entryResult.ok) {
                callback(entryResult)
                return
            }
            var existing = entryResult.data || {}
            var interval = existing.timeInterval || {}
            var f = fields || {}
            var payload = {
                start: f.begin || interval.start || existing.start || Util.isoUtc(new Date()),
                description: f.description !== undefined ? f.description : (existing.description || ""),
                billable: existing.billable || false
            }
            if (f.end !== undefined) {
                payload.end = f.end
            } else if (interval.end) {
                payload.end = interval.end
            }
            if (f.project !== undefined) {
                payload.projectId = f.project || null
            } else if (existing.projectId) {
                payload.projectId = existing.projectId
            }
            if (f.activity !== undefined) {
                payload.taskId = f.activity || null
            } else if (existing.taskId) {
                payload.taskId = existing.taskId
            }
            request("PUT", url, token, wsPath("/time-entries/" + timesheetId), JSON.stringify(payload), true, function(result) {
                if (result.ok) {
                    callback(Util.ok(normalizeTimesheet(result.data)))
                } else {
                    callback(result)
                }
            })
        })
    })
}

function createTimesheet(url, token, fields, callback) {
    withSession(url, token, function(sessionResult) {
        if (!sessionResult.ok) {
            callback(sessionResult)
            return
        }
        var f = fields || {}
        if (!f.begin) {
            callback(Util.fail({ type: "config", status: 0, detail: "begin is required" }))
            return
        }
        var data = {
            start: toClockifyTime(f.begin),
            description: f.description || "",
            billable: false
        }
        if (f.end) {
            data.end = toClockifyTime(f.end)
        }
        if (f.project) {
            data.projectId = f.project
        }
        if (f.activity) {
            data.taskId = f.activity
        }
        request("POST", url, token, wsPath("/time-entries"), JSON.stringify(data), true, function(result) {
            if (result.ok) {
                callback(Util.ok(normalizeTimesheet(result.data)))
            } else {
                callback(result)
            }
        })
    })
}

function loadCustomers(url, token, callback) {
    withSession(url, token, function(sessionResult) {
        if (!sessionResult.ok) {
            callback(sessionResult)
            return
        }
        getJson(url, token, wsPath("/clients"), [], function(result) {
            if (!result.ok) {
                callback(result)
                return
            }
            var rows = []
            _session.clientsById = {}
            var list = result.data || []
            for (var i = 0; i < list.length; i++) {
                var c = list[i]
                _session.clientsById[c.id] = c
                rows.push({
                    id: c.id,
                    name: c.name || "",
                    color: DEFAULT_CUSTOMER_COLOR
                })
            }
            callback(Util.ok(rows))
        })
    })
}

function loadProjects(url, token, callback) {
    withSession(url, token, function(sessionResult) {
        if (!sessionResult.ok) {
            callback(sessionResult)
            return
        }
        getJson(url, token, wsPath("/projects"), [], function(result) {
            if (!result.ok) {
                callback(result)
                return
            }
            var list = result.data || []
            _session.projectsById = {}
            var rows = []
            for (var i = 0; i < list.length; i++) {
                var p = list[i]
                _session.projectsById[p.id] = p
                rows.push({
                    id: p.id,
                    name: p.name || "",
                    customer: clientName(p.clientId),
                    color: Util.normalizeCustomerColor(p.color)
                })
            }
            callback(Util.ok(rows))
        })
    })
}

function loadActivities(url, token, projectId, callback) {
    if (!projectId) {
        callback(Util.fail({ type: "config", status: 0, detail: "" }))
        return
    }
    withSession(url, token, function(sessionResult) {
        if (!sessionResult.ok) {
            callback(sessionResult)
            return
        }
        getJson(url, token, wsPath("/projects/" + projectId + "/tasks"), [], function(result) {
            if (!result.ok) {
                callback(result)
                return
            }
            var list = result.data || []
            var rows = []
            for (var i = 0; i < list.length; i++) {
                var t = list[i]
                _session.tasksById[t.id] = t
                rows.push({
                    id: t.id,
                    name: t.name || "",
                    project: projectId
                })
            }
            if (rows.length === 0) {
                rows.push({ id: "", name: "General", project: projectId })
            }
            callback(Util.ok(rows))
        })
    })
}

function fetchTimesheetsRange(url, token, beginDate, endDate, callback) {
    withSession(url, token, function(sessionResult) {
        if (!sessionResult.ok) {
            callback(sessionResult)
            return
        }
        var start = encodeURIComponent(Util.isoUtc(beginDate))
        var end = encodeURIComponent(Util.isoUtc(endDate))
        getJson(url, token, userTePath("?start=" + start + "&end=" + end + "&page-size=1000"), [], function(result) {
            if (!result.ok) {
                callback(result)
                return
            }
            callback(Util.ok(normalizeTimesheets(result.data || [])))
        })
    })
}

function fetchCurrentUser(url, token, callback) {
    getJson(url, token, "/user", {}, function(result) {
        if (!result.ok) {
            callback(result)
            return
        }
        var u = result.data || {}
        callback(Util.ok({
            id: u.id,
            username: u.email || u.name || "",
            email: u.email || "",
            name: u.name || ""
        }))
    })
}

function preferenceMap(user) {
    return {}
}

function workDaySecondsFromPrefs(prefs, date) {
    return 0
}

function workWeekSecondsFromPrefs(prefs, date) {
    return 0
}
