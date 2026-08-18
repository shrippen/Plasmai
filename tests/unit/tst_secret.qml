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

    function test_parsePreparingShutdown() {
        verify(Secret.parsePreparingShutdown("1\n"))
        verify(!Secret.parsePreparingShutdown("true"))
        verify(!Secret.parsePreparingShutdown("0"))
        verify(!Secret.parsePreparingShutdown("false"))
        verify(!Secret.parsePreparingShutdown(""))
    }
}
