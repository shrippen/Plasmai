.pragma library
.import "./entityNames.js" as Names
.import "./providerUtil.js" as ProviderUtil

/**
 * Colors of customers, projects and activities: the explicit color, else the
 * project's, else the customer's. Every service shows the same colors.
 */

/** True when Kimai provided an explicit color (non-empty). */
function hasExplicitColor(value) {
    return String(value || "").trim().length > 0
}

/**
 * Kimai display color cascade:
 *   activity → project → customer → default
 */
function activityColor(activity) {
    if (activity && typeof activity === "object" && hasExplicitColor(activity.color)) {
        return ProviderUtil.normalizeCustomerColor(activity.color)
    }
    return ""
}

function projectColor(project) {
    if (project && typeof project === "object" && hasExplicitColor(project.color)) {
        return ProviderUtil.normalizeCustomerColor(project.color)
    }
    return ""
}

function customerColorOnly(project, customersById) {
    if (!project || typeof project !== "object") {
        return ""
    }
    if (project.customer && typeof project.customer === "object" && hasExplicitColor(project.customer.color)) {
        return ProviderUtil.normalizeCustomerColor(project.customer.color)
    }
    var cid = Names.customerIdOfProject(project)
    if (cid && customersById) {
        var cust = customersById[cid] || customersById[String(cid)]
        if (cust && hasExplicitColor(cust.color)) {
            return ProviderUtil.normalizeCustomerColor(cust.color)
        }
    }
    return ""
}

/** Customer bar color, for section headers and customer pills. */
function customerBarColor(project, customersById) {
    return customerColorOnly(project, customersById) || ProviderUtil.DEFAULT_CUSTOMER_COLOR
}

/**
 * Resolve the hierarchy color for a bar: activity → project → customer → default.
 * Returns { color, category, id }.
 */
function barColorInfo(activity, project, customersById) {
    var ac = activityColor(activity)
    if (ac && activity && activity.id !== null && activity.id !== undefined) {
        return {
            color: ac,
            category: "activity",
            id: activity.id
        }
    }
    var pc = projectColor(project)
    if (pc && project && project.id !== null && project.id !== undefined) {
        return {
            color: pc,
            category: "project",
            id: project.id
        }
    }
    var cid = Names.customerIdOfProject(project)
    var cc = customerColorOnly(project, customersById) || ProviderUtil.DEFAULT_CUSTOMER_COLOR
    return {
        color: cc,
        category: "customer",
        id: cid || null
    }
}

function barColorInfoFromTimesheet(timesheet, customersById) {
    if (!timesheet) {
        return { color: ProviderUtil.DEFAULT_CUSTOMER_COLOR, category: "", id: null }
    }
    var activity = (typeof timesheet.activity === "object" && timesheet.activity) ? timesheet.activity : null
    var project = (typeof timesheet.project === "object" && timesheet.project) ? timesheet.project : null
    return barColorInfo(activity, project, customersById)
}

/**
 * Customer / project colors for compact panel pills.
 * Project falls back to the customer color when Kimai has no project color.
 */
function panelPillInfo(timesheet, projects, customersById) {
    var empty = {
        customerColor: ProviderUtil.DEFAULT_CUSTOMER_COLOR,
        customerId: null,
        projectColor: ProviderUtil.DEFAULT_CUSTOMER_COLOR,
        projectId: null
    }
    if (!timesheet) {
        return empty
    }
    var project = (typeof timesheet.project === "object" && timesheet.project)
        ? timesheet.project
        : null
    if (!project) {
        var pid = Names.projectId(timesheet)
        var byId = Names.indexById(projects)
        project = byId[pid] || byId[String(pid)] || null
    }
    var cid = Names.customerIdOfProject(project)
    var cc = customerColorOnly(project, customersById) || ProviderUtil.DEFAULT_CUSTOMER_COLOR
    var pc = projectColor(project) || cc
    return {
        customerColor: cc,
        customerId: cid || null,
        projectColor: pc,
        projectId: Names.projectId(timesheet) || null
    }
}

/** Project colour, else customer colour, else default. */
function projectBarColor(project, customersById) {
    return barColorInfo(null, project, customersById).color
}

/** Activity colour, else project, else customer, else default. */
function timesheetBarColor(timesheet, customersById) {
    return barColorInfoFromTimesheet(timesheet, customersById).color
}
