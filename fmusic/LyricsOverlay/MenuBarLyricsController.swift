//
//  MenuBarLyricsController.swift
//  fmusic
//
//  Shows the currently sung lyric line in the macOS menu bar.
//
//  NSStatusBar is not exposed to Mac Catalyst, so the item is created through the
//  Objective-C runtime.
//

#if targetEnvironment(macCatalyst)

  import ObjectiveC
  import UIKit
  import fmusicKit

  // MARK: - MenuBarLyricsController

  @MainActor
  final class MenuBarLyricsController: NSObject {
    private static let maximumTitleLength = 48
    private static let variableLength = -1.0 as CGFloat

    private let statusBar: NSObject
    private let statusItem: NSObject
    private var currentText = ""

    var onOpenApp: (() -> Void)?

    private init(statusBar: NSObject, statusItem: NSObject) {
      self.statusBar = statusBar
      self.statusItem = statusItem
      super.init()

      statusItem.setValue(Self.variableLength, forKey: "length")
      if let button = statusItem.value(forKey: "button") as? NSObject {
        button.setValue(self, forKey: "target")
        Self.setAction(#selector(statusItemPressed), on: button)
      }
      update(title: "fmusic")
    }

    static func make() -> MenuBarLyricsController? {
      guard let statusBarClass = NSClassFromString("NSStatusBar") as? NSObject.Type,
            let statusBar = statusBarClass.perform(NSSelectorFromString("systemStatusBar"))?
            .takeUnretainedValue() as? NSObject,
            let statusItem = createStatusItem(in: statusBar)
      else { return nil }
      return MenuBarLyricsController(statusBar: statusBar, statusItem: statusItem)
    }

    func remove() {
      _ = statusBar.perform(NSSelectorFromString("removeStatusItem:"), with: statusItem)
    }

    func update(title: String) {
      let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
      let display = trimmed.isEmpty ? "fmusic" : trimmed
      guard display != currentText else { return }
      currentText = display
      let text = String(display.prefix(Self.maximumTitleLength))
      if let button = statusItem.value(forKey: "button") as? NSObject {
        button.setValue(text, forKey: "title")
        button.setValue(text, forKey: "toolTip")
      }
    }

    @objc
    private func statusItemPressed() {
      onOpenApp?()
    }

    // MARK: Runtime helpers

    private static func createStatusItem(in statusBar: NSObject) -> NSObject? {
      let selector = NSSelectorFromString("statusItemWithLength:")
      guard let method = class_getInstanceMethod(type(of: statusBar), selector) else {
        return nil
      }
      typealias StatusItemFunc = @convention(c) (AnyObject, Selector, CGFloat) -> AnyObject?
      let implementation = method_getImplementation(method)
      let function = unsafeBitCast(implementation, to: StatusItemFunc.self)
      return function(statusBar, selector, variableLength) as? NSObject
    }

    private static func setAction(_ action: Selector, on target: NSObject) {
      let selector = NSSelectorFromString("setAction:")
      guard let method = class_getInstanceMethod(type(of: target), selector) else { return }
      typealias SetActionFunc = @convention(c) (AnyObject, Selector, Selector) -> Void
      let implementation = method_getImplementation(method)
      let function = unsafeBitCast(implementation, to: SetActionFunc.self)
      function(target, selector, action)
    }
  }

#endif
