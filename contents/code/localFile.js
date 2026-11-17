.pragma library

/** How reading one of the client's own files (platform.js loadLocal) ended. */
var Status = {
    /** There is no such file: the first start. */
    MISSING: "missing",
    OK: "ok",
    /** The file is there and could not be read: its content is unknown, never overwrite it. */
    UNREADABLE: "unreadable",
    /** The file is there and is no JSON. The platform moved it aside (`<name>.broken-<time>`). */
    BROKEN: "broken"
}
