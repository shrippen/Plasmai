WorkerScript.onMessage = function(msg) {
    var parsed = null
    try {
        var s = String(msg.text || "")
        var start = s.indexOf("{")
        var end = s.lastIndexOf("}")
        if (start >= 0 && end > start) {
            parsed = JSON.parse(s.substring(start, end + 1))
        }
    } catch (e) {
        parsed = null
    }
    WorkerScript.sendMessage({ payload: parsed })
}
