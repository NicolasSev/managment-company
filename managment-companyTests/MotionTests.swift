//
//  MotionTests.swift
//  managment-companyTests
//
//  D2.0: motion tokens and the pure parts of the motion modifiers. Canonical source:
//  apps/ios/PropManager/Tests (mirrored into the wrapper test target by `make ios-sync`).
//

import SwiftUI
import Testing
@testable import managment_company

@MainActor
struct MotionTests {
    @Test func staggerDelayGrowsByStepAndIsCapped() {
        #expect(AppTheme.Motion.staggerDelay(index: 0) == 0)
        #expect(abs(AppTheme.Motion.staggerDelay(index: 1) - 0.03) < 1e-9)
        #expect(abs(AppTheme.Motion.staggerDelay(index: 5) - 0.15) < 1e-9)
        let cap = AppTheme.Motion.staggerDelay(index: AppTheme.Motion.staggerLimit)
        #expect(AppTheme.Motion.staggerDelay(index: 50) == cap)
        #expect(abs(cap - 0.24) < 1e-9)
        #expect(AppTheme.Motion.staggerDelay(index: -3) == 0)
    }

    @Test func reduceMotionDropsDelayAndOffset() {
        #expect(AppTheme.Motion.staggerDelay(index: 7, reduceMotion: true) == 0)
        #expect(AppearStaggerModifier.offset(isVisible: false, reduceMotion: true) == 0)
        #expect(AppearStaggerModifier.offset(isVisible: false, reduceMotion: false) == 6)
        #expect(AppearStaggerModifier.offset(isVisible: true, reduceMotion: false) == 0)
    }

    @Test func reduceMotionReplacesSpringWithEaseInOut() {
        #expect(AppTheme.Motion.resolved(AppTheme.Motion.success, reduceMotion: true) == AppTheme.Motion.reduced)
        #expect(AppTheme.Motion.resolved(AppTheme.Motion.success, reduceMotion: false) == AppTheme.Motion.success)
        #expect(AppTheme.Motion.resolved(AppTheme.Motion.normal, reduceMotion: false) == AppTheme.Motion.normal)
    }

    /// The modifiers must build and lay out in a hosting renderer without a view hierarchy.
    @Test func modifiersRender() {
        let view = VStack {
            Text("380 000 ₸").moneyText(value: 380_000)
            Text("Загрузка").shimmerPlaceholder(true)
            Text("Строка").appearStagger(index: 2, isVisible: true)
        }
        let renderer = ImageRenderer(content: view)
        #expect(renderer.uiImage != nil)
    }
}
