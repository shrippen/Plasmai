import QtQuick
import QtTest
import "../../contents/code/secret.js" as Secret

TestCase {
    name: "Secret"

    function test_shQuote() {
        compare(Secret.shQuote("abc"), "'abc'")
        compare(Secret.shQuote("a'b"), "'a'\\''b'")
    }

    function test_fileUrlToPath() {
        compare(Secret.fileUrlToPath("file:///home/x/kwallet.sh"), "/home/x/kwallet.sh")
        compare(Secret.fileUrlToPath("/already/path"), "/already/path")
        compare(Secret.fileUrlToPath("file:///home/x/My%20Widgets/kwallet.sh"), "/home/x/My Widgets/kwallet.sh")
    }

    function test_storeCommandExecsWithEnv() {
        compare(Secret.storeCommand("KIMAI_TOKEN", "a'b", "/p/kwallet.sh", ["store", "default"]),
                "KIMAI_TOKEN='a'\\''b' exec sh '/p/kwallet.sh' 'store' 'default'")
    }

    function test_catalogChunksStayBelowArgLimit() {
        var json = ""
        for (var i = 0; i < 70000; i++) {
            json += (i % 7 === 0) ? "'" : "x"
        }
        var chunks = Secret.catalogChunks(json)
        compare(chunks.length, 3)
        compare(chunks.join(""), json)
        for (i = 0; i < chunks.length; i++) {
            verify(Secret.shQuote(chunks[i]).length * 3 < 128 * 1024)
        }
        // A surrogate pair is never split.
        var emoji = "a\uD83D\uDE00b"
        var parts = Secret.catalogChunks(JSON.parse('"' + emoji + '"'), 2)
        compare(parts[0], "a")
        compare(parts.join(""), JSON.parse('"' + emoji + '"'))
    }

    // Records commands instead of running them; answer() completes the oldest.
    function fakeSource() {
        return {
            sources: [],
            connectSource: function(name) { this.sources.push(name) },
            disconnectSource: function(name) {}
        }
    }

    function answerAll(ds) {
        var done = 0
        while (done < ds.sources.length) {
            Secret.handleData(ds, ds.sources[done], { "exit code": 0, stdout: "", stderr: "" })
            done++
        }
        return done
    }

    function test_sharedConfigSmallStoresOnce() {
        var ds = fakeSource()
        var saved = null
        Secret.saveSharedConfig(ds, "/p/sharedConfig.sh", { a: 1 }, function(ok) { saved = ok })
        compare(answerAll(ds), 1)
        verify(ds.sources[0].indexOf("KIMAI_SHARED_JSON='{\"a\":1}' exec sh '/p/sharedConfig.sh' 'store'") === 0)
        compare(saved, true)
    }

    function test_sharedConfigLargeIsChunked() {
        // shared.json can grow past one argv (128 KiB).
        var big = ""
        for (var i = 0; i < 200000; i++) {
            big += "x"
        }
        var ds = fakeSource()
        var saved = null
        Secret.saveSharedConfig(ds, "/p/sharedConfig.sh", { pluginProbesJson: big }, function(ok) { saved = ok })
        var n = answerAll(ds)
        verify(n > 2)
        for (i = 0; i < n - 1; i++) {
            verify(ds.sources[i].indexOf("' 'append' '") > 0)
            verify(ds.sources[i].length < 128 * 1024)
        }
        verify(ds.sources[n - 1].indexOf("exec sh '/p/sharedConfig.sh' commit '") === 0)
        compare(saved, true)
    }

    // The Plasmoid's own files: the name follows every subcommand.
    function test_localStoreNamesTheFile() {
        var ds = fakeSource()
        var saved = null
        Secret.saveLocal(ds, "/p/localStore.sh", "offline-outbox-p1", { ops: [] }, function(ok) { saved = ok })
        compare(answerAll(ds), 1)
        verify(ds.sources[0].indexOf("PLASMAI_LOCAL_JSON='{\"ops\":[]}' exec sh '/p/localStore.sh' 'store' 'offline-outbox-p1'") === 0)
        compare(saved, true)

        var big = ""
        for (var i = 0; i < 70000; i++) {
            big += "x"
        }
        ds = fakeSource()
        Secret.saveLocal(ds, "/p/localStore.sh", "offline-state-p1", { big: big }, function(ok) { saved = ok })
        var n = answerAll(ds)
        verify(n > 2)
        verify(ds.sources[0].indexOf("' 'append' 'offline-state-p1' '") > 0)
        verify(ds.sources[n - 1].indexOf("exec sh '/p/localStore.sh' commit 'offline-state-p1' '") === 0)
    }

    function test_systemCheckResult() {
        var r = Secret.systemCheckResult("secretTool=yes\nsecretService=no\nnotifySend=no\nosId=ubuntu\nosLike=debian\n")
        compare(r.secretTool, true)
        compare(r.secretService, "no")
        compare(r.notifySend, false)
        compare(r.osId, "ubuntu")
        compare(r.osLike, "debian")
        // A failed or missing script checks nothing.
        compare(Object.keys(Secret.systemCheckResult("")).length, 0)
        compare(Secret.systemCheckResult("secretTool=no\nosId=\n").osId, "")
    }

    function test_runSystemCheck() {
        var ds = fakeSource()
        var got = null
        Secret.runSystemCheck(ds, "/p/systemCheck.sh", function(result) { got = result })
        verify(ds.sources[0].indexOf("sh '/p/systemCheck.sh'") === 0)
        Secret.handleData(ds, ds.sources[0], { "exit code": 0, stdout: "secretTool=no\nsecretService=unknown\n", stderr: "" })
        compare(got.secretTool, false)
        compare(got.secretService, "unknown")
    }

    function test_loadLocal() {
        var ds = fakeSource()
        var got = "unset"
        Secret.loadLocal(ds, "/p/localStore.sh", "offline-state-p1", function(obj, err) { got = obj })
        verify(ds.sources[0].indexOf("sh '/p/localStore.sh' load 'offline-state-p1'") === 0)
        Secret.handleData(ds, ds.sources[0], { "exit code": 0, stdout: '{"v":1}\n', stderr: "" })
        compare(got.v, 1)
        Secret.loadLocal(ds, "/p/localStore.sh", "none", function(obj, err) { got = [obj, err] })
        Secret.handleData(ds, ds.sources[1], { "exit code": 1, stdout: "", stderr: "" })
        compare(got, [null, null])
    }
}
