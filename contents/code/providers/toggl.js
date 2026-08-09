.pragma library
.import "../providerUtil.js" as Util

var ErrorType = Util.ErrorType
var DEFAULT_CUSTOMER_COLOR = Util.DEFAULT_CUSTOMER_COLOR

var DEFAULT_BASE_URL = "https://api.track.toggl.com/api/v9"

var _session = {
    workspaceId: 0,
    userId: 0,
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
    xhr.setRequestHeader("Authorization", Util.basicAuthHeader(token, "api_token"))
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
        } else if (status === 404) {
            callback(Util.ok(null))
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
    getJson(url, token, "/me", {}, function(meResult) {
        if (!meResult.ok) {
            callback(meResult)
            return
        }
        var me = meResult.data || {}
        _session.userId = _session.userId || me.id || 0
        _session.workspaceId = _session.workspaceId || me.default_workspace_id || 0
        callback(Util.ok(_session))
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

function intId(value) {
    if (value === null || value === undefined || value === "") {
        return 0
    }
    var n = parseInt(value, 10)
    return isNaN(n) ? 0 : n
}

function clientName(clientId) {
    if (!clientId) {
        return ""
    }
    var c = _session.clientsById[clientId]
    return c ? (c.name || "") : ""
}

function projectFromEntry(entry) {
    var pid = entry.project_id || entry.pid || 0
    if (!pid) {
        return {
            id: 0,
            name: entry.project_name || "",
            customer: entry.client_name || "",
            color: Util.normalizeCustomerColor(entry.project_color)
        }
    }
    var p = _session.projectsById[pid]
    return {
        id: pid,
        name: (p && p.name) || entry.project_name || "",
        customer: clientName(p && p.client_id) || entry.client_name || "",
        color: Util.normalizeCustomerColor((p && p.color) || entry.project_color)
    }
}

function activityFromEntry(entry) {
    var tid = entry.task_id || entry.tid || 0
    if (!tid) {
        return { id: 0, name: entry.task_name || "" }
    }
    var t = _session.tasksById[tid]
    return {
        id: tid,
        name: (t && t.name) || entry.task_name || ""
    }
}

function normalizeTimesheet(entry) {
    if (!entry) {
        return null
    }
    var begin = entry.start || ""
    var end = entry.stop || null
    var duration = entry.duration
    if (typeof duration === "number" && duration < 0) {
        duration = Util.durationSecondsFromRange(begin, null)
        end = null
    } else if (duration === null || duration === undefined) {
        duration = Util.durationSecondsFromRange(begin, end)
    } else {
        duration = Math.max(0, Math.floor(Number(duration)))
    }
    return {
        id: entry.id,
        begin: begin,
        end: end,
        duration: duration,
        description: entry.description || "",
        billable: !!entry.billable,
        project: projectFromEntry(entry),
        activity: activityFromEntry(entry)
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
    getJson(url, token, "/me", {}, function(result) {
        if (!result.ok) {
            callback(result)
            return
        }
        var me = result.data || {}
        _session.userId = me.id || 0
        _session.workspaceId = _session.workspaceId || me.default_workspace_id || 0
        callback(Util.ok({
            version: "Toggl Track",
            workspaceId: _session.workspaceId,
            userId: _session.userId,
            email: me.email || ""
        }))
    })
}

function fetchActiveTimesheet(url, token, callback) {
    getJson(url, token, "/me/time_entries/current", null, function(result) {
        if (!result.ok) {
            callback(result)
            return
        }
        if (!result.data) {
            callback(Util.ok([]))
            return
        }
        callback(Util.ok([normalizeTimesheet(result.data)]))
    })
}

function fetchRecentTimesheets(url, token, size, callback) {
    var pageSize = size || 10
    getJson(url, token, "/me/time_entries?meta=true", [], function(result) {
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
}

function startTracking(url, token, projectId, activityId, description, callback) {
    withSession(url, token, function(sessionResult) {
        if (!sessionResult.ok) {
            callback(sessionResult)
            return
        }
        var data = {
            created_with: "Plasmai",
            description: description || "",
            start: Util.isoUtc(new Date()),
            duration: -1,
            workspace_id: _session.workspaceId,
            billable: false
        }
        var pid = intId(projectId)
        if (pid) {
            data.project_id = pid
        }
        var tid = intId(activityId)
        if (tid) {
            data.task_id = tid
        }
        request("POST", url, token, "/workspaces/" + _session.workspaceId + "/time_entries", JSON.stringify(data), true, function(result) {
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
        if (!timesheetId) {
            callback(Util.fail({ type: "config", status: 0, detail: "" }))
            return
        }
        request("PATCH", url, token, "/workspaces/" + _session.workspaceId + "/time_entries/" + timesheetId + "/stop", undefined, false, function(result) {
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
    getJson(url, token, "/me/time_entries/" + timesheetId, {}, function(entryResult) {
        if (!entryResult.ok) {
            callback(entryResult)
            return
        }
        var entry = entryResult.data || {}
        startTracking(
            url,
            token,
            entry.project_id || entry.pid || 0,
            entry.task_id || entry.tid || 0,
            entry.description || "",
            callback
        )
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
        getJson(url, token, "/me/time_entries/" + timesheetId, {}, function(entryResult) {
            if (!entryResult.ok) {
                callback(entryResult)
                return
            }
            var existing = entryResult.data || {}
            var f = fields || {}
            var payload = {
                created_with: "Plasmai",
                description: f.description !== undefined ? f.description : (existing.description || ""),
                start: f.begin || existing.start,
                workspace_id: _session.workspaceId,
                billable: existing.billable || false
            }
            if (f.end !== undefined) {
                payload.stop = f.end
            } else if (existing.stop) {
                payload.stop = existing.stop
            }
            if (f.project !== undefined) {
                payload.project_id = intId(f.project) || null
            } else if (existing.project_id || existing.pid) {
                payload.project_id = existing.project_id || existing.pid
            }
            if (f.activity !== undefined) {
                payload.task_id = intId(f.activity) || null
            } else if (existing.task_id || existing.tid) {
                payload.task_id = existing.task_id || existing.tid
            }
            if (payload.start && payload.stop) {
                var startMs = new Date(payload.start).getTime()
                var stopMs = new Date(payload.stop).getTime()
                if (!isNaN(startMs) && !isNaN(stopMs)) {
                    payload.duration = Math.max(0, Math.floor((stopMs - startMs) / 1000))
                }
            } else if (existing.duration !== undefined && existing.duration !== null) {
                payload.duration = existing.duration
            }
            request("PUT", url, token, "/workspaces/" + _session.workspaceId + "/time_entries/" + timesheetId, JSON.stringify(payload), true, function(result) {
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
        var beginIso = Util.isoUtc(new Date(f.begin))
        if (isNaN(new Date(f.begin).getTime())) {
            beginIso = Util.isoUtc(new Date(String(f.begin).replace(" ", "T")))
        }
        var data = {
            created_with: "Plasmai",
            description: f.description || "",
            start: beginIso,
            workspace_id: _session.workspaceId,
            billable: false
        }
        if (f.end) {
            var endDate = new Date(f.end)
            if (isNaN(endDate.getTime())) {
                endDate = new Date(String(f.end).replace(" ", "T"))
            }
            data.stop = Util.isoUtc(endDate)
            var startMs = new Date(beginIso).getTime()
            var stopMs = endDate.getTime()
            if (!isNaN(startMs) && !isNaN(stopMs)) {
                data.duration = Math.max(0, Math.floor((stopMs - startMs) / 1000))
            }
        }
        if (f.project) {
            data.project_id = intId(f.project)
        }
        if (f.activity) {
            data.task_id = intId(f.activity)
        }
        request("POST", url, token, "/workspaces/" + _session.workspaceId + "/time_entries", JSON.stringify(data), true, function(result) {
            if (result.ok) {
                callback(Util.ok(normalizeTimesheet(result.data)))
            } else {
                callback(result)
            }
        })
    })
}

function loadCustomers(url, token, callback) {
    getJson(url, token, "/me/clients", [], function(result) {
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
}

function loadProjects(url, token, callback) {
    getJson(url, token, "/me/projects", [], function(result) {
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
                customer: clientName(p.client_id),
                color: Util.normalizeCustomerColor(p.color)
            })
        }
        callback(Util.ok(rows))
    })
}

function loadActivities(url, token, projectId, callback) {
    var pid = intId(projectId)
    if (!pid) {
        callback(Util.fail({ type: "config", status: 0, detail: "" }))
        return
    }
    withSession(url, token, function(sessionResult) {
        if (!sessionResult.ok) {
            callback(sessionResult)
            return
        }
        getJson(url, token, "/workspaces/" + _session.workspaceId + "/projects/" + pid + "/tasks?active=true", [], function(result) {
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
                    project: pid
                })
            }
            if (rows.length === 0) {
                rows.push({ id: "", name: "General", project: pid })
            }
            callback(Util.ok(rows))
        })
    })
}

function fetchTimesheetsRange(url, token, beginDate, endDate, callback) {
    var startDate = encodeURIComponent(Util.isoUtc(beginDate))
    var endDateStr = encodeURIComponent(Util.isoUtc(endDate))
    getJson(url, token, "/me/time_entries?start_date=" + startDate + "&end_date=" + endDateStr + "&meta=true", [], function(result) {
        if (!result.ok) {
            callback(result)
            return
        }
        callback(Util.ok(normalizeTimesheets(result.data || [])))
    })
}

function fetchCurrentUser(url, token, callback) {
    getJson(url, token, "/me", {}, function(result) {
        if (!result.ok) {
            callback(result)
            return
        }
        var u = result.data || {}
        callback(Util.ok({
            id: u.id,
            username: u.email || u.fullname || "",
            email: u.email || "",
            name: u.fullname || ""
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
