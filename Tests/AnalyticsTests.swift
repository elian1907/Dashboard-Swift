import XCTest

@testable import LosloDashboard

final class AnalyticsTests: XCTestCase {
  func testUTCPeriodsAndLaunchClamp() {
    let r = PeriodRange(.month, launch: "2026-06-14", today: "2026-06-20")
    XCTAssertEqual(r.start, "2026-06-14")
    XCTAssertEqual(r.end, "2026-06-19")
    XCTAssertEqual(r.labels.count, 6)
    XCTAssertEqual(r.previous, Day.range("2026-06-08", "2026-06-13"))
    XCTAssertEqual(Day.shift("2026-03-01", -1), "2026-02-28")
    XCTAssertEqual(Day.shift("2024-03-01", -1), "2024-02-29")
  }
  func testMissingDaysStayMissingAndZeroStaysZero() {
    let dates = ["2026-06-14", "2026-06-15", "2026-06-16"]
    let p = Analytics.align(
      [DataPoint(date: dates[0], value: 5), DataPoint(date: dates[2], value: 0)], dates: dates)
    XCTAssertEqual(p.map(\.value), [5, nil, 0])
    XCTAssertNil(Analytics.total(p))
    XCTAssertEqual(Analytics.total(p, complete: false), 5)
    XCTAssertEqual(Analytics.cumulative(p).map(\.value), [5, nil, nil])
    XCTAssertEqual(
      Analytics.align([], dates: dates, coverage: dates[0]...dates[1]).map(\.value), [0, 0, nil])
  }
  func testIncompleteRevenueExcluded() {
    let p = Analytics.align(
      [DataPoint(date: "2026-06-14", value: 12, incomplete: true)], dates: ["2026-06-14"])
    XCTAssertNil(p[0].value)
    XCTAssertNil(Analytics.total(p))
    XCTAssertNil(Analytics.change(12, 0))
  }
  func testAppReportSeparatesApplicationsAndExcludesUpdates() throws {
    let tsv =
      "Apple Identifier\tUnits\tProduct Type Identifier\tCountry Code\tTitle\n111\t8\t1\tFR\tLoslo\n111\t2\t1F\tUS\tLoslo\n111\t100\t7\tFR\tLoslo\n222\t999\t1\tFR\tOther\n"
    let result = try AppleService.parse(tsv)
    XCTAssertEqual(result["111"]?.units, 10)
    XCTAssertEqual(result["111"]?.countries["FR"], 8)
    XCTAssertEqual(result["222"]?.units, 999)
    XCTAssertEqual(try AppleService.resolve(result, configured: nil, name: "Loslo"), "111")
    XCTAssertThrowsError(try AppleService.resolve(result, configured: nil, name: "Unknown"))
    XCTAssertThrowsError(try AppleService.parse("Units\tTitle\n10\tLoslo"))
  }
  func testCountryAggregationAndMissingDays() {
    let a = SalesArchive(
      selectedAppId: "111",
      reports: [
        "2026-06-14": SalesReport(
          checkedAt: 0,
          apps: [
            "111": AppDay(title: "Loslo", units: 5, countries: ["FR": 5]),
            "222": AppDay(title: "Other", units: 500, countries: ["FR": 500]),
          ]), "2026-06-15": SalesReport(checkedAt: 0, apps: nil),
      ])
    let r = a.countries(["2026-06-14", "2026-06-15"], appID: "111")
    XCTAssertEqual(r.rows.first?.units, 5)
    XCTAssertEqual(r.missing, 1)
  }
  func testRPMUsesFinishedTrialsAndOfferPrices() {
    let offer = JSONValue.object([
      "Conversions": .number(3), "Expirations": .number(1), "Pending": .number(2),
    ])
    let total = JSONValue.object(["loslo_special_offer": offer, "unknown": offer])
    XCTAssertEqual(Offer.conversion(offer), 0.75)
    XCTAssertEqual(Offer.expected(total), 2 * 0.75 * 19.99, accuracy: 0.00001)
    XCTAssertNil(Offer.conversion(.object(["Pending": .number(9)])))
  }
  func testMigrationReadsQuotedConfigurationWithoutExecution() {
    let env = DashboardImporter.environment(
      "# ignore\nVALUE=\"a=b\"\nKEY='first\\nsecond'\nexport NAME=Loslo\n")
    XCTAssertEqual(env["VALUE"], "a=b")
    XCTAssertEqual(env["KEY"], "first\nsecond")
    XCTAssertEqual(env["NAME"], "Loslo")
  }
  func testHTTPSRequired() throws {
    XCTAssertThrowsError(try HTTP.url("http://example.com"))
    XCTAssertEqual(try HTTP.url("https://example.com", [("query", "a&b")]).query, "query=a%26b")
  }
  func testGzipRejectsInvalidOrTruncatedReports() {
    XCTAssertThrowsError(try Gzip.decode(Data()))
    XCTAssertThrowsError(try Gzip.decode(Data([31, 139, 8, 0, 0, 0])))
  }
}
