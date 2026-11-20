//
//  Utilities.swift
//  fmusicKit
//
//  Created by Maximilian Bauer on 09.03.19.
//  Copyright (c) 2019 Maximilian Bauer. All rights reserved.
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

import CoreData
import Foundation
import os.log

#if canImport(UIKit)
  import UIKit
#elseif canImport(AppKit)
  import AppKit
#endif

public typealias VoidFunctionCallback = () -> ()

// MARK: - CustomEquatable

public protocol CustomEquatable {
  func isEqualTo(_ other: CustomEquatable) -> Bool
}

extension CustomEquatable where Self: Equatable {
  public func isEqualTo(_ other: CustomEquatable) -> Bool {
    if let other = other as? Self { return self == other }
    return false
  }
}

// MARK: - Atomic

@propertyWrapper
public final class Atomic<Value>: Sendable {
  nonisolated(unsafe) private var value: Value
  private let lock = NSLock()

  public var wrappedValue: Value {
    get { lock.withLock { value } }
    set { lock.withLock { value = newValue } }
  }

  public init(wrappedValue value: Value) {
    self.value = value
  }
}

extension Bool {
  public mutating func toggle() {
    self = !self
  }

  public static func random(probabilityForTrueInPercent probability: Float) -> Bool {
    Float.random(in: 0 ..< 100) <= probability
  }
}

extension Int16 {
  public static func isValid(value: Int) -> Bool {
    !((value < Int16.min) || (value > Int16.max))
  }
}

extension Int32 {
  public static func isValid(value: Int) -> Bool {
    !((value < Int32.min) || (value > Int32.max))
  }
}

extension Int64 {
  public var asByteString: String {
    ByteCountFormatter.string(
      fromByteCount: self,
      countStyle: ByteCountFormatter.CountStyle.decimal
    )
  }
}

extension Int {
  public mutating func setOtherRandomValue(in targetRange: ClosedRange<Int>) {
    var newValue = 0
    repeat {
      newValue = Int.random(in: targetRange)
    } while newValue == self
    self = newValue
  }

  public func roundDownToFractionOf(_ value: Int) -> Int {
    (self / value) * value
  }

  public var asColonDurationString: String {
    var hourString = ""
    let hours = self / (60 * 60)
    if hours > 0 {
      hourString += "\(hours):"
    }
    let minutes = (self - (hours * 60 * 60)) / 60
    let seconds = self - ((hours * 60 * 60) + (minutes * 60))
    if hourString.isEmpty {
      return String(format: "%01d", Int(minutes)) + ":" + String(format: "%02d", Int(seconds))
    } else {
      return hourString + String(format: "%02d", Int(minutes)) + ":" +
        String(format: "%02d", Int(seconds))
    }
  }

  public var asDurationShortString: String {
    let formatter = DateComponentsFormatter()
    formatter.allowedUnits = [.hour, .minute]
    formatter.unitsStyle = .abbreviated
    return formatter.string(from: TimeInterval(self))!
  }

  public var asDurationString: String {
    let formatter = DateComponentsFormatter()
    formatter.allowedUnits = [.hour, .minute, .second]
    formatter.unitsStyle = .abbreviated
    return formatter.string(from: TimeInterval(self))!
  }

  public var asMinuteString: String {
    let formatter = DateComponentsFormatter()
    formatter.allowedUnits = [.minute]
    formatter.unitsStyle = .short
    return formatter.string(from: TimeInterval(self))!
  }

  public var asDayString: String {
    let formatter = DateComponentsFormatter()
    formatter.allowedUnits = [.day]
    formatter.unitsStyle = .short
    return formatter.string(from: TimeInterval(self))!
  }
}

