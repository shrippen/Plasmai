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
}
