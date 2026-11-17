.pragma library
.import "./entityColors.js" as Colors
.import "./entityNames.js" as Names

/**
 * The lists the pickers show: projects grouped by customer, activities of a
 * project, without hidden entries.
 */

function splitActivitiesForProject(activities, projectId) {
    var projectSpecific = []
    var globalActivities = []
    var list = activities || []
    for (var i = 0; i < list.length; i++) {
        var activity = list[i]
        var pid = Names.activityProjectId(activity)
        if (!pid) {
            globalActivities.push(activity)
        } else if (String(pid) === String(projectId)) {
            projectSpecific.push(activity)
        }
    }
    return { projectSpecific: projectSpecific, global: globalActivities }
}

function activitiesListModel(activities, projectId) {
    var split = splitActivitiesForProject(activities, projectId)
    split.projectSpecific.sort(Names.byName)
    split.global.sort(Names.byName)
    var rows = []
    var i
    for (i = 0; i < split.projectSpecific.length; i++) {
        rows.push({
            section: "project",
            activity: split.projectSpecific[i]
        })
    }
    for (i = 0; i < split.global.length; i++) {
        rows.push({
            section: "global",
            activity: split.global[i]
        })
    }
    return rows
}

function projectsGroupedByCustomer(projects, customers) {
    var customersById = Names.buildCustomersById(customers)

    var groups = {}
    var order = []
    var i
    for (i = 0; i < (projects || []).length; i++) {
        var project = projects[i]
        var name = Names.customerNameOfProject(project, customersById) || "Other"
        if (!groups[name]) {
            groups[name] = {
                // Section bars always use the customer color
                color: Colors.customerBarColor(project, customersById),
                customerId: Names.customerIdOfProject(project),
                projects: []
            }
            order.push(name)
        }
        groups[name].projects.push(project)
    }

    order.sort(function(a, b) {
        if (a === "Other") {
            return 1
        }
        if (b === "Other") {
            return -1
        }
        return Names.compareNames(a, b)
    })

    var rows = []
    for (i = 0; i < order.length; i++) {
        var customerName = order[i]
        var group = groups[customerName]
        var list = group.projects
        list.sort(Names.byName)
        for (var p = 0; p < list.length; p++) {
            var proj = list[p]
            var bar = Colors.barColorInfo(null, proj, customersById)
            rows.push({
                customerName: customerName,
                customerId: group.customerId,
                customerColor: group.color,
                projectColor: bar.color,
                project: proj
            })
        }
    }
    return rows
}

/** Kimai lists are loaded with visible=3 (incl. hidden) so names still resolve. */
function isHiddenEntity(entity) {
    return !!entity && typeof entity === "object" && entity.visible === false
}

/** Projects that may be picked for new time: project and its customer visible. */
function visibleProjects(projects, customers) {
    var hiddenCustomers = {}
    var i
    for (i = 0; i < (customers || []).length; i++) {
        if (isHiddenEntity(customers[i])) {
            hiddenCustomers[String(customers[i].id)] = true
        }
    }
    var out = []
    for (i = 0; i < (projects || []).length; i++) {
        var project = projects[i]
        if (isHiddenEntity(project) || isHiddenEntity(project && project.customer)) {
            continue
        }
        if (hiddenCustomers[String(Names.customerIdOfProject(project))]) {
            continue
        }
        out.push(project)
    }
    return out
}

function visibleActivities(activities) {
    var out = []
    for (var i = 0; i < (activities || []).length; i++) {
        if (!isHiddenEntity(activities[i])) {
            out.push(activities[i])
        }
    }
    return out
}

function projectPickerItems(projects, customers) {
    var rows = projectsGroupedByCustomer(visibleProjects(projects, customers), customers)
    var items = []
    for (var i = 0; i < rows.length; i++) {
        var row = rows[i]
        var customerName = row.customerName || ""
        var projectName = (row.project && row.project.name) || ""
        items.push({
            label: projectName,
            searchText: customerName + " " + projectName,
            section: customerName,
            // Section header uses customer color; row uses project cascade
            color: row.customerColor,
            rowColor: row.projectColor,
            value: row.project
        })
    }
    return items
}

function activityPickerItems(activities, projectId, project, customersById) {
    var rows = activitiesListModel(visibleActivities(activities), projectId)
    var items = []
    for (var i = 0; i < rows.length; i++) {
        var activity = rows[i].activity
        var bar = Colors.barColorInfo(activity, project || null, customersById || {})
        items.push({
            label: activity.name || activity.title || ("#" + activity.id),
            searchText: (activity.name || activity.title || "") + " " + activity.id,
            section: rows[i].section,
            color: bar.color,
            value: activity
        })
    }
    return items
}