extension String {
  public var asByteCount: Int? {
    guard !isEmpty else { return nil }
    if hasSuffix(" GB") {
      let stringSize = self[..<index(endIndex, offsetBy: -3)]
      guard let stringFloat = Float(stringSize) else { return nil }
      return Int(stringFloat * 1000 * 1000 * 1000)
    } else if hasSuffix(" MB") {
      let stringSize = self[..<index(endIndex, offsetBy: -3)]
      guard let stringFloat = Float(stringSize) else { return nil }
      return Int(stringFloat * 1000 * 1000)
    } else if hasSuffix(" KB") {
      let stringSize = self[..<index(endIndex, offsetBy: -3)]
      guard let stringFloat = Float(stringSize) else { return nil }
      return Int(stringFloat * 1000)
    } else if hasSuffix(" B") {
      let stringSize = self[..<index(endIndex, offsetBy: -2)]
      guard let stringFloat = Float(stringSize) else { return nil }
      return Int(stringFloat)
    } else {
      return nil
    }
  }

  public var sectionInitial: String {
    guard !isEmpty else { return "?" }
    let initial = String(
      prefix(1).folding(options: .diacriticInsensitive, locale: nil)
        .uppercased()
    )
    if let _ = initial.rangeOfCharacter(from: CharacterSet.decimalDigits) {
      return "#"
    } else if let _ = initial
      .rangeOfCharacter(from: CharacterSet(charactersIn: String.uppercaseAsciiLetters)) {
      return initial
    } else if let _ = initial
      .rangeOfCharacter(from: CharacterSet.letters) { // japanese / chinese letters
      return "&"
    } else {
      return "?"
    }
  }

  public static var uppercaseAsciiLetters: String {
    "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
  }
}

extension Dictionary where Value: Equatable {
  public func findKey(forValue val: Value) -> Key? {
    first(where: { $1 == val })?.key
  }
}

extension Array {
  public func object(at: Int) -> Element? {
    at < count ? self[at] : nil
  }

  public func chunked(intoSubarrayCount chunkCount: Int) -> [[Element]] {
    let chuckSize = Int(ceil(Float(count) / Float(chunkCount)))
    return chunked(intoSubarraySize: chuckSize)
  }

  public func chunked(intoSubarraySize size: Int) -> [[Element]] {
    guard count > 0 else { return [[Element]]() }
    return stride(from: 0, to: count, by: size).map {
      Array(self[$0 ..< Swift.min($0 + size, count)])
    }
  }

  /// Picks `n` random elements (partial Fisher-Yates shuffle approach)
  public subscript(randomPick pickCount: Int) -> [Element] {
    var copy = self
    let n = Swift.min(pickCount, count)
    for i in stride(from: count - 1, to: count - n - 1, by: -1) {
      copy.swapAt(i, Int(arc4random_uniform(UInt32(i + 1))))
    }
    return Array(copy.suffix(n))
  }

  public func prefix(upToAsArray: Int) -> [Element] {
    Array(prefix(upToAsArray))
  }
}

extension PlatformColor {
  public convenience init(hue: CGFloat, saturation: CGFloat, lightness: CGFloat, alpha: CGFloat) {
    precondition(
      0 ... 1 ~= hue &&
        0 ... 1 ~= saturation &&
        0 ... 1 ~= lightness &&
        0 ... 1 ~= alpha,
      "input range is out of range 0...1"
    )

    // from HSL TO HSB
    var newSaturation: CGFloat = 0.0
    let brightness = lightness + saturation * min(lightness, 1 - lightness)
    if brightness == 0 {
      newSaturation = 0.0
    } else {
      newSaturation = 2 * (1 - lightness / brightness)
    }
    self.init(hue: hue, saturation: newSaturation, brightness: brightness, alpha: alpha)
  }

