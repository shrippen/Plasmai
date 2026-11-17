.pragma library

function defaultProfiles() {
    return [{ id: "default", name: "Default", url: "", provider: "kimai" }]
}

function parseProfiles(jsonStr, legacyUrl) {
    if (jsonStr) {
        try {
            var parsed = JSON.parse(jsonStr)
            if (Array.isArray(parsed) && parsed.length > 0) {
                var out = []
                for (var i = 0; i < parsed.length; i++) {
                    out.push(normalizeProfile(parsed[i]))
                }
                return out
            }
        } catch (e) {
        }
    }
    if (legacyUrl) {
        return [normalizeProfile({ id: "default", name: "Default", url: legacyUrl, provider: "kimai" })]
    }
    return defaultProfiles()
}

function profileById(profiles, id) {
    if (!profiles || profiles.length === 0) {
        return null
    }
    for (var i = 0; i < profiles.length; i++) {
        if (profiles[i].id === id) {
            return profiles[i]
        }
    }
    return profiles[0]
}

/** Show the "Connected to …" line: only with several profiles, or while not connected. */
function showsConnection(profiles, configured, state) {
    if (!configured || state !== "online") {
        return true
    }
    return (profiles || []).length > 1
}

/** Profiles plus the demo profile (id "demo"); an unused default profile without URL is dropped. */
function withDemoProfile(profiles, demoUrl, name) {
    var out = []
    for (var i = 0; i < (profiles || []).length; i++) {
        var p = profiles[i]
        if (p.id === "demo" || (!p.url && p.id === "default")) {
            continue
        }
        out.push(p)
    }
    out.push(normalizeProfile({ id: "demo", name: name, url: demoUrl, provider: "kimai" }))
    return out
}

function serializeProfiles(profiles) {
    return JSON.stringify(profiles || defaultProfiles())
}

function newProfileId() {
    return "profile-" + Date.now()
}

function normalizeProfile(profile) {
    var p = profile || {}
    return {
        id: p.id || newProfileId(),
        name: p.name || "Profile",
        url: p.url || "",
        provider: p.provider || "kimai",
        workspaceId: p.workspaceId || "",
        userId: p.userId || "",
        organizationId: p.organizationId || "",
        memberId: p.memberId || ""
    }
}

function validIndex(profiles, index) {
    return !!profiles && index >= 0 && index < profiles.length
}

/** Position of the active profile; 0 when it is unknown. */
function activeIndex(profiles, activeId) {
    for (var i = 0; i < (profiles || []).length; i++) {
        if (profiles[i].id === activeId) {
            return i
        }
    }
    return 0
}

/** A profile list with one profile's field set. */
function withField(profiles, index, field, value) {
    if (!validIndex(profiles, index)) {
        return profiles
    }
    var copy = profiles.slice()
    var row = Object.assign({}, copy[index])
    row[field] = value
    copy[index] = row
    return copy
}

/** Switch a profile's service: take its default URL and forget the ids of the old one. */
function withProvider(profiles, index, providerId, defaultUrl) {
    if (!validIndex(profiles, index)) {
        return profiles
    }
    // The same service picked again (a ComboBox reports that too): nothing changes.
    if (profiles[index].provider === providerId) {
        return profiles
    }
    var copy = profiles.slice()
    copy[index] = Object.assign({}, copy[index], {
        provider: providerId,
        url: defaultUrl || "",
        workspaceId: "",
        userId: "",
        organizationId: "",
        memberId: ""
    })
    return copy
}

/** The ids a connection test reports (workspace, user, ...) set on one profile; empty ones change nothing. */
function withTestMeta(profiles, index, data) {
    if (!data || !validIndex(profiles, index)) {
        return profiles
    }
    var copy = profiles.slice()
    var row = Object.assign({}, copy[index])
    var keys = ["workspaceId", "userId", "organizationId", "memberId"]
    for (var i = 0; i < keys.length; i++) {
        if (data[keys[i]]) {
            row[keys[i]] = data[keys[i]]
        }
    }
    copy[index] = row
    return copy
}

/** Append a Kimai profile; nameOf(n) words its name, n is the first free number. */
function withNewProfile(profiles, nameOf) {
    var taken = {}
    for (var i = 0; i < profiles.length; i++) {
        taken[profiles[i].name] = true
    }
    var num = profiles.length + 1
    while (taken[nameOf(num)]) {
        num++
    }
    var copy = profiles.slice()
    copy.push(normalizeProfile({ id: newProfileId(), name: nameOf(num), url: "", provider: "kimai" }))
    return copy
}

/** Without the profile at index; the last one stays. */
function withoutProfile(profiles, index) {
    if (profiles.length <= 1 || !validIndex(profiles, index)) {
        return profiles
    }
    var copy = profiles.slice()
    copy.splice(index, 1)
    return copy
}

/** The list itself, or the default profile (with the normalized URL) when it is empty. */
function ensured(profiles, url) {
    if (profiles.length > 0) {
        return profiles
    }
    var out = defaultProfiles()
    out[0].url = url || ""
    return out
}
