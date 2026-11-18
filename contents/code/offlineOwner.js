.pragma library
.import "./providerUtil.js" as ProviderUtil
.import "./offlineState.js" as OfflineState

/**
 * Whose changes are waiting. A connection is an address and a token: its key is the server
 * (`serverOf`) and a hash of the token (`markOf`, never the token). Every waiting change (op)
 * is stamped with the key it was made on (`op.by`) and a replay sends it over that key only.
 * The account is what the server says of a connection (`/api/users/me`), checked later and
 * kept in the owner: `{ server, mark, account, name }` (the name is for display).
 * Changes of another key never go out on their own and never show over the answers of the
 * connection in use: they wait in `held`, one group per owner, until the connection of their
 * key is back or the user sends or discards them.
 *
 *   settle(identity)
 *     key of the connection ≠ key of the owner ─► owner = identity, ops of the old key ─► held
 *     same key, other account (checked) ─────────► ops under the old account ─► held
 *     a group of this connection (account empty or the same) ─► back into the queue, stamped
 *     a group of the same account and server, other token (renewed) ─► the same
 *
 * An owner without an account is a connection that was not checked yet (offline): ops are
 * kept and nothing is sent until the account is known. Pure functions on the session object.
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

/** A short hash of a token (never the token): tells one token from another, 0 for none. */
function markOf(token) {
    var text = String(token || "")
    var hash = 0
    for (var i = 0; i < text.length; i++) {
        hash = (Math.imul(hash, 31) + text.charCodeAt(i)) | 0
    }
    return text ? (hash || 1) : 0
}

function clone(value) {
    return JSON.parse(JSON.stringify(value))
}

function sameKey(a, b) {
    return !!a && !!b && a.server === b.server && a.mark === b.mark
}

/** No known difference between two accounts ("" = not known yet). */
function accountsFit(a, b) {
    return !a || !b || a === b
}

function stamp(op, key) {
    op.by = { server: key.server, mark: key.mark }
}

function stampUnowned(ops, key) {
    for (var i = 0; i < ops.length; i++) {
        if (!ops[i].by) {
            stamp(ops[i], key)
        }
    }
}

function newGroupId(s) {
    s.counter = (s.counter || 0) + 1
    return "group:" + s.counter
}

/** The group of a key and account (made if there is none). */
function groupOf(s, key, account, name, now) {
    for (var i = 0; i < s.held.length; i++) {
        var owner = s.held[i].owner
        if (sameKey(owner, key) && owner.account === account) {
            return s.held[i]
        }
    }
    var group = { id: newGroupId(s), owner: { server: key.server, mark: key.mark, account: account, name: name },
                  ops: [], heldAt: now || Date.now() }
    s.held.push(group)
    return group
}

/**
 * Moves the ops of the queue that `picked(op)` says yes to into the group of their own key. The group
 * has the account and name of `owner` when that is the key they were made on (else none).
 * Returns whether any op moved.
 */
function park(s, picked, owner, now) {
    var kept = []
    for (var i = 0; i < s.ops.length; i++) {
        var op = s.ops[i]
        if (!picked(op)) {
            kept.push(op)
            continue
        }
        var mine = sameKey(owner, op.by)
        groupOf(s, op.by, mine ? owner.account : "", mine ? owner.name : "", now).ops.push(op)
    }
    var moved = kept.length !== s.ops.length
    s.ops = kept
    return moved
}

/** Fills the account of the groups of the connection in use, then joins groups that are the same now. */
function fillGroups(s) {
    var owner = s.owner
    if (!owner.account) {
        return
    }
    var joined = []
    for (var i = 0; i < s.held.length; i++) {
        var group = s.held[i]
        if (sameKey(group.owner, owner) && !group.owner.account) {
            group.owner.account = owner.account
            group.owner.name = owner.name
        }
        var twin = joined.filter(function(g) {
            return sameKey(g.owner, group.owner) && g.owner.account === group.owner.account
        })[0]
        if (twin) {
            twin.ops = twin.ops.concat(group.ops)
        } else {
            joined.push(group)
        }
    }
    s.held = joined
}

/**
 * A group comes back when it is of this connection and no known account differs, also
 * unchecked (going back to an address and token must not wait for the server), or when
 * the token was renewed for the same account on the same server (checked).
 */
function resumable(owner, group) {
    if (sameKey(group, owner)) {
        return accountsFit(group.account, owner.account)
    }
    return group.server === owner.server && !!owner.account && group.account === owner.account
}

