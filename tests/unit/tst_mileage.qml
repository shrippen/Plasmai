import QtQuick
import QtTest
import "../../contents/code/mileage.js" as Mileage
import "../../contents/code/statsData.js" as StatsData

TestCase {
    name: "Mileage"

    function ping(o) {
        var p = { apiVersions: ["v1"],
                  permissions: { view: true, editOwn: true, deleteOwn: true, editLocked: false },
                  features: ["tripTimesheet", "dateRange", "acceptFields", "commuteCheck"],
                  profile: { commuteKm: 12.5, defaultVehicle: "company_car", defaultVehicleId: 6 },
                  lockedMonths: ["2026-08"] }
        for (var k in (o || {})) p[k] = o[k]
        return p
    }

    function trip(o) {
        var t = { id: 7, user: 2, date: "2026-09-22", departure: "2026-09-22T07:15:00+02:00",
                  arrival: "2026-09-22T08:00:00+02:00", purpose: "business", vehicle: "own_car", vehicleId: null,
                  start: "Home", destination: "Set", distanceKm: 12.5, roundTrip: true, totalKm: 25,
                  project: 1, timesheet: 99, comment: null, source: "manual" }
        for (var k in (o || {})) t[k] = o[k]
        return t
    }

    function test_ranges() {
        var r = Mileage.monthRange(new Date(2026, 1, 10))
        compare(r.from, "2026-02-01")
        compare(r.to, "2026-02-28")
        var w = Mileage.weekRange(new Date(2026, 8, 27))   // Sunday
        compare(w.from, "2026-09-21")
        compare(w.to, "2026-09-27")
        var span = StatsData.tripRangeFor(new Date(2026, 9, 1))  // Thu 1 Oct: week starts in September
        compare(span.from, "2026-09-28")
        compare(span.to, "2026-10-31")
    }

    function test_pingHelpers() {
        verify(Mileage.hasFeature(ping(), "tripTimesheet"))
        verify(!Mileage.hasFeature(ping({ features: [] }), "tripTimesheet"))
        verify(Mileage.can(ping(), "editOwn"))
        verify(!Mileage.can(ping(), "editLocked"))
        compare(Mileage.commuteKm(ping()), 12.5)
        compare(Mileage.commuteKm(ping({ profile: { commuteKm: 0 } })), null)
        verify(Mileage.isMonthLocked(ping(), "2026-08-14"))
        verify(!Mileage.isMonthLocked(ping(), "2026-09-14"))
        verify(!Mileage.isMonthLocked(ping({ permissions: { view: true, editLocked: true } }), "2026-08-14"))
    }

    function test_emptyFormUsesProfile() {
        var f = Mileage.emptyForm(ping(), "2026-09-22")
        compare(f.date, "2026-09-22")
        compare(f.purpose, "business")
        compare(f.vehicle, "company_car")
        compare(f.vehicleId, 6)
        compare(Mileage.emptyForm(null, "bad").vehicle, "own_car")
    }

    function test_formFromTripAndBack() {
        var f = Mileage.formFromTrip(trip())
        compare(f.id, 7)
        compare(f.distanceKm, "12.5")
        verify(f.withTimes)
        compare(f.departure, "07:15")   // as the plugin wrote it (user timezone)
        compare(f.arrival, "08:00")
        compare(f.timesheet, 99)
        // unchanged form → empty PATCH
        verify(Mileage.isEmptyBody(Mileage.toApiBody(f, trip(), ping())))
        f.distanceKm = "13,5"
        f.comment = "  Umweg "
        var patch = Mileage.toApiBody(f, trip(), ping())
        compare(Object.keys(patch).sort().join(","), "comment,distanceKm")
        compare(patch.distanceKm, 13.5)
        compare(patch.comment, "Umweg")
        f.withTimes = false
        patch = Mileage.toApiBody(f, trip(), ping())
        compare(patch.departure, null)
        compare(patch.arrival, null)
    }

    function test_createBodySkipsEmptyAndTimesheetWithoutFeature() {
        var f = Mileage.formForTimesheet(ping(), { id: 5, begin: "2026-09-22T23:30:00+0200" }, function(ts) { return 3 })
        compare(f.date, "2026-09-22")
        compare(f.timesheet, 5)
        compare(f.project, 3)
        f.distanceKm = "40"
        var body = Mileage.toApiBody(f, null, ping())
        compare(body.distanceKm, 40)
        compare(body.timesheet, 5)
        compare(body.project, 3)
        compare(body.vehicleId, 6)
        verify(!body.hasOwnProperty("start"))
        verify(!body.hasOwnProperty("departure"))
        var old = Mileage.toApiBody(f, null, ping({ features: [] }))
        verify(!old.hasOwnProperty("timesheet"))
    }

    function test_validate() {
        var f = Mileage.emptyForm(ping(), "2026-09-22")
        compare(Mileage.validateForm(f, ping()).distanceKm, "required")
        f.purpose = "commute"
        verify(!Mileage.hasErrors(Mileage.validateForm(f, ping())))         // profile commute distance
        compare(Mileage.validateForm(f, ping({ profile: {} })).distanceKm, "required")
        f.distanceKm = "abc"
        compare(Mileage.validateForm(f, ping()).distanceKm, "invalid")
        f.distanceKm = "20000"
        compare(Mileage.validateForm(f, ping()).distanceKm, "invalid")
        f.distanceKm = "7,4"
        f.date = "2026-08-03"
        compare(Mileage.validateForm(f, ping()).date, "locked")
        f.date = "2026-09-31"
        compare(Mileage.validateForm(f, ping()).date, "invalid")
        f.date = "2026-09-22"
        f.withTimes = true
        f.departure = "9:00"
        f.arrival = "08:30"
        compare(Mileage.validateForm(f, ping()).arrival, "beforeDeparture")
        f.arrival = "25:00"
        compare(Mileage.validateForm(f, ping()).arrival, "invalid")
        f.arrival = "10:00"
        verify(!Mileage.hasErrors(Mileage.validateForm(f, ping())))
        compare(Mileage.toApi(f, ping()).departure, "09:00")
    }

    function test_parseDistance() {
        compare(Mileage.parseDistance("12,5"), 12.5)
        compare(Mileage.parseDistance(" 12.5 km"), 12.5)
        compare(Mileage.parseDistance(3), 3)
        compare(Mileage.parseDistance(""), null)
        compare(Mileage.parseDistance("1.2.3"), null)
        compare(Mileage.parseDistance("-4"), null)
    }

    function test_acceptAndCommuteBodies() {
        compare(JSON.stringify(Mileage.commuteBody("2026-09-22")), '{"purpose":"commute","date":"2026-09-22"}')
        var b = Mileage.acceptBody(ping(), { purpose: "business", project: 3, distanceKm: "8,2", timesheet: 5, comment: "" })
        compare(b.purpose, "business")
        compare(b.project, 3)
        compare(b.distanceKm, 8.2)
        compare(b.timesheet, 5)
        verify(!b.hasOwnProperty("comment"))
        var old = Mileage.acceptBody(ping({ features: [] }), { purpose: "business", project: 3 })
        verify(!old.hasOwnProperty("project"))
    }

    function test_summarizeAndSort() {
        var trips = [trip(), trip({ id: 8, date: "2026-09-23", purpose: "commute", totalKm: undefined, distanceKm: 10, roundTrip: false }),
                     trip({ id: 9, date: "2026-10-01", totalKm: 5 }), { id: 10 }]
        var s = Mileage.summarize(trips, "2026-09-01", "2026-09-30")
        compare(s.count, 2)
        compare(s.km, 35)
        compare(s.byPurpose.business, 25)
        compare(s.byPurpose.commute, 10)
        var sorted = Mileage.sortTrips(trips.slice(0, 3))
        compare(sorted[0].id, 9)
        compare(sorted[2].id, 7)
        compare(Mileage.tripsForTimesheet(trips, 99).length, 3)
        var k = StatsData.tripKmSummary(trips, new Date(2026, 8, 23))
        compare(k.todayKm, 10)
        compare(k.weekKm, 35)
        compare(k.monthKm, 35)
        compare(k.monthCount, 2)
    }

    function test_labelsAndOptions() {
        var meta = [{ value: "business", label: "Dienstreise" }]
        compare(Mileage.labelOf(meta, "business", {}), "Dienstreise")
        compare(Mileage.labelOf(meta, "private", { "private": "Privat" }), "Privat")
        compare(Mileage.options(null, Mileage.PURPOSES, { business: "B" })[1].label, "B")
        compare(Mileage.options(null, Mileage.PURPOSES, {})[0].value, "commute")
        compare(Mileage.options(meta, Mileage.PURPOSES, {})[0].label, "Dienstreise")
        // The plugin's /meta labels are English; a translated fallback wins.
        var englishMeta = [{ value: "business", label: "Business trip" }, { value: "custom", label: "Custom" }]
        compare(Mileage.labelOf(englishMeta, "business", { business: "Dienstreise" }), "Dienstreise")
        compare(Mileage.options(englishMeta, Mileage.PURPOSES, { business: "Dienstreise" })[0].label, "Dienstreise")
        compare(Mileage.options(englishMeta, Mileage.PURPOSES, { business: "Dienstreise" })[1].label, "Custom")
        compare(Mileage.routeText("A", "B"), "A → B")
        compare(Mileage.routeText("", "B"), "B")
    }
}
