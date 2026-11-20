//
//  MacWindowHelper.swift
//  fmusic
//
//  Created by Mike Liddle on 04.03.26.
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

#if targetEnvironment(macCatalyst)

  import ObjectiveC
  import UIKit

  // NSWindow.Level.floating = 3, NSWindow.Level.normal = 0 https://developer.apple.com/documentation/appkit/nswindow/level-swift.struct
  private let nsWindowLevelFloating = 3
  private let nsWindowLevelNormal = 0

  enum MacWindowHelper {
    /// Brings the whole application to the front. Requesting a scene activation
    /// alone only raises the window within fmusic; because the desktop-lyrics
    /// panel is a nonactivating panel, clicking its controls never activates the
    /// app, so the main window would appear behind the frontmost app (e.g. a
    /// browser). Forcing activation makes "open main window" actually come to
    /// the front.
    static func activateApplication() {
      // 1) Preferred: NSRunningApplication.current.activate(.activateIgnoringOtherApps).
      //    Verified to raise fmusic above a frontmost browser on this machine.
      if let runningClass = NSClassFromString("NSRunningApplication") as? NSObject.Type,
         let app = runningClass
         .perform(NSSelectorFromString("currentApplication"))?
         .takeUnretainedValue(),
         app.responds(to: NSSelectorFromString("activateWithOptions:")),
         let method = class_getInstanceMethod(
           type(of: app),
           NSSelectorFromString("activateWithOptions:")
         ) {
        // NSApplicationActivationOptions.activateIgnoringOtherApps == 1 << 1.
        typealias ActivateOptionsFunc = @convention(c) (AnyObject, Selector, UInt) -> Bool
        let function = unsafeBitCast(
          method_getImplementation(method),
          to: ActivateOptionsFunc.self
        )
        let selector = NSSelectorFromString("activateWithOptions:")
        if function(app, selector, 1 << 1) { return }
      }
      // 2) Fallback: NSApplication.sharedApplication activateIgnoringOtherApps:.
      guard let appClass = NSClassFromString("NSApplication") as? NSObject.Type,
            let app = appClass
            .perform(NSSelectorFromString("sharedApplication"))?
            .takeUnretainedValue()
      else { return }
      for selectorName in ["activateIgnoringOtherApps:", "activate"] {
        let selector = NSSelectorFromString(selectorName)
        guard app.responds(to: selector),
              let method = class_getInstanceMethod(type(of: app), selector)
        else { continue }
        if selectorName.hasSuffix(":") {
          typealias ForceFunc = @convention(c) (AnyObject, Selector, Bool) -> ()
          let function = unsafeBitCast(
            method_getImplementation(method),
            to: ForceFunc.self
          )
          function(app, selector, true)
        } else {
          typealias ActivateFunc = @convention(c) (AnyObject, Selector) -> ()
          let function = unsafeBitCast(
            method_getImplementation(method),
            to: ActivateFunc.self
          )
          function(app, selector)
        }
        return
      }
    }

    static func setAlwaysOnTop(
      _ alwaysOnTop: Bool,
      sceneTitle: String
    ) {
      let level = alwaysOnTop ? nsWindowLevelFloating : nsWindowLevelNormal

      guard let appClass = NSClassFromString("NSApplication")
        as? NSObject.Type
      else { return }

      let sharedApp = appClass
        .perform(NSSelectorFromString("sharedApplication"))?
        .takeUnretainedValue()

      guard let app = sharedApp,
            let nsWindows = (app as AnyObject)
            .perform(NSSelectorFromString("windows"))?
            .takeUnretainedValue() as? [AnyObject]
      else { return }

      let setLevelSel = NSSelectorFromString("setLevel:")

      for nsWindow in nsWindows {
        guard let title = nsWindow
          .perform(NSSelectorFromString("title"))?
          .takeUnretainedValue() as? String,
          title == sceneTitle
        else { continue }

        guard let method = class_getInstanceMethod(
          type(of: nsWindow),
          setLevelSel
        ) else { continue }

        typealias SetLevelFunc = @convention(c)
          (AnyObject, Selector, Int) -> ()
        let impl = method_getImplementation(method)
        let setLevel = unsafeBitCast(impl, to: SetLevelFunc.self)
        setLevel(nsWindow, setLevelSel, level)
      }
    }
  }

#endif
