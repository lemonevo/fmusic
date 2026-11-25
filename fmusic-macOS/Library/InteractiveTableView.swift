//
//  InteractiveTableView.swift
//  fmusic-macOS
//
//  Shared NSTableView subclass providing native keyboard activation (Return/Enter),
//  optional Delete handling, and row-aware right-click context menus.
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

/// `NSTableView` subclass with consistent keyboard activation, delete, and
/// right-click context menu support across library and queue lists.
@MainActor
final class InteractiveTableView: NSTableView {
  var onReturn: (() -> Void)?
  var onDelete: (() -> Void)?
  var onContextMenu: ((Int) -> NSMenu?)?

  override func keyDown(with event: NSEvent) {
    if (event.keyCode == 36 || event.keyCode == 76), selectedRow >= 0, let onReturn {
      onReturn()
      return
    }
    if (event.keyCode == 51 || event.keyCode == 117), selectedRow >= 0, let onDelete {
      onDelete()
      return
    }
    super.keyDown(with: event)
  }

  override func menu(for event: NSEvent) -> NSMenu? {
    guard let onContextMenu else { return super.menu(for: event) }
    let point = convert(event.locationInWindow, from: nil)
    let row = self.row(at: point)
    guard row >= 0 else { return nil }
    if !selectedRowIndexes.contains(row) {
      selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
    }
    return onContextMenu(row)
  }
}
