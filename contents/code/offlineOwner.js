.pragma library
.import "./providerUtil.js" as ProviderUtil
.import "./offlineState.js" as OfflineState

/**
 * Whose changes are waiting. The outbox and the snapshot belong to an owner, the server and
 * the account the changes were made for (`{ server, account, name }`; the name is for display).
 * Another server or account never gets them and never sees them laid over its answers: they
 * are parked in `held`, one group per owner, until the user sends or discards them.
 *
 *   settle(identity):  owner ──same──► nothing
 *                        │ other server / verified other account
 *                        ▼
 *                      ops ──► held[owner]     snapshot emptied     owner = identity
 *                      held group of the identity ──► ops again (back on the old address)
 *
 * An owner without an account is a server that was not checked yet (offline): ops are kept
 * and nothing is sent until the account is known. Pure functions on the session object.
 */

var Result = {
    NONE: "none",
    // The owner of a file without one was set (after the first good check).
    CLAIMED: "claimed",
    // The account of an owner that knew only its server was learned.
    FILLED: "filled",
    // A held group of the identity went back into the queue.
    RESUMED: "resumed",
    // Another owner: the ops were parked, the snapshot emptied.
    PARKED: "parked"
}

var DEFAULT_PORT = { http: "80", https: "443" }
var ADDRESS = /^([a-z][a-z0-9+.-]*):\/\/([^\/?#]*)(.*)$/i

/**
 * The server of an address: the same server whatever its spelling may be at the end
 * (slash), in scheme and host (case) and in the standard port. Anything else (http or
 * https, IP or name, a path) is another server: the user decides once.
 */
function serverOf(url) {
    var text = ProviderUtil.normalizeUrl(url)
    var parts = ADDRESS.exec(text)
    if (!parts) {
        return text
    }
    var scheme = parts[1].toLowerCase()
    var host = parts[2].toLowerCase().replace(/:(\d+)$/, function(all, port) {
        return port === DEFAULT_PORT[scheme] ? "" : all
    })
    return scheme + "://" + host + parts[3]
}

function clone(value) {
    return JSON.parse(JSON.stringify(value))
}

function sameOwner(a, b) {
    return a.server === b.server && a.account === b.account
}

/** Both known to be one server and no known difference in the account. */
function compatible(a, b) {
    return a.server === b.server && (!a.account || !b.account || a.account === b.account)
}

function groupOf(s, owner) {
    for (var i = 0; i < s.held.length; i++) {
        if (sameOwner(s.held[i].owner, owner)) {
            return s.held[i]
        }
    }
    return null
}

function park(s, now) {
    s.snapshot = OfflineState.emptySnapshot()
    if (!s.ops.length) {
        return
    }
    var group = groupOf(s, s.owner)
    if (group) {
        group.ops = group.ops.concat(s.ops)
    } else {
        s.held.push({ owner: clone(s.owner), ops: s.ops, heldAt: now || Date.now() })
    }
    s.ops = []
}

/** The held group of the owner goes back into the queue, in front of what was made meanwhile. */
function resume(s) {
    var group = groupOf(s, s.owner)
    if (!group) {
        return false
    }
    s.held = s.held.filter(function(g) { return g !== group })
    s.ops = group.ops.concat(s.ops)
    return true
}

/**
 * Brings the session's owner in line with `identity` ({ server, account, name }; account ""
 * while not checked). Returns what happened (Result). Without a server (no address yet)
 * nothing is decided. A snapshot of another owner is dropped on the way.
 */
function settle(s, identity, now) {
    if (!identity || !identity.server) {
        return Result.NONE
    }
    var result = Result.NONE
    if (!s.owner) {
        if (!identity.account) {
            return Result.NONE
        }
        s.owner = clone(identity)
        result = Result.CLAIMED
    } else if (!compatible(s.owner, identity)) {
        park(s, now)
        s.owner = clone(identity)
        result = Result.PARKED
    } else if (identity.account && !s.owner.account) {
        s.owner.account = identity.account
        s.owner.name = identity.name
        result = Result.FILLED
    } else if (identity.name) {
        s.owner.name = identity.name
    }
    if (s.owner.account && resume(s) && result !== Result.PARKED) {
        result = Result.RESUMED
    }
    if (s.snapshot.owner && !compatible(s.snapshot.owner, s.owner)) {
        s.snapshot = OfflineState.emptySnapshot()
    }
    return result
}

// -- Held groups ----------------------------------------------------------------

/** A group may be sent here when it was made on another address of the same account. */
function canAdopt(s, group) {
    return !!s.verified && !!s.owner && !!group.owner.account
        && group.owner.server !== s.owner.server && group.owner.account === s.owner.account
}

function ownerName(owner) {
    return owner.name || owner.account || ""
}

/** The groups for the lists: owner, count, whether they can be sent here. */
function groups(s) {
    return s.held.map(function(group, index) {
        return { index: index, name: ownerName(group.owner), server: group.owner.server,
                 account: group.owner.account, count: group.ops.length, heldAt: group.heldAt,
                 to: s.owner ? s.owner.server : "",
                 canAdopt: canAdopt(s, group), ops: clone(group.ops) }
    })
}

function heldCount(s) {
    return s.held.reduce(function(sum, group) { return sum + group.ops.length }, 0)
}

/**
 * The group's ops go behind the queue, pending again: what blocked them (a refusal, a
 * conflict, a forced overwrite) was said to another server. Their base stays, so every
 * server entry is read again and a difference is a conflict, nothing is overwritten blind.
 */
function adopt(s, index) {
    var group = s.held[index]
    if (!group || !canAdopt(s, group)) {
        return false
    }
    s.held.splice(index, 1)
    for (var i = 0; i < group.ops.length; i++) {
        var op = group.ops[i]
        op.state = OfflineState.State.PENDING
        op.error = null
        delete op.server
        delete op.force
    }
    s.ops = s.ops.concat(group.ops)
    return true
}

function dropGroup(s, index) {
    if (!s.held[index]) {
        return false
    }
    s.held.splice(index, 1)
    return true
}
