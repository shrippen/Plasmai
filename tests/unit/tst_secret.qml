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
        Secret.saveSharedConfig(ds, "/p/sharedConfig.sh", { filmDaysJson: big }, function(ok) { saved = ok })
        var n = answerAll(ds)
        verify(n > 2)
        for (i = 0; i < n - 1; i++) {
            verify(ds.sources[i].indexOf("' 'append' '") > 0)
            verify(ds.sources[i].length < 128 * 1024)
        }
        verify(ds.sources[n - 1].indexOf("exec sh '/p/sharedConfig.sh' commit '") === 0)
        compare(saved, true)
    }
}
