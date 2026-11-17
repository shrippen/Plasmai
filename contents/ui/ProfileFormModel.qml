import QtQml
import "../code/profiles.js" as Profiles
import "../code/providerUtil.js" as ProviderUtil

/**
 * The profile list the Connection form edits (Plasma settings page and app page):
 * the list, the selected profile and the actions on it. The pages only bind their
 * fields to it, serialize on `edited` and store.
 *
 *   field typed ─▶ updateSelected ─▶ profiles ─▶ edited()
 *   select / add / remove / setActive ─▶ fieldsReset() ─▶ page copies selectedProfile
 */
QtObject {
    id: form

    /** The session (its setup part words the services). */
    property QtObject session: null
    /** Every service in display order (id, name, needsUrl, defaultUrl, …). */
    property var providers: []
    property var profiles: []
    property int selectedIndex: 0
    /** Set while the page copies values into its fields: their change signals are not edits. */
    property bool updatingFields: false
    /** Set while the page loads or serializes the list. */
    property bool syncing: false

    readonly property var selectedProfile: Profiles.validIndex(profiles, selectedIndex) ? profiles[selectedIndex] : null
    readonly property string selectedProviderId: selectedProfile && selectedProfile.provider ? selectedProfile.provider : "kimai"
    readonly property var selectedProviderMeta: session.setup.providerMeta(selectedProviderId)
    readonly property int selectedProviderIndex: {
        const idx = providers.map(function(p) { return p.id }).indexOf(selectedProviderId)
        return idx >= 0 ? idx : 0
    }

    /** The page copies selectedProfile and selectedIndex into its fields. */
    signal fieldsReset()
    /** Only the URL field changed (normalized). */
    signal urlReset()
    /** The list changed: the page serializes and stores it. */
    signal edited()
    /** The service was switched: the page drops its status line. */
    signal providerSwitched()

    readonly property bool locked: updatingFields || syncing || profiles.length === 0 || selectedIndex < 0

    function resetFields() {
        if (profiles.length === 0 || selectedIndex < 0) {
            return
        }
        updatingFields = true
        fieldsReset()
        updatingFields = false
    }

    /** Selects the active profile; an empty list becomes the default profile with `fallbackUrl`. */
    function ensureSelection(activeId, fallbackUrl) {
        if (profiles.length === 0) {
            profiles = Profiles.ensured(profiles, ProviderUtil.normalizeUrl(fallbackUrl))
            edited()
        }
        selectedIndex = Profiles.activeIndex(profiles, activeId)
        resetFields()
    }

    function select(index) {
        selectedIndex = index
        resetFields()
    }

    function updateSelected(field, value) {
        if (locked) {
            return
        }
        profiles = Profiles.withField(profiles, selectedIndex, field, value)
        edited()
    }

    /** Sets the name; false when another profile has it already (nothing changes then). */
    function rename(text) {
        const trimmed = text.trim()
        for (let i = 0; i < profiles.length; i++) {
            if (i !== selectedIndex && profiles[i].name === trimmed) {
                return false
            }
        }
        updateSelected("name", text)
        return true
    }

    /** Switch service: clear URL and session ids, prefill the service's default URL. */
    function changeProvider(providerId) {
        if (locked) {
            return
        }
        const url = session.setup.providerMeta(providerId).defaultUrl || ""
        profiles = Profiles.withProvider(profiles, selectedIndex, providerId, url)
        edited()
        updatingFields = true
        urlReset()
        updatingFields = false
        providerSwitched()
    }

    /** Stores the URL field's text normalized; the field shows the normalized text. */
    function commitUrl(text) {
        if (locked) {
            return
        }
        const normalized = ProviderUtil.normalizeUrl(text)
        updateSelected("url", normalized)
        if (text === normalized) {
            return
        }
        updatingFields = true
        urlReset()
        updatingFields = false
    }

    /** Commits the URL and returns the id of the selected profile, which becomes the active one. */
    function activate(urlText) {
        if (profiles.length === 0 || selectedIndex < 0) {
            return ""
        }
        commitUrl(urlText)
        updatingFields = true
        urlReset()
        updatingFields = false
        return selectedProfile.id
    }

    /** nameOf(n) words a new profile's name. */
    function add(nameOf) {
        profiles = Profiles.withNewProfile(profiles, nameOf)
        edited()
        selectedIndex = profiles.length - 1
        resetFields()
    }

    /** Removes the selected profile; true when it was `activeId` (the page activates the new selection). */
    function removeSelected(activeId) {
        if (profiles.length <= 1) {
            return false
        }
        const removedId = profiles[selectedIndex].id
        profiles = Profiles.withoutProfile(profiles, selectedIndex)
        edited()
        selectedIndex = Math.max(0, selectedIndex - 1)
        resetFields()
        return activeId === removedId
    }

    /** Sets the ids a connection test reported on the profile `id` of the current list; only while it still has the `provider` and `url` the test began with. */
    function applyTested(id, data, provider, url) {
        const current = profiles.find(function(p) { return p.id === id })
        if (!current || current.provider !== provider
                || ProviderUtil.normalizeUrl(current.url) !== ProviderUtil.normalizeUrl(url)) {
            return
        }
        const next = Profiles.withTestMeta(profiles, id, data)
        if (next === profiles) {
            return
        }
        profiles = next
        edited()
    }
}
