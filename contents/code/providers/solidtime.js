.pragma library
.import "../providerUtil.js" as Util
.import "../timesheetFields.js" as Fields

var ErrorType = Util.ErrorType
var DEFAULT_CUSTOMER_COLOR = Util.DEFAULT_CUSTOMER_COLOR

var _session = {
    organizationId: "",
    memberId: "",
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

function apiBase(url) {
    var base = Util.normalizeUrl(url)
    if (!base) {
        return ""
    }
    if (/\/api\/v1$/i.test(base)) {
        return base
    }
    return base + "/api/v1"
}

function createRequest(method, url, endpoint, token, isJson) {
    var xhr = new XMLHttpRequest()
    xhr.open(method, apiBase(url) + endpoint, true)
    xhr.setRequestHeader("Authorization", "Bearer " + token)
    xhr.setRequestHeader("Accept", "application/json")
    if (isJson) {
        xhr.setRequestHeader("Content-Type", "application/json")
    }
    return xhr
}

function request(method, url, token, endpoint, body, isJson, callback) {
    if (!url || !token) {
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
            var body = Util.unwrapData(result.data)
            callback(Util.ok(body !== null && body !== undefined ? body : emptyValue))
        } else {
            callback(result)
        }
    })
}

function resolveSession(url, token, callback) {
    if (_session.organizationId && _session.memberId) {
        callback(Util.ok(_session))
        return
    }
    getJson(url, token, "/users/me/memberships", [], function(membershipResult) {
        if (!membershipResult.ok) {
            callback(membershipResult)
            return
        }
        var memberships = membershipResult.data || []
        var picked = null
        if (_session.organizationId) {
            for (var i = 0; i < memberships.length; i++) {
                var m = memberships[i]
                if (m.organization && m.organization.id === _session.organizationId) {
                    picked = m
                    break
                }
            }
        }
        if (!picked && memberships.length > 0) {
            picked = memberships[0]
        }
        if (!picked) {
            callback(Util.fail({ type: "config", status: 0, detail: "No organization membership found" }))
            return
        }
        _session.memberId = _session.memberId || picked.id || ""
        _session.organizationId = _session.organizationId || (picked.organization && picked.organization.id) || ""
        callback(Util.ok(_session))
    })
}

function withSession(url, token, callback) {
    resolveSession(url, token, function(result) {
        if (!result.ok) {
            callback(result)
            return
        }
        if (!_session.organizationId || !_session.memberId) {
            callback(Util.fail({ type: "config", status: 0, detail: "Organization or member not resolved" }))
            return
        }
        callback(Util.ok(_session))
    })
}

function orgPath(suffix) {
    return "/organizations/" + _session.organizationId + suffix
}

function clientName(clientId) {
    if (!clientId) {
        return ""
    }
    var c = _session.clientsById[clientId]
    return c ? (c.name || "") : ""
}

function projectFromIds(projectId, fallbackName) {
    if (!projectId) {
        return { id: "", name: fallbackName || "", customer: "", color: DEFAULT_CUSTOMER_COLOR }
    }
    var p = _session.projectsById[projectId]
    return {
        id: projectId,
        name: (p && p.name) || fallbackName || "",
        customer: clientName(p && p.client_id) || "",
        color: DEFAULT_CUSTOMER_COLOR
    }
}

