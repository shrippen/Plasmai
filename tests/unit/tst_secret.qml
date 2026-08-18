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
    }
}