function resume(s) {
    var owner = s.owner
    var back = []
    s.held = s.held.filter(function(group) {
        if (!resumable(owner, group.owner)) {
            return true
        }
        // An account known of the group is taken on: a check that names another one parks it again.
        if (!owner.account && group.owner.account) {
            owner.account = group.owner.account
            owner.name = group.owner.name
        }
        for (var i = 0; i < group.ops.length; i++) {
            stamp(group.ops[i], owner)
        }
        back = back.concat(group.ops)
        return false
    })
    s.ops = back.concat(s.ops)
    return back.length > 0
}

/** Both are one server and no account is known to differ. */
function compatible(a, b) {
    return a.server === b.server && accountsFit(a.account, b.account)
}

/**
 * True when `identity` is another owner than the session's: another key, or a checked account
 * that is not the one known. A replay on its way must end before that is settled.
 */
function needsMove(s, identity) {
    var owner = s.owner
    if (!owner || !identity || !identity.server || !identity.mark) {
        return false
    }
    return !sameKey(owner, identity) || !accountsFit(owner.account, identity.account)
}

/** The owner of the session becomes `identity` where that is a change (or is learned); returns what it was. */
function takeIdentity(s, prev, identity, now) {
    if (!prev) {
        // A file made before owners (2.7.0) has ops without a key: they are of the connection that
        // reads them. Without such ops the owner is set with the first check.
        var legacy = s.ops.some(function(op) { return !op.by })
        if (!identity.account && !legacy) {
            return Result.NONE
        }
        s.owner = clone(identity)
        stampUnowned(s.ops, identity)
        return Result.CLAIMED
    }
    if (!sameKey(prev, identity)) {
        stampUnowned(s.ops, prev)
        s.owner = clone(identity)
        s.snapshot = OfflineState.emptySnapshot()
        return Result.PARKED
    }
    if (!accountsFit(prev.account, identity.account)) {
        // Same address and token, another account: the database behind it was swapped.
        park(s, function(op) { return sameKey(op.by || prev, prev) }, prev, now)
        s.owner = clone(identity)
        s.snapshot = OfflineState.emptySnapshot()
        return Result.PARKED
    }
    var learned = identity.account && !prev.account
    if (identity.account) {
        prev.account = identity.account
        prev.name = identity.name || prev.name
    }
    return learned ? Result.FILLED : Result.NONE
}

/**
 * Brings the session's owner and its ops in line with `identity` ({ server, mark, account,
 * name }; account "" while not checked). Returns what happened (Result). Without a server or
 * token nothing is decided. A snapshot of another owner is dropped on the way.
 */
function settle(s, identity, now) {
    if (!identity || !identity.server || !identity.mark) {
        return Result.NONE
    }
    var prev = s.owner
    var result = takeIdentity(s, prev, identity, now)
    if (!s.owner) {
        return result
    }

    // Whatever is not of the key in use (made before, or while the file was read) waits in its group.
    if (park(s, function(op) { return !!op.by && !sameKey(op.by, s.owner) }, prev, now)) {
        result = Result.PARKED
    }
    fillGroups(s)
    if (resume(s) && result !== Result.PARKED) {
        result = Result.RESUMED
    }
    if (s.snapshot.owner && !compatible(s.snapshot.owner, s.owner)) {
        s.snapshot = OfflineState.emptySnapshot()
    }
    return result
}

// -- Held groups ----------------------------------------------------------------

function ownerName(owner) {
    return owner.name || owner.account || ""
}

/** The groups for the lists: owner, address, count. */
function groups(s) {
    return s.held.map(function(group) {
        return { id: group.id, name: ownerName(group.owner), server: group.owner.server,
                 account: group.owner.account, count: group.ops.length, heldAt: group.heldAt,
                 sameServer: !!s.owner && group.owner.server === s.owner.server, ops: clone(group.ops) }
    })
}

function heldCount(s) {
    return s.held.reduce(function(sum, group) { return sum + group.ops.length }, 0)
}

function indexOfGroup(s, id) {
    for (var i = 0; i < s.held.length; i++) {
        if (s.held[i].id === id) {
            return i
        }
    }
    return -1
}

function dropGroup(s, id) {
    var at = indexOfGroup(s, id)
    if (at < 0) {
        return false
    }
    s.held.splice(at, 1)
    return true
}
