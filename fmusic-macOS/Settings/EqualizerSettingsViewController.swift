//
//  EqualizerSettingsViewController.swift
//  fmusic-macOS
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

import AppKit
import fmusicKit

/// 均衡器: the global on/off switch, the active equalizer picker and the editor for the
/// custom equalizers of the core `EqualizerSetting` model.
///
/// The editor works on a local copy (`editingName` / `editingGains`): moving a band slider
/// previews the change through `player.updateEqualizerSetting` without writing the settings
/// store on every mouse movement. `Save` writes the equalizer back through the same
/// persistence the Catalyst app uses (a copy of `UserSettings`); leaving the page restores
/// the persisted active equalizer so a preview never survives the page.
@MainActor
final class EqualizerSettingsViewController: SettingsPageViewController {
  private var activePopup: SettingsPopUpButton?
  private var activeOptions: [EqualizerSetting] = []

  private var editingSetting: EqualizerSetting?
  private var editingName = ""
  private var editingGains = EqualizerSetting.defaultGains

  private var bandSliders: [SettingsSliderControl] = []
  private var hasPreviewed = false

  init() {
    super.init(title: L10n.tr("Equalizer"))
  }

  required init?(coder: NSCoder) {
    nil
  }

  // MARK: - Lifecycle

  override func viewWillDisappear() {
    super.viewWillDisappear()
    stopPreviewIfNeeded()
  }

  /// Drops a live preview when the page goes away: playback always matches the persisted
  /// active equalizer again after editing.
  private func stopPreviewIfNeeded() {
    guard hasPreviewed else { return }
    hasPreviewed = false
    applyPersistedEqualizer()
  }

  /// Pushes the persisted on/off state and active equalizer to the audio backend.
  private func applyPersistedEqualizer() {
    let user = SettingsStore.user
    SettingsStore.player.updateEqualizerEnabled(isEnabled: user.isEqualizerEnabled)
    SettingsStore.player.updateEqualizerSetting(eqSetting: user.activeEqualizerSetting)
  }

  // MARK: - Form

  override func buildForm() {
    activePopup = nil
    bandSliders.removeAll()

    loadEditingState()

    let user = SettingsStore.user
    let isEnabled = user.isEqualizerEnabled

    // MARK: On/off and active equalizer

    let enableRow = makeSwitchRow(
      title: L10n.tr("Enable Equalizer"),
      isOn: isEnabled
    ) { [weak self] isOn in
      SettingsStore.updateUser { $0.isEqualizerEnabled = isOn }
      SettingsStore.player.updateEqualizerEnabled(isEnabled: isOn)
      self?.hasPreviewed = false
      if isOn {
        // Reapply the persisted equalizer: the audio backend may still hold a preview.
        SettingsStore.player.updateEqualizerSetting(
          eqSetting: SettingsStore.user.activeEqualizerSetting
        )
      }
      self?.activePopup?.isEnabled = isOn
    }

    let activeRow = makeActiveEqualizerRow(isEnabled: isEnabled)
    addSection(rows: [enableRow, activeRow])

    // MARK: Editor

    var rows: [NSView] = [makeEqualizerPickerRow()]

    if editingSetting != nil {
      rows.append(makeNameRow())
      rows.append(contentsOf: makeBandRows())
      rows.append(makeActionsRow())
    }

    addSection(
      header: L10n.tr("Equalizer Editor"),
      footer: editingSetting == nil ? nil : L10n.tr(
        "Changes are applied immediately. Click Save to keep them."
      ),
      rows: rows
    )
  }

  /// Resolves the equalizer shown in the editor against the current settings so a stale
  /// selection (deleted elsewhere, settings changed outside the page) is dropped.
  private func loadEditingState() {
    guard let editing = editingSetting else {
      // Default to the first custom equalizer so the editor is usable right away.
      if let first = SettingsStore.user.equalizerSettings.first {
        editingSetting = first
        editingName = first.name
        editingGains = normalizedGains(first.gains)
      }
      return
    }

    guard let current = SettingsStore.user.equalizerSettings
      .first(where: { $0.id == editing.id }) else {
      editingSetting = nil
      editingName = ""
      editingGains = EqualizerSetting.defaultGains
      return
    }
    editingSetting = current
    editingName = current.name
    editingGains = normalizedGains(current.gains)
  }

  // MARK: - Active equalizer row

