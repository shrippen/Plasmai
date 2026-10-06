import QtQuick
import QtTest
import "../../contents/code/setupWizard.js" as Wizard

TestCase {
    name: "SetupWizard"

    function test_packageManager() {
        compare(Wizard.packageManager("ubuntu", "debian"), "apt")
        compare(Wizard.packageManager("neon", "ubuntu debian"), "apt")
        compare(Wizard.packageManager("arch", ""), "pacman")
        compare(Wizard.packageManager("manjaro", "arch"), "pacman")
        compare(Wizard.packageManager("fedora", ""), "dnf")
        compare(Wizard.packageManager("opensuse-tumbleweed", "opensuse suse"), "zypper")
        compare(Wizard.packageManager("opensuse-leap", ""), "zypper")
        compare(Wizard.packageManager("nixos", ""), "")
        compare(Wizard.packageManager("", ""), "")
    }

    function test_installCommand() {
        compare(Wizard.installCommand(Wizard.Tool.SECRET_TOOL, "debian", ""), "sudo apt install libsecret-tools")
        compare(Wizard.installCommand(Wizard.Tool.NOTIFY_SEND, "kubuntu", "ubuntu debian"), "sudo apt install libnotify-bin")
        compare(Wizard.installCommand(Wizard.Tool.SECRET_TOOL, "arch", ""), "sudo pacman -S libsecret")
        compare(Wizard.installCommand(Wizard.Tool.SECRET_TOOL, "opensuse-tumbleweed", "opensuse suse"), "sudo zypper install secret-tool")
        compare(Wizard.installCommand(Wizard.Tool.SECRET_TOOL, "gentoo", ""), "")
    }

    function test_assessNothingMissing() {
        compare(Wizard.assess({ secretTool: true, secretService: "yes", notifySend: true }).length, 0)
        // The app checks nothing: no findings, no System step.
        compare(Wizard.assess({}).length, 0)
        compare(Wizard.assess(null).length, 0)
    }

    function test_assessSecretToolMissing() {
        var issues = Wizard.assess({ secretTool: false, secretService: "no", notifySend: true, osId: "fedora" })
        // Without secret-tool the Secret Service is not reported separately.
        compare(issues.length, 1)
        compare(issues[0].id, Wizard.Issue.SECRET_TOOL)
        compare(issues[0].severity, Wizard.Severity.BLOCKING)
        compare(issues[0].command, "sudo dnf install libsecret")
        verify(Wizard.hasBlocking(issues))
    }

    function test_assessSecretService() {
        var issues = Wizard.assess({ secretTool: true, secretService: "no" })
        compare(issues.length, 1)
        compare(issues[0].id, Wizard.Issue.SECRET_SERVICE)
        // "unknown" (no dbus-send) must not block: storing the token tells.
        compare(Wizard.assess({ secretTool: true, secretService: "unknown" }).length, 0)
    }

    function test_assessNotifySendIsOptional() {
        var issues = Wizard.assess({ secretTool: true, secretService: "yes", notifySend: false, osId: "arch" })
        compare(issues.length, 1)
        compare(issues[0].severity, Wizard.Severity.OPTIONAL)
        compare(issues[0].command, "sudo pacman -S libnotify")
        verify(!Wizard.hasBlocking(issues))
        compare(Wizard.issueById(issues, Wizard.Issue.NOTIFY_SEND).id, Wizard.Issue.NOTIFY_SEND)
        compare(Wizard.issueById(issues, Wizard.Issue.SECRET_TOOL), null)
    }

    function test_steps() {
        compare(Wizard.steps([], Wizard.SystemStep.AUTO), ["look", "service", "access", "day"])
        var blocking = Wizard.assess({ secretTool: false })
        compare(Wizard.steps(blocking, Wizard.SystemStep.AUTO), ["system", "look", "service", "access", "day"])
        // Fixed after it was shown: the step stays, indices do not shift.
        compare(Wizard.steps([], Wizard.SystemStep.KEEP), ["system", "look", "service", "access", "day"])
    }

    function test_lookPatch() {
        compare(Wizard.lookPatch(0), { visualStyle: 0 })
        compare(Wizard.lookPatch(1), { visualStyle: 1 })
        compare(Wizard.lookPatch("2"), { visualStyle: 2 })
        compare(Wizard.lookPatch(3), {})
        compare(Wizard.lookPatch(-1), {})
        compare(Wizard.lookPatch("x"), {})
    }

    function test_cleanToken() {
        compare(Wizard.cleanToken("  abc123\n"), "abc123")
        compare(Wizard.cleanToken("Bearer abc123"), "abc123")
        compare(Wizard.cleanToken("bearer   abc\n123 "), "abc123")
        compare(Wizard.cleanToken(""), "")
        compare(Wizard.cleanToken(null), "")
    }

    function test_checkUrlMissingAndInvalid() {
        compare(Wizard.checkUrl("kimai", "").problem, Wizard.UrlProblem.MISSING)
        compare(Wizard.checkUrl("kimai", "   ").problem, Wizard.UrlProblem.MISSING)
        compare(Wizard.checkUrl("kimai", "ftp://kimai.example.com").problem, Wizard.UrlProblem.INVALID)
        compare(Wizard.checkUrl("kimai", "https://").problem, Wizard.UrlProblem.INVALID)
    }

    function test_checkUrlSchemeAndCase() {
        var r = Wizard.checkUrl("kimai", "kimai.example.com")
        compare(r.url, "https://kimai.example.com")
        verify(Wizard.hasNote(r, Wizard.UrlNote.SCHEME_ADDED))
        compare(Wizard.checkUrl("kimai", "HTTPS://kimai.example.com/").url, "https://kimai.example.com")
        compare(Wizard.checkUrl("kimai", "https://kimai.example.com:8443").url, "https://kimai.example.com:8443")
    }

    function test_checkUrlKimaiPages() {
        var page = Wizard.checkUrl("kimai", "https://kimai.example.com/de/timesheet/")
        compare(page.url, "https://kimai.example.com")
        verify(Wizard.hasNote(page, Wizard.UrlNote.TRIMMED))
        compare(Wizard.checkUrl("kimai", "https://kimai.example.com/api/doc").url, "https://kimai.example.com")
        compare(Wizard.checkUrl("kimai", "https://kimai.example.com/api").url, "https://kimai.example.com")
        compare(Wizard.checkUrl("kimai", "https://example.com/kimai/en_GB/dashboard/").url, "https://example.com/kimai")
        // An instance in a sub folder stays.
        var sub = Wizard.checkUrl("kimai", "https://example.com/kimai")
        compare(sub.url, "https://example.com/kimai")
        verify(!Wizard.hasNote(sub, Wizard.UrlNote.TRIMMED))
    }

    function test_checkUrlOtherServicesKeepPaths() {
        compare(Wizard.checkUrl("toggl", "https://api.track.toggl.com/api/v9").url, "https://api.track.toggl.com/api/v9")
        compare(Wizard.checkUrl("clockify", "https://euc1.clockify.me/api/v1/").url, "https://euc1.clockify.me/api/v1")
    }

    function test_checkUrlInsecure() {
        verify(Wizard.hasNote(Wizard.checkUrl("kimai", "http://kimai.example.com"), Wizard.UrlNote.INSECURE))
        verify(!Wizard.hasNote(Wizard.checkUrl("kimai", "http://localhost:8001"), Wizard.UrlNote.INSECURE))
        verify(!Wizard.hasNote(Wizard.checkUrl("kimai", "http://127.0.0.1"), Wizard.UrlNote.INSECURE))
        verify(!Wizard.hasNote(Wizard.checkUrl("kimai", "http://kimai.local"), Wizard.UrlNote.INSECURE))
        verify(!Wizard.hasNote(Wizard.checkUrl("kimai", "https://kimai.example.com"), Wizard.UrlNote.INSECURE))
    }

    function test_applyServiceDefaultProfile() {
        var r = Wizard.applyService([{ id: "default", name: "Default", url: "", provider: "kimai" }],
                                    "default", "toggl", "Toggl Track", "https://api.track.toggl.com/api/v9")
        compare(r.profileId, "default")
        compare(r.profiles.length, 1)
        compare(r.profiles[0].provider, "toggl")
        compare(r.profiles[0].name, "Toggl Track")
        compare(r.profiles[0].url, "https://api.track.toggl.com/api/v9")
    }

    function test_applyServiceKeepsOthersAndNames() {
        var list = [
            { id: "a", name: "Work", url: "https://a", provider: "kimai" },
            { id: "b", name: "Home", url: "", provider: "kimai" }
        ]
        var r = Wizard.applyService(list, "b", "kimai", "Kimai", "https://b")
        compare(r.profileId, "b")
        compare(r.profiles[0].url, "https://a")
        compare(r.profiles[1].name, "Home")
        compare(r.profiles[1].url, "https://b")
        // The input list is not changed.
        compare(list[1].url, "")
        // Unknown active id: the first profile.
        compare(Wizard.applyService(list, "zzz", "kimai", "Kimai", "https://c").profileId, "a")
        compare(Wizard.applyService([], "default", "kimai", "Kimai", "https://c").profiles[0].id, "default")
    }

    function test_withConnectionMeta() {
        var p = Wizard.withConnectionMeta({ id: "x", workspaceId: "" }, { workspaceId: 7, userId: 3, version: "Toggl Track" })
        compare(p.workspaceId, 7)
        compare(p.userId, 3)
        verify(p.version === undefined)
        compare(Wizard.withConnectionMeta({ id: "x" }, null).id, "x")
    }

    function test_userLabel() {
        compare(Wizard.userLabel({ alias: "Anna B.", username: "anna" }), "Anna B.")
        compare(Wizard.userLabel({ username: "anna" }), "anna")
        compare(Wizard.userLabel({ email: "a@example.com" }), "a@example.com")
        compare(Wizard.userLabel(null), "")
    }

    function test_clockAndHours() {
        compare(Wizard.clockMinutes("08:30"), 510)
        compare(Wizard.clockMinutes("8:05"), 485)
        compare(Wizard.clockMinutes("24:00"), -1)
        compare(Wizard.clockMinutes("x"), -1)
        verify(Wizard.validHours("08:00", "17:00"))
        verify(!Wizard.validHours("17:00", "08:00"))
        verify(!Wizard.validHours("08:00", "08:00"))
    }

    function test_dayPatch() {
        var p = Wizard.dayPatch({ begin: "07:30", end: "16:00",
                                  place: { displayName: "Hamburg, Deutschland", latitude: 53.55, longitude: 9.99 },
                                  remind: true })
        compare(p.workDayBegin, "07:30")
        compare(p.workDayEnd, "16:00")
        compare(p.latitude, 53.55)
        compare(p.longitude, 9.99)
        compare(p.locationName, "Hamburg, Deutschland")
        compare(p.notifyForgotToStart, true)
    }

    function test_dayPatchKeepsWhatWasNotSet() {
        var p = Wizard.dayPatch({ begin: "18:00", end: "08:00", place: null })
        verify(p.workDayBegin === undefined)
        verify(p.latitude === undefined)
        verify(p.notifyForgotToStart === undefined)
        compare(Object.keys(Wizard.dayPatch(null)).length, 0)
    }

    function test_shortPlace() {
        compare(Wizard.shortPlace("Hamburg, Deutschland"), "Hamburg")
        compare(Wizard.shortPlace(""), "")
    }
}