function activityFromIds(taskId, fallbackName) {
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
    var begin = entry.start || ""
    var end = entry.end || null
    var duration = 0
    if (end) {
        duration = Util.durationSecondsFromRange(begin, end)
    } else if (begin) {
        duration = Util.durationSecondsFromRange(begin, null)
    }
    if (entry.duration && !end) {
        duration = Math.max(duration, Util.parseIsoDurationToSeconds(entry.duration))
    }
    return {
        id: entry.id,
        begin: begin,
        end: end,
        duration: duration,
        description: entry.description || "",
        billable: !!entry.billable,
        tags: Fields.tagsFromTimesheet(entry),
        project: projectFromIds(entry.project_id, entry.project && entry.project.name),
        activity: activityFromIds(entry.task_id, entry.task && entry.task.name)
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
    if (!url || !token) {
        callback(Util.fail({ type: "config", status: 0, detail: "" }))
        return
    }
    getJson(url, token, "/users/me", {}, function(userResult) {
        if (!userResult.ok) {
            callback(userResult)
            return
        }
        getJson(url, token, "/users/me/memberships", [], function(membershipResult) {
            if (!membershipResult.ok) {
                callback(membershipResult)
                return
            }
            var memberships = membershipResult.data || []
            var picked = null
            if (_session.organizationId) {
                for (var i = 0; i < memberships.length; i++) {
                    if (memberships[i].organization && memberships[i].organization.id === _session.organizationId) {
                        picked = memberships[i]
                        break
                    }
                }
            }
            if (!picked && memberships.length > 0) {
                picked = memberships[0]
            }
            if (picked) {
                _session.memberId = picked.id || ""
                _session.organizationId = (picked.organization && picked.organization.id) || ""
            }
            var orgs = []
            for (var j = 0; j < memberships.length; j++) {
                var m = memberships[j]
                orgs.push({
                    id: m.organization && m.organization.id,
                    name: m.organization && m.organization.name,
                    memberId: m.id
                })
            }
            var user = userResult.data || {}
            callback(Util.ok({
                version: "SolidTime",
                organizationId: _session.organizationId,
                memberId: _session.memberId,
                userId: user.id,
                organizations: orgs
            }))
        })
    })
}

function fetchActiveTimesheet(url, token, callback) {
    getJson(url, token, "/users/me/time-entries/active", null, function(result) {
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
    withSession(url, token, function(sessionResult) {
        if (!sessionResult.ok) {
            callback(sessionResult)
            return
        }
        var limit = size || 10
        getJson(url, token, orgPath("/time-entries?limit=" + limit + "&offset=0"), [], function(result) {
            if (!result.ok) {
                callback(result)
                return
            }
            var rows = normalizeTimesheets(result.data || [])
            rows.sort(function(a, b) {
                return String(b.begin).localeCompare(String(a.begin))
            })
            callback(Util.ok(rows.slice(0, limit)))
        })
    })
}

function startTracking(url, token, projectId, activityId, description, callback, extras) {
    withSession(url, token, function(sessionResult) {
        if (!sessionResult.ok) {
            callback(sessionResult)
            return
        }
        var extra = extras || {}
        var data = {
            member_id: _session.memberId,
            start: Util.isoUtc(new Date()),
            end: null,
            description: description || "",
            billable: Fields.resolveBillable(extra)
        }
        if (projectId) {
            data.project_id = projectId
        }
        if (activityId) {
            data.task_id = activityId
        }
        request("POST", url, token, orgPath("/time-entries"), JSON.stringify(data), true, function(result) {
            if (result.ok) {
                callback(Util.ok(normalizeTimesheet(Util.unwrapData(result.data))))
            } else {
                callback(result)
            }
        })
    })
}

function stopTracking(url, token, timesheetId, callback) {
    if (!timesheetId) {
        callback(Util.fail({ type: "config", status: 0, detail: "" }))
        return
    }
    withSession(url, token, function(sessionResult) {
        if (!sessionResult.ok) {
            callback(sessionResult)
            return
        }
        var body = { end: Util.isoUtc(new Date()) }
        request("PUT", url, token, orgPath("/time-entries/" + timesheetId), JSON.stringify(body), true, function(result) {
            if (result.ok) {
                callback(Util.ok(normalizeTimesheet(Util.unwrapData(result.data))))
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
        getJson(url, token, orgPath("/time-entries/" + timesheetId), {}, function(entryResult) {
            if (!entryResult.ok) {
                callback(entryResult)
                return
            }
            var entry = entryResult.data || {}
            startTracking(
                url,
                token,
                entry.project_id || "",
                entry.task_id || "",
                entry.description || "",
                callback,
                { billable: !!entry.billable }
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
        getJson(url, token, orgPath("/time-entries/" + timesheetId), {}, function(entryResult) {
            if (!entryResult.ok) {
                callback(entryResult)
                return
            }
            var existing = entryResult.data || {}
            var f = fields || {}
            var payload = {
                description: f.description !== undefined ? f.description : (existing.description || ""),
                billable: Fields.resolveBillable(f, existing)
            }
            if (f.begin !== undefined) {
                var beginDate = new Date(f.begin)
                if (isNaN(beginDate.getTime())) {
                    beginDate = new Date(String(f.begin).replace(" ", "T"))
                }
                payload.start = Util.isoUtc(beginDate)
            } else if (existing.start) {
                payload.start = existing.start
            }
            if (f.end !== undefined) {
                if (f.end) {
                    var endDate = new Date(f.end)
                    if (isNaN(endDate.getTime())) {
                        endDate = new Date(String(f.end).replace(" ", "T"))
                    }
                    payload.end = Util.isoUtc(endDate)
                }
            } else if (existing.end) {
                payload.end = existing.end
            }
            if (f.project !== undefined) {
                payload.project_id = f.project || null
            } else if (existing.project_id) {
                payload.project_id = existing.project_id
            }
            if (f.activity !== undefined) {
                payload.task_id = f.activity || null
            } else if (existing.task_id) {
                payload.task_id = existing.task_id
            }
            request("PUT", url, token, orgPath("/time-entries/" + timesheetId), JSON.stringify(payload), true, function(result) {
                if (result.ok) {
                    callback(Util.ok(normalizeTimesheet(Util.unwrapData(result.data))))
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
        var beginDate = new Date(f.begin)
        if (isNaN(beginDate.getTime())) {
            beginDate = new Date(String(f.begin).replace(" ", "T"))
        }
        var data = {
            member_id: _session.memberId,
            start: Util.isoUtc(beginDate),
            description: f.description || "",
            billable: Fields.resolveBillable(f)
        }
        if (f.end) {
            var endDate = new Date(f.end)
            if (isNaN(endDate.getTime())) {
                endDate = new Date(String(f.end).replace(" ", "T"))
            }
            data.end = Util.isoUtc(endDate)
        }
        if (f.project) {
            data.project_id = f.project
        }
        if (f.activity) {
            data.task_id = f.activity
        }
        request("POST", url, token, orgPath("/time-entries"), JSON.stringify(data), true, function(result) {
            if (result.ok) {
                callback(Util.ok(normalizeTimesheet(Util.unwrapData(result.data))))
            } else {
                callback(result)
            }
        })
    })
}

function deleteTimesheet(url, token, timesheetId, callback) {
    if (!timesheetId) {
        callback(Util.fail({ type: "config", status: 0, detail: "" }))
        return
    }
    withSession(url, token, function(sessionResult) {
        if (!sessionResult.ok) {
            callback(sessionResult)
            return
        }
        request("DELETE", url, token, orgPath("/time-entries/" + timesheetId), "", false, function(result) {
            callback(result)
        })
    })
}

function createCustomer(url, token, fields, callback) {
    var name = String((fields && fields.name) || "").trim()
    if (!name) {
        callback(Util.fail({ type: "config", status: 0, detail: "name is required" }))
        return
    }
    withSession(url, token, function(sessionResult) {
        if (!sessionResult.ok) {
            callback(sessionResult)
            return
        }
        request("POST", url, token, orgPath("/clients"), JSON.stringify({ name: name }), true, function(result) {
            if (!result.ok) {
                callback(result)
                return
            }
            var c = Util.unwrapData(result.data) || {}
            _session.clientsById[c.id] = c
            callback(Util.ok({
                id: c.id,
                name: c.name || name,
                color: DEFAULT_CUSTOMER_COLOR
            }))
        })
    })
}

function createProject(url, token, fields, callback) {
    var f = fields || {}
    var name = String(f.name || "").trim()
    if (!name || !f.customer) {
        callback(Util.fail({ type: "config", status: 0, detail: "name and customer are required" }))
        return
    }
    withSession(url, token, function(sessionResult) {
        if (!sessionResult.ok) {
            callback(sessionResult)
            return
        }
        var payload = {
            name: name,
            client_id: f.customer,
            billable: Fields.resolveBillable(f)
        }
        request("POST", url, token, orgPath("/projects"), JSON.stringify(payload), true, function(result) {
            if (!result.ok) {
                callback(result)
                return
            }
            var p = Util.unwrapData(result.data) || {}
            _session.projectsById[p.id] = p
            callback(Util.ok({
                id: p.id,
                name: p.name || name,
                customer: f.customer,
                color: DEFAULT_CUSTOMER_COLOR
            }))
        })
    })
}

function createActivity(url, token, fields, callback) {
    var f = fields || {}
    var name = String(f.name || "").trim()
    if (!name || !f.project) {
        callback(Util.fail({ type: "config", status: 0, detail: "name and project are required" }))
        return
    }
    withSession(url, token, function(sessionResult) {
        if (!sessionResult.ok) {
            callback(sessionResult)
            return
        }
        var payload = {
            name: name,
            project_id: f.project
        }
        request("POST", url, token, orgPath("/tasks"), JSON.stringify(payload), true, function(result) {
            if (!result.ok) {
                callback(result)
                return
            }
            var t = Util.unwrapData(result.data) || {}
            _session.tasksById[t.id] = t
            callback(Util.ok({
                id: t.id,
                name: t.name || name,
                project: f.project
            }))
        })
    })
}

function loadCustomers(url, token, callback) {
    withSession(url, token, function(sessionResult) {
        if (!sessionResult.ok) {
            callback(sessionResult)
            return
        }
        getJson(url, token, orgPath("/clients?archived=false"), [], function(result) {
            if (!result.ok) {
                callback(result)
                return
            }
            var list = result.data || []
            _session.clientsById = {}
            var rows = []
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
        getJson(url, token, orgPath("/projects?archived=false"), [], function(result) {
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
                    color: DEFAULT_CUSTOMER_COLOR
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
        var query = orgPath("/tasks?project_id=" + encodeURIComponent(projectId) + "&done=false")
        getJson(url, token, query, [], function(result) {
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
        getJson(url, token, orgPath("/time-entries?start=" + start + "&end=" + end + "&limit=1000&offset=0"), [], function(result) {
            if (!result.ok) {
                callback(result)
                return
            }
            callback(Util.ok(normalizeTimesheets(result.data || [])))
        })
    })
}

function fetchCurrentUser(url, token, callback) {
    getJson(url, token, "/users/me", {}, function(result) {
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