  private func makeActiveEqualizerRow(isEnabled: Bool) -> NSView {
    let activeSetting = SettingsStore.user.activeEqualizerSetting
    var options: [EqualizerSetting] = [.off] + SettingsStore.user.equalizerSettings
    if !options.contains(where: { $0.id == activeSetting.id }) {
      // A persisted active equalizer that is no longer part of the saved list (for example
      // a legacy preset) is kept selectable instead of being silently replaced by "Off".
      options.append(activeSetting)
    }
    activeOptions = options

    let titles = options.map { L10n.tr($0.name) }
    let selectedIndex = options.firstIndex(where: { $0.id == activeSetting.id }) ?? 0
    let popup = SettingsPopUpButton(titles: titles, selectedIndex: selectedIndex) {
      [weak self] index in
      guard let self, index >= 0, index < self.activeOptions.count else { return }
      let setting = self.activeOptions[index]
      SettingsStore.updateUser { $0.activeEqualizerSetting = setting }
      SettingsStore.player.updateEqualizerSetting(eqSetting: setting)
      self.hasPreviewed = false
    }
    popup.isEnabled = isEnabled
    activePopup = popup

    return makeRow(title: L10n.tr("Active Equalizer"), control: popup)
  }

  // MARK: - Editor rows

  private func makeEqualizerPickerRow() -> NSView {
    let settings = SettingsStore.user.equalizerSettings
    let createButton = SettingsButton(title: L10n.tr("Create new Equalizer")) { [weak self] in
      self?.createEqualizer()
    }

    guard !settings.isEmpty else {
      return SettingsRowView(title: "", control: createButton)
    }

    let titles = settings.map { L10n.tr($0.name) }
    var selectedIndex = 0
    if let editing = editingSetting,
       let index = settings.firstIndex(where: { $0.id == editing.id }) {
      selectedIndex = index
    }
    let popup = SettingsPopUpButton(titles: titles, selectedIndex: selectedIndex) {
      [weak self] index in
      guard let self else { return }
      let settings = SettingsStore.user.equalizerSettings
      guard index >= 0, index < settings.count else { return }
      self.select(settings[index])
    }

    let stack = NSStackView(views: [popup, createButton])
    stack.orientation = .horizontal
    stack.alignment = .centerY
    stack.spacing = 10
    stack.translatesAutoresizingMaskIntoConstraints = false

    return makeRow(title: L10n.tr("Equalizer"), control: stack)
  }

  private func makeNameRow() -> NSView {
    let field = SettingsTextField(
      text: editingName,
      placeholder: L10n.tr("Equalizer Name")
    ) { [weak self] newName in
      self?.editingName = newName
    }
    return makeRow(title: L10n.tr("Name"), control: field)
  }

  private func makeBandRows() -> [NSView] {
    let range = -Double(EqualizerSetting.rangeFromZero) ... Double(
      EqualizerSetting.rangeFromZero
    )
    return EqualizerSetting.frequencies.enumerated().map { index, frequency in
      let value = index < editingGains.count ? Double(editingGains[index]) : 0
      let slider = SettingsSliderControl(
        value: value,
        range: range,
        step: 0.5,
        sliderWidth: 240,
        valueFormatter: { String(format: "%+.1f dB", $0) }
      ) { [weak self] newValue in
        guard let self else { return }
        guard index < self.editingGains.count else { return }
        self.editingGains[index] = Float(newValue)
        self.previewGains()
      }
      bandSliders.append(slider)
      return SettingsRowView(title: Self.frequencyLabel(frequency), control: slider)
    }
  }

  private func makeActionsRow() -> NSView {
    let saveButton = SettingsButton(title: L10n.tr("Save")) { [weak self] in
      self?.saveEditing()
    }
    let resetButton = SettingsButton(title: L10n.tr("Reset")) { [weak self] in
      self?.resetBands()
    }
    let deleteButton = SettingsButton(title: L10n.tr("Delete")) { [weak self] in
      self?.confirmDelete()
    }
    deleteButton.contentTintColor = .systemRed

    let stack = NSStackView(views: [saveButton, resetButton, deleteButton])
    stack.orientation = .horizontal
    stack.alignment = .centerY
    stack.spacing = 8
    stack.translatesAutoresizingMaskIntoConstraints = false

    return SettingsRowView(title: "", control: stack)
  }

