//
//  LyricsSettingsView.swift
//  fmusic
//
//  Desktop and menu bar lyrics options, grouped on their own page.
//
//  This program is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//

import fmusicKit
import SwiftUI

// MARK: - LyricsSettingsView

struct LyricsSettingsView: View {
  @EnvironmentObject
  private var settings: Settings

  private var backgroundOpacityBinding: Binding<Double> {
    Binding(
      get: { Double(settings.desktopLyricsBackgroundOpacity) },
      set: { settings.desktopLyricsBackgroundOpacity = Int($0.rounded()) }
    )
  }

  private var opacityLabel: String {
    settings.desktopLyricsBackgroundOpacity == 0
      ? L10n.tr("Transparent")
      : "\(settings.desktopLyricsBackgroundOpacity)%"
  }

  private var iconBrightnessBinding: Binding<Double> {
    Binding(
      get: { Double(settings.desktopLyricsControlIconBrightness) },
      set: { settings.desktopLyricsControlIconBrightness = Int($0.rounded()) }
    )
  }

  private var iconBrightnessLabel: String {
    "\(settings.desktopLyricsControlIconBrightness)%"
  }

  var body: some View {
    ZStack {
      SettingsList {
        #if targetEnvironment(macCatalyst)
          SettingsSection(
            content: {
              SettingsCheckBoxRow(
                title: L10n.tr("Desktop Lyrics"),
                isOn: $settings.isDesktopLyricsEnabled
              )
            },
            footer:
            L10n
              .tr(
                "Show the current lyric line in a floating window above all other windows. Drag it to move it."
              )
          )

          if settings.isDesktopLyricsEnabled {
            SettingsSection(
              content: {
                SettingsRow(title: L10n.tr("Desktop Lyrics Font Size")) {
                  Picker("", selection: $settings.desktopLyricsFontSize) {
                    ForEach(DesktopLyricsFontSize.allCases, id: \.self) { size in
                      Text(size.description).tag(size)
                    }
                  }
                  .pickerStyle(.menu)
                  .labelsHidden()
                }
                SettingsRow(title: L10n.tr("Alignment")) {
                  Picker("", selection: $settings.desktopLyricsAlignment) {
                    ForEach(DesktopLyricsAlignment.allCases, id: \.self) { alignment in
                      Text(alignment.description).tag(alignment)
                    }
                  }
                  .pickerStyle(.menu)
                  .labelsHidden()
                }
                SettingsRow(title: L10n.tr("Background Opacity")) {
                  HStack(spacing: 10) {
                    Slider(value: backgroundOpacityBinding, in: 0 ... 100, step: 1)
                      .frame(width: 150)
                    Text(opacityLabel)
                      .font(.system(size: 12))
                      .foregroundStyle(.secondary)
                      .monospacedDigit()
                      .frame(width: 52, alignment: .trailing)
                  }
                }
                SettingsRow(title: L10n.tr("Control Bar Icon Color")) {
                  HStack(spacing: 10) {
                    Slider(value: iconBrightnessBinding, in: 0 ... 100, step: 1)
                      .frame(width: 150)
                    Text(iconBrightnessLabel)
                      .font(.system(size: 12))
                      .foregroundStyle(.secondary)
                      .monospacedDigit()
                      .frame(width: 52, alignment: .trailing)
                  }
                }
                SettingsCheckBoxRow(
                  title: L10n.tr("Show Next Line"),
                  isOn: $settings.isDesktopLyricsNextLineShown
                )
                SettingsCheckBoxRow(
                  title: L10n.tr("Always on Top"),
                  isOn: $settings.isDesktopLyricsAlwaysOnTop
                )
              },
              footer:
              L10n
                .tr(
                  "At 0% the background is fully transparent and only the lyrics remain. The hover control bar shares the background and has its own icon opacity."
                )
            )

            SettingsSection(
              content: {
                SettingsCheckBoxRow(
                  title: L10n.tr("Lock Desktop Lyrics"),
                  isOn: $settings.isDesktopLyricsLocked
                )
              },
              footer:
              L10n.tr("Lock the desktop lyrics in place and let mouse clicks pass through.")
            )
          }

          SettingsSection(
            content: {
              SettingsCheckBoxRow(
                title: L10n.tr("Menu Bar Lyrics"),
                isOn: $settings.isMenuBarLyricsEnabled
              )
            },
            footer:
            L10n
              .tr(
                "Show the current lyric line in the menu bar. When the menu bar is full, macOS keeps the item in the overflow area."
              )
          )
        #endif

        if let activeAccountInfo = settings.activeAccountInfo,
           appDelegate.storage.settings.accounts.getSetting(activeAccountInfo)
           .read.loginCredentials != nil {
          SettingsSection(
            content: {
              SettingsCheckBoxRow(
                title: L10n.tr("Lyrics Smooth Scrolling"),
                isOn: $settings.isLyricsSmoothScrolling
              )
            },
            footer:
            L10n.tr(
              "Lyrics are smoothly scrolled to next line. Deactivating will result in jumping from line to line."
            )
          )
        }
      }
    }
    .navigationTitle(L10n.tr("Lyrics"))
    .navigationBarTitleDisplayMode(.inline)
  }
}