  public func getHue(
    _ hue: UnsafeMutablePointer<CGFloat>?,
    saturation targetSaturation: UnsafeMutablePointer<CGFloat>?,
    lightness targetLightness: UnsafeMutablePointer<CGFloat>?,
    alpha targetAlpha: UnsafeMutablePointer<CGFloat>?
  )
    -> Bool {
    var saturation, brightness, alpha: CGFloat
    (saturation, brightness, alpha) = (0.0, 0.0, 0.0)
    getHue(hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
    // from HSB TO HSL
    var newSaturation: CGFloat = 0.0
    let lightness = brightness * (1 - saturation / 2)
    if lightness == 0 || lightness == 1 {
      newSaturation = 0.0
    } else {
      newSaturation = (brightness - lightness) / min(lightness, 1 - lightness)
    }

    targetSaturation?.pointee = newSaturation
    targetLightness?.pointee = lightness
    targetAlpha?.pointee = alpha
    return true
  }

  // 007AFF
  // r:0 g:122 b:255
  public static var defaultBlue: PlatformColor {
    #if canImport(UIKit)
      return UIColor(displayP3Red: 0 / 255, green: 122 / 255, blue: 1.0, alpha: 1.0)
    #else
      return NSColor(displayP3Red: 0 / 255, green: 122 / 255, blue: 1.0, alpha: 1.0)
    #endif
  }

  public static var gold: PlatformColor {
    #if canImport(UIKit)
      return UIColor(displayP3Red: 241 / 255, green: 194 / 255, blue: 66 / 255, alpha: 1.0)
    #else
      return NSColor(displayP3Red: 241 / 255, green: 194 / 255, blue: 66 / 255, alpha: 1.0)
    #endif
  }

  public static var labelColor: PlatformColor {
    #if canImport(UIKit)
      return UIColor.label
    #else
      return NSColor.labelColor
    #endif
  }

  public static var redHeart: PlatformColor {
    #if canImport(UIKit)
      return UIColor.red.withAlphaComponent(0.8)
    #else
      return NSColor.systemRed.withAlphaComponent(0.8)
    #endif
  }

  public static var fillColor: PlatformColor {
    #if canImport(UIKit)
      return UIColor.systemFill
    #else
      return NSColor.quaternaryLabelColor
    #endif
  }

  public static var secondaryLabelColor: PlatformColor {
    #if canImport(UIKit)
      return UIColor.secondaryLabel
    #else
      return NSColor.secondaryLabelColor
    #endif
  }
}

#if canImport(UIKit)
  extension UIActivityIndicatorView {
    public static var defaultStyle: Style {
      if #available(iOS 13.0, *) {
        return .medium
      } else {
        return .gray
      }
    }
  }
#endif

extension NSObject {
  public class var typeName: String {
    String(describing: self)
  }
}

extension Date {
  public var asIso8601String: String {
    let dateFormatter = ISO8601DateFormatter()
    return dateFormatter.string(from: self)
  }

  public var asShortDayMonthString: String {
    let dateFormatter = DateFormatter()
    dateFormatter.dateFormat = "d. MMMM"
    dateFormatter.timeZone = NSTimeZone(name: "UTC")! as TimeZone
    return dateFormatter.string(from: self)
  }

  public var asShortHrMinString: String {
    let dateFormatter = DateFormatter()
    dateFormatter.dateStyle = .none
    dateFormatter.timeStyle = .short
    return dateFormatter.string(from: self)
  }
}

extension URLComponents {
  public mutating func addQueryItem(name: String, value: Int) {
    addQueryItem(name: name, value: String(value))
  }

  public mutating func addQueryItem(name: String, value: String) {
    let queryItem = URLQueryItem(name: name, value: value)
    var queryItems = queryItems ?? [URLQueryItem]()
    queryItems.append(queryItem)
    self.queryItems = queryItems
  }
}

extension Array {
  public func element(at index: Int) -> Element? {
    index < count ? self[index] : nil
  }
}

extension Array where Element: Equatable {}

extension Array where Element: Hashable {
  /// The elements without duplicates, followed by the ones of `allElements` missing (e.g. new cases).
  /// Used to complete an order arranged by the user.
  public func completingOrder(with allElements: [Element]) -> [Element] {
    var seen = Set<Element>()
    let unique = filter { seen.insert($0).inserted }
    return unique + allElements.filter { !seen.contains($0) }
  }
}

extension Array where Element == String {
  public func sortAlphabeticallyAscending() -> [String] {
    sorted { $0.localizedStandardCompare($1) == ComparisonResult.orderedAscending }
  }

  public func sortAlphabeticallyDescending() -> [String] {
    sorted { $0.localizedStandardCompare($1) == ComparisonResult.orderedDescending }
  }
}