  // MARK: - Editing actions

  private func select(_ setting: EqualizerSetting) {
    stopPreviewIfNeeded()
    editingSetting = setting
    editingName = setting.name
    editingGains = normalizedGains(setting.gains)
    reloadForm()
  }

  private func createEqualizer() {
    let newSetting = EqualizerSetting(name: L10n.tr("My new Equalizer"))
    SettingsStore.updateUser { $0.equalizerSettings.append(newSetting) }
    select(newSetting)
  }

  private func previewGains() {
    // Preview only while the equalizer is on; the player ignores the setting otherwise.
    guard SettingsStore.user.isEqualizerEnabled else { return }
    var setting = editingSetting ?? EqualizerSetting(
      name: L10n.tr("My new Equalizer"),
      gains: editingGains
    )
    let trimmedName = editingName.trimmingCharacters(in: .whitespacesAndNewlines)
    if !trimmedName.isEmpty {
      setting.name = trimmedName
    }
    setting.gains = editingGains
    SettingsStore.player.updateEqualizerSetting(eqSetting: setting)
    hasPreviewed = true
  }

  private func saveEditing() {
    guard let editing = editingSetting else { return }
    var settings = SettingsStore.user.equalizerSettings
    guard let index = settings.firstIndex(where: { $0.id == editing.id }) else { return }

    var updated = editing
    let trimmedName = editingName.trimmingCharacters(in: .whitespacesAndNewlines)
    updated.name = trimmedName.isEmpty ? editing.name : trimmedName
    updated.gains = editingGains
    settings[index] = updated

    let isActive = SettingsStore.user.activeEqualizerSetting.id == updated.id
    SettingsStore.updateUser { user in
      user.equalizerSettings = settings
      if isActive {
        user.activeEqualizerSetting = updated
      }
    }

    editingSetting = updated
    editingName = updated.name
    if isActive {
      hasPreviewed = false
      SettingsStore.player.updateEqualizerSetting(eqSetting: updated)
    } else {
      // The edited equalizer is not the active one: stop previewing it.
      stopPreviewIfNeeded()
    }
    reloadForm()
  }

  private func resetBands() {
    editingGains = EqualizerSetting.defaultGains
    for slider in bandSliders {
      slider.setValue(0)
    }
    previewGains()
  }

  private func confirmDelete() {
    guard let editing = editingSetting else { return }

    let alert = NSAlert()
    alert.messageText = L10n.tr("Delete Equalizer")
    alert.informativeText = L10n.tr("Are you sure to delete this equalizer?")
    alert.alertStyle = .warning
    alert.addButton(withTitle: L10n.tr("Delete")).hasDestructiveAction = true
    alert.addButton(withTitle: L10n.tr("Cancel"))

    guard let window = view.window else {
      if alert.runModal() == .alertFirstButtonReturn {
        delete(editing)
      }
      return
    }
    alert.beginSheetModal(for: window) { [weak self] response in
      guard response == .alertFirstButtonReturn else { return }
      self?.delete(editing)
    }
  }

  private func delete(_ setting: EqualizerSetting) {
    let isActive = SettingsStore.user.activeEqualizerSetting.id == setting.id
    SettingsStore.updateUser { user in
      user.equalizerSettings.removeAll { $0.id == setting.id }
      if isActive {
        user.activeEqualizerSetting = .off
      }
    }
    if isActive {
      SettingsStore.player.updateEqualizerSetting(eqSetting: .off)
      hasPreviewed = false
    } else {
      // Stop previewing the deleted equalizer.
      stopPreviewIfNeeded()
    }

    editingSetting = nil
    editingName = ""
    editingGains = EqualizerSetting.defaultGains
    hasPreviewed = false
    reloadForm()
  }

  // MARK: - Helpers

  /// The core model owns the band count; equalizers loaded from older settings are padded
  /// or truncated so the editor always shows exactly the bands the player applies.
  private func normalizedGains(_ gains: [Float]) -> [Float] {
    var normalized = EqualizerSetting.defaultGains
    for (index, gain) in gains.enumerated() where index < normalized.count {
      normalized[index] = gain
    }
    return normalized
  }

  private static func frequencyLabel(_ frequency: Float) -> String {
    if frequency < 1000 {
      return "\(Int(frequency)) Hz"
    }
    return "\(Int(frequency / 1000)) kHz"
  }
}
