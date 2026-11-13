//
//  TextSizeSettingsSection.swift
//  fmusic
//
//  Created by Giacomo Sfratato on 09.11.26.
//  Copyright (c) 2026 Maximilian Bauer. All rights reserved.
//
//  This program is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//
//  This program is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License
//  along with this program.  If not, see <http://www.gnu.org/licenses/>.
//
import fmusicKit
import SwiftUI

/// Settings section to choose the text size used in fmusic
struct TextSizeSettingsSection: View {
  @EnvironmentObject
  private var settings: Settings

  /// Text size that is displayed while the system text size is used
  private var currentTextSize: UIContentSizeCategory {
    if let textSize = settings.textSize {
      return textSize
    }
    #if targetEnvironment(macCatalyst)
      return .large
    #else
      let systemTextSize = UIApplication.shared.preferredContentSizeCategory
      return TextScaling.textSizes.contains(systemTextSize) ? systemTextSize : .large
    #endif
  }

  /// Position of the text size in `TextScaling.textSizes`
  private var textSizeIndex: Binding<Double> {
    Binding<Double>(
      get: {
        let index = TextScaling.textSizes.firstIndex(of: currentTextSize) ??
          TextScaling.textSizes.firstIndex(of: .large) ?? 0
        return Double(index)
      },
      set: { newValue in
        let index = min(max(Int(newValue.rounded()), 0), TextScaling.textSizes.count - 1)
        let textSize = TextScaling.textSizes[index]
        if settings.textSize != textSize {
          settings.textSize = textSize
        }
      }
    )
  }

  private var isSystemTextSize: Binding<Bool> {
    Binding<Bool>(
      get: { settings.textSize == nil },
      set: { settings.textSize = $0 ? nil : currentTextSize }
    )
  }

  /// Mac: always (no system text size), iOS: if the system text size is not used
  private var isTextSizeSliderVisible: Bool {
    #if targetEnvironment(macCatalyst)
      return true
    #else
      return settings.textSize != nil
    #endif
  }

  private var textSizeFooter: String {
    #if targetEnvironment(macCatalyst)
      return L10n.tr(
        "%@: Size of the text in lists and album grids.",
        Self.textSizeName(currentTextSize)
      )
    #else
      guard settings.textSize != nil else {
        return L10n.tr("fmusic uses the text size from the iOS settings.")
      }
      return L10n.tr(
        "%@: Size of the text in fmusic.",
        Self.textSizeName(currentTextSize)
      )
    #endif
  }

  private static func textSizeName(_ textSize: UIContentSizeCategory) -> String {
    switch textSize {
    case .extraSmall: L10n.tr("Extra Small")
    case .small: L10n.tr("Small")
    case .medium: L10n.tr("Medium")
    case .large: L10n.tr("Default")
    case .extraLarge: L10n.tr("Large")
    case .extraExtraLarge: L10n.tr("Extra Large")
    case .extraExtraExtraLarge: L10n.tr("Extra Extra Large")
    case .accessibilityMedium: L10n.tr("Accessibility 1")
    case .accessibilityLarge: L10n.tr("Accessibility 2")
    case .accessibilityExtraLarge: L10n.tr("Accessibility 3")
    case .accessibilityExtraExtraLarge: L10n.tr("Accessibility 4")
    case .accessibilityExtraExtraExtraLarge: L10n.tr("Accessibility 5")
    default: textSize.rawValue
    }
  }

  var body: some View {
    SettingsSection(
      content: {
        #if !targetEnvironment(macCatalyst)
          SettingsCheckBoxRow(title: L10n.tr("Use System Text Size"), isOn: isSystemTextSize)
        #endif
        if isTextSizeSliderVisible {
          SettingsRow(title: L10n.tr("Text Size")) {
            Slider(
              value: textSizeIndex,
              in: 0 ... Double(TextScaling.textSizes.count - 1),
              step: 1
            ) {
              Text(L10n.tr("Text Size"))
            } minimumValueLabel: {
              Image(systemName: "textformat.size.smaller")
            } maximumValueLabel: {
              Image(systemName: "textformat.size.larger")
            }
          }
        }
      },
      footer: textSizeFooter
    )
  }
}
