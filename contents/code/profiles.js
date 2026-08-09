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
        return [{ id: "default", name: "Default", url: legacyUrl, provider: "kimai" }]
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

function serializeProfiles(profiles) {
    var list = profiles || defaultProfiles()
    var out = []
    for (var i = 0; i < list.length; i++) {
        out.push(normalizeProfile(list[i]))
    }
    return JSON.stringify(out)
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
        provider: p.provider || "kimai"
    }
}

function accountForProfile(profileId) {
    if (!profileId || profileId === "default") {
        return "api-token"
    }
    return "api-token:" + profileId
}
