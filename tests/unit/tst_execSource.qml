import QtQuick
import QtTest
import "../../contents/ui"
import "../../contents/code/secret.js" as Secret

TestCase {
    name: "ExecSource"

    ExecSource {
        id: exec
    }

    // Every command gets its own DataSource, gone once it answered.
    function test_runsAndForgetsEachCommand() {
        var out = []
        Secret._run(exec, "echo one", function(data) { out.push(String(data.stdout).trim()) })
        Secret._run(exec, "echo two", function(data) { out.push(String(data.stdout).trim()) })
        compare(Object.keys(exec.jobs).length, 2)
        tryCompare(out, "length", 2, 5000)
        verify(out.indexOf("one") >= 0 && out.indexOf("two") >= 0)
        compare(Object.keys(exec.jobs).length, 0)
    }

    // secret.js makes every source unique; a repeated one still runs once and leaves nothing.
    function test_sameSourceRunsOnce() {
        exec.connectSource("echo same")
        var first = exec.jobs["echo same"]
        exec.connectSource("echo same")
        verify(exec.jobs["echo same"] === first, "the running DataSource is kept, not replaced")
        exec.disconnectSource("echo same")
        compare(Object.keys(exec.jobs).length, 0)
    }

    function test_cancelDropsPendingJobs() {
        var called = false
        Secret._run(exec, "sleep 2", function() { called = true })
        compare(Object.keys(exec.jobs).length, 1)
        Secret.cancelAll(exec)
        compare(Object.keys(exec.jobs).length, 0)
        wait(100)
        verify(!called)
    }
}
