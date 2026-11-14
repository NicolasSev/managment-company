import SwiftUI
import UIKit

/// UIKit-level appearance that SwiftUI cannot express per screen: the masthead type of large
/// navigation titles. Bars keep the system (Liquid Glass) materials — only the title font and
/// colour are set.
enum AppAppearance {
    static func apply() {
        let ink = UIColor(AppTheme.Colors.textPrimary)
        let large = UIFont.systemFont(ofSize: 32, weight: .light, width: .expanded)
        let inline = UIFont.systemFont(ofSize: 16, weight: .semibold)
        let bar = UINavigationBar.appearance()
        bar.largeTitleTextAttributes = [
            .font: UIFontMetrics(forTextStyle: .largeTitle).scaledFont(for: large, maximumPointSize: 44),
            .foregroundColor: ink,
            .kern: -0.3,
        ]
        bar.titleTextAttributes = [
            .font: UIFontMetrics(forTextStyle: .headline).scaledFont(for: inline, maximumPointSize: 22),
            .foregroundColor: ink,
        ]
    }
}
