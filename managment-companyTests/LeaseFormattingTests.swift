//
//  LeaseFormattingTests.swift
//  managment-company
//
//  D2.3: lease dates and amounts are shown in the Russian format shared with the web client
//  (`14 окт 2026`, `380 000 ₸`). Input parsing (`Money.parse`) keeps accepting the same text.
//  Canonical source: apps/ios/PropManager/Tests (mirrored into the wrapper test target by
//  `make ios-sync`).
//

import Foundation
import Testing
@testable import managment_company

/// Non-breaking and narrow spaces printed by the formatters, normalised for comparison.
private func plain(_ text: String) -> String {
    text.replacingOccurrences(of: "\u{00A0}", with: " ").replacingOccurrences(of: "\u{202F}", with: " ")
}

@MainActor
struct LeaseFormattingTests {
    @Test func moneyIsGroupedWithSymbolAfterTheNumber() {
        #expect(plain(Money(minor: 38_000_000, currency: "KZT").formatted()) == "380 000 ₸")
        #expect(plain(Money(minor: 2_500_000, currency: "KZT").formatted()) == "25 000 ₸")
        #expect(plain(Money(minor: 0, currency: "KZT").formatted()) == "0 ₸")
        #expect(plain(Money(minor: 123_456_789_00, currency: "KZT").formatted()) == "123 456 789 ₸")
    }

    @Test func moneySeparatorsAreNonBreaking() {
        let text = Money(minor: 38_000_000, currency: "KZT").formatted()
        #expect(text.contains("\u{00A0}"))
        #expect(!text.contains(" "))
    }

    @Test func moneyOfOtherCurrenciesUsesTheLocaleSymbol() {
        #expect(plain(Money(minor: 150_000, currency: "USD").formatted()) == "1 500 $")
        #expect(plain(Money(minor: 150_000, currency: "RUB").formatted()) == "1 500 ₽")
    }

    @Test func moneyRoundsToWholeUnitsForDisplay() {
        #expect(plain(Money(minor: 150_050, currency: "KZT").formatted()) == "1 501 ₸")
    }

    @Test func parsingInputIsUnchanged() {
        #expect(Money.parse("380 000", currency: "KZT") == Money(minor: 38_000_000, currency: "KZT"))
        #expect(Money.parse("380\u{00A0}000", currency: "KZT") == Money(minor: 38_000_000, currency: "KZT"))
        #expect(Money.parse("1500,50", currency: "KZT")?.minor == 150_050)
        #expect(Money(minor: 150_050, currency: "KZT").editableText == "1500.5")
    }

    @Test func leaseDayDisplayIsRussianShortDate() {
        #expect(LeaseDay.display("2026-10-14") == "14 окт 2026")
        #expect(LeaseDay.display("2026-05-08") == "8 мая 2026")
        #expect(LeaseDay.display("2026-03-15") == "15 марта 2026")
        #expect(LeaseDay.display("2026-01-01") == "1 янв 2026")
        #expect(LeaseDay.display("2026-12-31") == "31 дек 2026")
    }

    @Test func leaseDayDisplayIgnoresTimeAndHandlesMissingValues() {
        #expect(LeaseDay.display("2026-10-14T21:00:00Z") == "14 окт 2026")
        #expect(LeaseDay.display(nil) == "-")
        #expect(LeaseDay.display("") == "-")
        #expect(LeaseDay.display("not-a-date") == "not-a-date")
    }

    @Test func leaseDayShortStaysNumeric() {
        #expect(LeaseDay.short("2026-10-15") == "15.10.26")
    }
}
