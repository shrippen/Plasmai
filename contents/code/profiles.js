.pragma library

function defaultProfiles() {
    return [{ id: "default", name: "Default", url: "" }]
}

function parseProfiles(jsonStr, legacyUrl) {
    if (jsonStr) {
        try {
            var parsed = JSON.parse(jsonStr)
            if (Array.isArray(parsed) && parsed.length > 0) {
                return parsed
            }
        } catch (e) {
        }
    }
    if (legacyUrl) {
        return [{ id: "default", name: "Default", url: legacyUrl }]
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
    return JSON.stringify(profiles || defaultProfiles())
}

function newProfileId() {
    return "profile-" + Date.now()
}

function normalizeProfile(profile) {
    return {
        id: profile.id || newProfileId(),
        name: profile.name || "Profile",
        url: profile.url || ""
    }
}

function accountForProfile(profileId) {
    if (!profileId || profileId === "default") {
        return "api-token"
    }
    return "api-token:" + profileId
}
