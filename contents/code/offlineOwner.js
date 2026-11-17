.pragma library
.import "./providerUtil.js" as ProviderUtil

/** Skeleton: the tests of the owner of waiting changes run against it first. */
var Result = { NONE: "none", CLAIMED: "claimed", FILLED: "filled", PARKED: "parked" }

function serverOf(url) {
    return ProviderUtil.normalizeUrl(url)
}

function settle(s, identity) {
    return Result.NONE
}
