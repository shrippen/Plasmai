.pragma library
.import "./providerUtil.js" as ProviderUtil

/**
 * Ids and names of projects, activities and customers in timesheets and catalogs,
 * and the name order. Accepts a bare id or an embedded object, as Kimai sends both.
 */

function activityProjectId(activity) {
    if (!activity || activity.project === null || activity.project === undefined || activity.project === "") {
        return 0
    }
    if (typeof activity.project === "object") {
        return activity.project.id || 0
    }
    return activity.project
}

function customerIdOfProject(project) {
    if (!project || project.customer === null || project.customer === undefined) {
        return 0
    }
    if (typeof project.customer === "object") {
        return project.customer.id || 0
    }
    return project.customer
}

function buildCustomersById(customers) {
    var map = {}
    for (var i = 0; i < (customers || []).length; i++) {
        var customer = customers[i]
        map[customer.id] = {
            id: customer.id,
            name: customer.name || "",
            color: ProviderUtil.normalizeCustomerColor(customer.color)
        }
    }
    return map
}

function customerNameOfProject(project, customersById) {
    if (!project) {
        return ""
    }
    if (typeof project.customer === "object" && project.customer && project.customer.name) {
        return project.customer.name
    }
    var cid = customerIdOfProject(project)
    if (cid && customersById && customersById[cid]) {
        return customersById[cid].name || customersById[cid]
    }
    return ""
}

function customerNameFromTimesheet(timesheet, customersById) {
    if (!timesheet || !timesheet.project) {
        return ""
    }
    return customerNameOfProject(timesheet.project, customersById)
}

/** Sort key: lower case without accents, so the list reads Aa→Zz with "ä" beside "a". */
function nameKey(name) {
    return String(name || "").normalize("NFD").replace(/[\u0300-\u036f]/g, "").toLowerCase()
}

/** Names Aa→Zz; Android's localeCompare alone would put every capital first. */
function compareNames(a, b) {
    var x = nameKey(a)
    var y = nameKey(b)
    if (x !== y) {
        return x < y ? -1 : 1
    }
    return String(a) < String(b) ? -1 : (String(a) > String(b) ? 1 : 0)
}

function byName(a, b) {
    return compareNames(a && a.name, b && b.name)
}

/** ISO currency code of the project's customer from the loaded catalog, or "". */
function customerCurrencyOfProject(project, customers) {
    if (!project) {
        return ""
    }
    if (typeof project.customer === "object" && project.customer && project.customer.currency) {
        return String(project.customer.currency)
    }
    var cid = customerIdOfProject(project)
    for (var i = 0; i < (customers || []).length; i++) {
        if (customers[i] && String(customers[i].id) === String(cid)) {
            return customers[i].currency ? String(customers[i].currency) : ""
        }
    }
    return ""
}

/**
 * Kimai collection endpoints often return project/activity as bare IDs;
 * detail/recent endpoints embed objects. Accept both.
 */
function entityId(value) {
    if (value === null || value === undefined || value === "") {
        return 0
    }
    if (typeof value === "object") {
        return value.id || 0
    }
    return value
}

function entityName(value) {
    if (!value || typeof value !== "object") {
        return ""
    }
    return value.name || value.title || ""
}

function projectName(timesheet) {
    if (!timesheet) {
        return ""
    }
    return entityName(timesheet.project)
}

function activityName(timesheet) {
    if (!timesheet) {
        return ""
    }
    return entityName(timesheet.activity)
}

/**
 * Best-effort display name: embedded → catalog → empty (caller may show "#id").
 */
function displayActivityName(timesheet, activities, activitiesByProject) {
    if (!timesheet) {
        return ""
    }
    var n = activityName(timesheet)
    if (n) {
        return n
    }
    return resolveActivityName(timesheet, activitiesIndexFromCache(activities, activitiesByProject))
}

function displayProjectName(timesheet, projects) {
    if (!timesheet) {
        return ""
    }
    var n = projectName(timesheet)
    if (n) {
        return n
    }
    return resolveProjectName(timesheet, indexById(projects))
}

/**
 * Resolve a display name, preferring embedded entity name then an id→entity map.
 */
function resolveEntityName(value, byId) {
    var n = entityName(value)
    if (n) {
        return n
    }
    var id = entityId(value)
    if (id && byId) {
        var hit = byId[id] || byId[String(id)]
        if (hit) {
            return entityName(hit) || ""
        }
    }
    return ""
}

function resolveActivityName(timesheet, activitiesById) {
    if (!timesheet) {
        return ""
    }
    return resolveEntityName(timesheet.activity, activitiesById)
}

function resolveProjectName(timesheet, projectsById) {
    if (!timesheet) {
        return ""
    }
    return resolveEntityName(timesheet.project, projectsById)
}

function projectId(timesheet) {
    if (!timesheet) {
        return 0
    }
    return entityId(timesheet.project)
}

function activityId(timesheet) {
    if (!timesheet) {
        return 0
    }
    return entityId(timesheet.activity)
}

function indexById(list) {
    var map = {}
    for (var i = 0; i < (list || []).length; i++) {
        var item = list[i]
        if (!item || item.id === null || item.id === undefined) {
            continue
        }
        map[String(item.id)] = item
    }
    return map
}

function activitiesIndexFromCache(activities, activitiesByProject) {
    var map = indexById(activities)
    var byProject = activitiesByProject || {}
    for (var key in byProject) {
        if (!byProject.hasOwnProperty(key)) {
            continue
        }
        var list = byProject[key] || []
        for (var i = 0; i < list.length; i++) {
            var act = list[i]
            if (act && act.id !== null && act.id !== undefined) {
                map[String(act.id)] = act
            }
        }
    }
    return map
}
