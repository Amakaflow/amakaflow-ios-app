//
//  MonthGridLayoutTests.swift
//  AmakaFlowCompanionTests
//
//  AMA-1641: Tests for the pure month-grid layout helpers extracted
//  from WorkoutsView so day-1 of any month lands under the correct
//  weekday column.
//

import XCTest
@testable import AmakaFlowCompanion

final class MonthGridLayoutTests: XCTestCase {

    private var gregorianUSCalendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.firstWeekday = 1                       // Sunday-first (US default)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        cal.locale = Locale(identifier: "en_US")
        return cal
    }

    private var gregorianMondayFirstCalendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.firstWeekday = 2                       // Monday-first (most of EU)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        cal.locale = Locale(identifier: "en_GB")
        return cal
    }

    // MARK: - leadingEmptyCells

    func test_leadingEmptyCells_AprilFirstWednesday_3LeadingCellsSundayFirst() {
        // April 2026 — April 1 is a Wednesday. With Sunday-first layout we
        // need 3 leading empty cells (Sun, Mon, Tue) before day 1.
        let cal = gregorianUSCalendar
        let april1 = cal.date(from: DateComponents(year: 2026, month: 4, day: 1))!
        XCTAssertEqual(MonthGridLayout.leadingEmptyCells(for: april1, calendar: cal), 3)
    }

    func test_leadingEmptyCells_AnyDayInMonth_anchorsToFirst() {
        let cal = gregorianUSCalendar
        let april15 = cal.date(from: DateComponents(year: 2026, month: 4, day: 15))!
        XCTAssertEqual(MonthGridLayout.leadingEmptyCells(for: april15, calendar: cal), 3,
                       "Function must re-anchor to day-1 of the month")
    }

    func test_leadingEmptyCells_AprilSundayFirstMonth_zero() {
        // March 2026 — March 1 is a Sunday. Zero leading cells expected.
        let cal = gregorianUSCalendar
        let march1 = cal.date(from: DateComponents(year: 2026, month: 3, day: 1))!
        XCTAssertEqual(MonthGridLayout.leadingEmptyCells(for: march1, calendar: cal), 0)
    }

    func test_leadingEmptyCells_MondayFirstLocale_AprilFirst_2LeadingCells() {
        // April 2026 in a Monday-first locale. April 1 = Wednesday. Leading
        // empty cells should be (Wed - Mon) = 2 (Mon and Tue).
        let cal = gregorianMondayFirstCalendar
        let april1 = cal.date(from: DateComponents(year: 2026, month: 4, day: 1))!
        XCTAssertEqual(MonthGridLayout.leadingEmptyCells(for: april1, calendar: cal), 2)
    }

    func test_leadingEmptyCells_isAlwaysIn0to6() {
        let cal = gregorianUSCalendar
        // Spot-check every month in 2026.
        for month in 1...12 {
            let date = cal.date(from: DateComponents(year: 2026, month: month, day: 1))!
            let leading = MonthGridLayout.leadingEmptyCells(for: date, calendar: cal)
            XCTAssertGreaterThanOrEqual(leading, 0)
            XCTAssertLessThanOrEqual(leading, 6, "Month \(month): leading=\(leading)")
        }
    }

    // MARK: - weekdaySymbols

    func test_weekdaySymbols_sundayFirst_startsWithSundayInitial() {
        let cal = gregorianUSCalendar
        let symbols = MonthGridLayout.weekdaySymbols(calendar: cal)
        XCTAssertEqual(symbols.count, 7)
        XCTAssertEqual(symbols.first, cal.veryShortStandaloneWeekdaySymbols.first,
                       "First entry must equal the calendar's first weekday symbol (Sun for US)")
    }

    func test_weekdaySymbols_mondayFirst_isRotated() {
        let usCal = gregorianUSCalendar
        let euCal = gregorianMondayFirstCalendar
        let usSymbols = MonthGridLayout.weekdaySymbols(calendar: usCal)
        let euSymbols = MonthGridLayout.weekdaySymbols(calendar: euCal)
        XCTAssertEqual(euSymbols.count, 7)
        // Monday-first should be the US sequence rotated by one.
        XCTAssertEqual(euSymbols.first, usSymbols[1], "Monday-first should start with what was index-1 in Sunday-first")
        // Same set of symbols, just rotated.
        XCTAssertEqual(Set(euSymbols), Set(usSymbols))
    }

    // MARK: - monthAnchor

    func test_monthAnchor_zeroOffset_isStartOfCurrentMonth() {
        let cal = gregorianUSCalendar
        let now = cal.date(from: DateComponents(year: 2026, month: 4, day: 17))!
        let anchor = MonthGridLayout.monthAnchor(from: now, offset: 0, calendar: cal)
        let parts = cal.dateComponents([.year, .month, .day], from: anchor)
        XCTAssertEqual(parts.year, 2026)
        XCTAssertEqual(parts.month, 4)
        XCTAssertEqual(parts.day, 1)
    }

    func test_monthAnchor_positiveOffset_advancesMonth() {
        let cal = gregorianUSCalendar
        let now = cal.date(from: DateComponents(year: 2026, month: 4, day: 17))!
        let anchor = MonthGridLayout.monthAnchor(from: now, offset: 2, calendar: cal)
        let parts = cal.dateComponents([.year, .month, .day], from: anchor)
        XCTAssertEqual(parts.month, 6)
        XCTAssertEqual(parts.day, 1)
    }

    func test_monthAnchor_negativeOffset_goesBack() {
        let cal = gregorianUSCalendar
        let now = cal.date(from: DateComponents(year: 2026, month: 1, day: 17))!
        let anchor = MonthGridLayout.monthAnchor(from: now, offset: -1, calendar: cal)
        let parts = cal.dateComponents([.year, .month, .day], from: anchor)
        XCTAssertEqual(parts.year, 2025)
        XCTAssertEqual(parts.month, 12)
        XCTAssertEqual(parts.day, 1)
    }

    // MARK: - dates(inMonthContaining:)

    func test_datesInMonthContaining_AprilHas30Days() {
        let cal = gregorianUSCalendar
        let april15 = cal.date(from: DateComponents(year: 2026, month: 4, day: 15))!
        let dates = MonthGridLayout.dates(inMonthContaining: april15, calendar: cal)
        XCTAssertEqual(dates.count, 30)
        XCTAssertEqual(cal.component(.day, from: dates.first!), 1)
        XCTAssertEqual(cal.component(.day, from: dates.last!), 30)
    }

    func test_datesInMonthContaining_FebLeapYear_29Days() {
        let cal = gregorianUSCalendar
        let feb15 = cal.date(from: DateComponents(year: 2024, month: 2, day: 15))!
        let dates = MonthGridLayout.dates(inMonthContaining: feb15, calendar: cal)
        XCTAssertEqual(dates.count, 29)
    }

    // MARK: - Calendar.startOfMonth

    func test_calendarStartOfMonth_anyDay_returnsFirst() {
        let cal = gregorianUSCalendar
        let april17 = cal.date(from: DateComponents(year: 2026, month: 4, day: 17))!
        let start = cal.startOfMonth(for: april17)
        let parts = cal.dateComponents([.year, .month, .day, .hour, .minute, .second], from: start)
        XCTAssertEqual(parts.year, 2026)
        XCTAssertEqual(parts.month, 4)
        XCTAssertEqual(parts.day, 1)
        XCTAssertEqual(parts.hour, 0)
        XCTAssertEqual(parts.minute, 0)
        XCTAssertEqual(parts.second, 0)
    }
}
