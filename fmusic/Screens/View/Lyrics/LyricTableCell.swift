//
//  LyricTableCell.swift
//  fmusic
//
//  Created by Maximilian Bauer on 17.06.24.
//  Copyright (c) 2021 Maximilian Bauer. All rights reserved.
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
import fmusicKit
import UIKit

// MARK: - LyricTableCellModel

@MainActor
class LyricTableCellModel {
  // White on the player's dark surface, and a dark gray on the light lyrics panel. This is
  // the same brightness adaptation Apple Music applies to lyrics over different backdrops.
  private static let activeTextColor = UIColor { traits in
    traits.userInterfaceStyle == .dark ? .white : UIColor(white: 0.32, alpha: 1)
  }

  private static let activeDimTextColor = UIColor { traits in
    traits.userInterfaceStyle == .dark
      ? UIColor.white.withAlphaComponent(0.55)
      : UIColor(white: 0.32, alpha: 0.55)
  }

  private static let inactiveTextColor = UIColor { traits in
    traits.userInterfaceStyle == .dark
      ? UIColor.white.withAlphaComponent(0.6)
      : UIColor(white: 0.5, alpha: 1)
  }

  private static let activeTranslationColor = UIColor { traits in
    traits.userInterfaceStyle == .dark
      ? UIColor.white.withAlphaComponent(0.72)
      : UIColor(white: 0.34, alpha: 0.82)
  }

  static let translationSpacing: CGFloat = 6

  let lyric: LyricsLine?
  let translation: String?
  var isActiveLine = false
  var isFullyHighlighted = false

  /// Per-syllable sung fraction, mapped from the playback clock onto displayed characters.
  private(set) var syllableProgress = [CGFloat]()
  let syllables: [LyricsSyllableTiming]

  let activeDimText: NSAttributedString?
  let activeBrightText: NSAttributedString?
  let inactiveText: NSAttributedString?
  let activeTranslationText: NSAttributedString?
  let inactiveTranslationText: NSAttributedString?

  private var cachedWidth: CGFloat = 0
  private var cachedOriginalHeight: CGFloat = 0
  private var cachedInactiveHeight: CGFloat = 0
  private var cachedTranslationHeight: CGFloat = 0

  init(lyric: LyricsLine, estimatedDuration: TimeInterval, centered: Bool = false) {
    let alignment: NSTextAlignment = centered ? .center : .left

    let lineParagraphStyle = NSMutableParagraphStyle()
    lineParagraphStyle.lineSpacing = 6
    lineParagraphStyle.lineBreakMode = .byWordWrapping
    lineParagraphStyle.alignment = alignment
    lineParagraphStyle.lineBreakStrategy = []

    let translationParagraphStyle = NSMutableParagraphStyle()
    translationParagraphStyle.lineSpacing = 3
    translationParagraphStyle.lineBreakMode = .byWordWrapping
    translationParagraphStyle.alignment = alignment
    translationParagraphStyle.lineBreakStrategy = []

    self.lyric = lyric
    let translationText = lyric.translation?
      .trimmingCharacters(in: .whitespacesAndNewlines)
    self.translation = (translationText?.isEmpty == false) ? translationText : nil
    self.syllables = LyricsTimingMap.syllables(
      for: lyric,
      estimatedDuration: estimatedDuration
    )

    let activeFont = UIFont.systemFont(ofSize: 29, weight: .bold)
    let inactiveFont = UIFont.systemFont(ofSize: 24, weight: .semibold)
    let text = lyric.value

    self.activeDimText = NSAttributedString(
      string: text,
      attributes: [
        .font: activeFont,
        .foregroundColor: Self.activeDimTextColor,
        .paragraphStyle: lineParagraphStyle,
      ]
    )
    self.activeBrightText = NSAttributedString(
      string: text,
      attributes: [
        .font: activeFont,
        .foregroundColor: Self.activeTextColor,
        .paragraphStyle: lineParagraphStyle,
      ]
    )
    self.inactiveText = NSAttributedString(
      string: text,
      attributes: [
        .font: inactiveFont,
        .foregroundColor: Self.inactiveTextColor,
        .paragraphStyle: lineParagraphStyle,
      ]
    )

    if let translationText, !translationText.isEmpty {
      let translationFont = UIFont.systemFont(ofSize: 17, weight: .regular)
      self.activeTranslationText = NSAttributedString(
        string: translationText,
        attributes: [
          .font: translationFont,
          .foregroundColor: Self.activeTranslationColor,
          .paragraphStyle: translationParagraphStyle,
        ]
      )
      self.inactiveTranslationText = NSAttributedString(
        string: translationText,
        attributes: [
          .font: translationFont,
          .foregroundColor: Self.inactiveTextColor,
          .paragraphStyle: translationParagraphStyle,
        ]
      )
    } else {
      self.activeTranslationText = nil
      self.inactiveTranslationText = nil
    }
  }

  /// Always measured with the active font so row heights stay stable while the
  /// emphasis animates in place.
  func calcHeight(containerWidth: CGFloat) -> CGFloat {
    updateCachedHeights(containerWidth: containerWidth)
    let translationHeight = activeTranslationText == nil
      ? 0
      : Self.translationSpacing + cachedTranslationHeight
    return cachedOriginalHeight + translationHeight
  }

  func calcOriginalHeight(containerWidth: CGFloat) -> CGFloat {
    updateCachedHeights(containerWidth: containerWidth)
    return cachedOriginalHeight
  }

  /// Height actually occupied by the line at the font size currently rendered.
  func calcInactiveHeight(containerWidth: CGFloat) -> CGFloat {
    updateCachedHeights(containerWidth: containerWidth)
    return cachedInactiveHeight
  }

  func calcTranslationHeight(containerWidth: CGFloat) -> CGFloat {
    updateCachedHeights(containerWidth: containerWidth)
    return cachedTranslationHeight
  }

  private func updateCachedHeights(containerWidth: CGFloat) {
    let width = LyricTableCell.adjustContainerWidthForMargins(containerWidth: containerWidth)
    guard abs(width - cachedWidth) > 0.5 else { return }
    cachedWidth = width
    cachedOriginalHeight = activeBrightText
      .map { LyricsTextLayout(text: $0, width: width).height } ?? 0
    cachedInactiveHeight = inactiveText
      .map { LyricsTextLayout(text: $0, width: width).height } ?? 0
    cachedTranslationHeight = activeTranslationText
      .map { LyricsTextLayout(text: $0, width: width).height } ?? 0
  }

  /// Maps the raw playback clock (seconds, lyrics offset already applied) onto the
  /// syllable timeline. Returns whether the values moved enough to repaint.
  func updateProgress(at seconds: TimeInterval) -> Bool {
    guard isActiveLine, !isFullyHighlighted, !syllables.isEmpty else { return false }
    var next = [CGFloat]()
    next.reserveCapacity(syllables.count)
    var changed = syllableProgress.count != syllables.count
    for (index, syllable) in syllables.enumerated() {
      let value = syllable.progress(at: seconds)
      if index >= syllableProgress.count || abs(syllableProgress[index] - value) > 0.002 {
        changed = true
      }
      next.append(value)
    }
    syllableProgress = next
    return changed
  }
}

// MARK: - LyricTableCell

class LyricTableCell: UITableViewCell {
  private weak var viewModel: LyricTableCellModel? = nil
  private static let sideInset: CGFloat = 22
  private static let maxTextColumnWidth: CGFloat = 560
  private static let blurContext = CIContext(options: nil)

  // Line layer: this cell owns position, scroll and emphasis.
  // Glyph layers: baseGlyph (unsung) and sungGlyph (sung, revealed by the syllable mask).
  private let glyphContainer = UIView()
  private let baseGlyph = LyricsGlyphView()
  private let sungGlyph = LyricsGlyphView()
  // Syllable layer: decides which glyphs of the line are revealed at this instant.
  private let syllableMask = LyricsSyllableMaskLayer()
  private let translationLabel = UILabel()

  private var blurredImageView: UIImageView!
  private var blurredImageSize: CGSize = .zero
  private var needsBlurredImage = true
  override var layoutMargins: UIEdgeInsets { get { BasicTableCell.margin } set {} }

  static func effectiveSideInset(for containerWidth: CGFloat) -> CGFloat {
    max(sideInset, (containerWidth - maxTextColumnWidth) / 2)
  }

  static func adjustContainerWidthForMargins(containerWidth: CGFloat) -> CGFloat {
    containerWidth - (2 * effectiveSideInset(for: containerWidth))
  }

  public override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
    super.init(style: style, reuseIdentifier: reuseIdentifier)
    commonInit()
  }

  required init?(coder aDecoder: NSCoder) {
    super.init(coder: aDecoder)
    commonInit()
  }

  private func commonInit() {
    selectionStyle = .none
    backgroundColor = .clear
    isAccessibilityElement = true

    // Apple Music blurs the inactive lines. The text is rasterized once per width and the
    // glyphs are blurred with Core Image, so only the text is soft and not a rectangle.
    blurredImageView = UIImageView(frame: .zero)
    blurredImageView.contentMode = .scaleToFill
    blurredImageView.isUserInteractionEnabled = false
    contentView.addSubview(blurredImageView)

    glyphContainer.isUserInteractionEnabled = false
    contentView.addSubview(glyphContainer)
    glyphContainer.addSubview(baseGlyph)
    glyphContainer.addSubview(sungGlyph)
    sungGlyph.layer.mask = syllableMask

    translationLabel.isUserInteractionEnabled = false
    translationLabel.backgroundColor = .clear
    translationLabel.numberOfLines = 0
    translationLabel.lineBreakMode = .byWordWrapping
    translationLabel.isAccessibilityElement = false
    contentView.addSubview(translationLabel)
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    guard let model = viewModel else { return }
    let sideInset = Self.effectiveSideInset(for: bounds.width)
    let originalHeight = min(
      model.calcOriginalHeight(containerWidth: bounds.width),
      bounds.height
    )
    let translationHeight = model.calcTranslationHeight(containerWidth: bounds.width)
    let hasTranslation = model.activeTranslationText != nil
    let totalHeight = originalHeight + (
      hasTranslation ? LyricTableCellModel.translationSpacing + translationHeight : 0
    )
    let width = max(0, bounds.width - (2 * sideInset))
    let textFrame = CGRect(
      x: sideInset,
      y: max(0, (bounds.height - totalHeight) / 2),
      width: width,
      height: originalHeight
    )
    glyphContainer.frame = textFrame
    blurredImageView.frame = textFrame
    baseGlyph.frame = glyphContainer.bounds
    sungGlyph.frame = glyphContainer.bounds
    syllableMask.setFrameWithoutAnimation(sungGlyph.bounds)

    // The row reserves the active font height so emphasis can animate in place.
    // Inactive lines render smaller, so hang the translation below the text that
    // is actually visible instead of below the reserved box.
    let isEmphasized = model.isActiveLine || model.isFullyHighlighted
    let renderedOriginalHeight = isEmphasized
      ? originalHeight
      : min(model.calcInactiveHeight(containerWidth: bounds.width), originalHeight)
    translationLabel.isHidden = !hasTranslation
    translationLabel.frame = CGRect(
      x: sideInset,
      y: textFrame.minY + renderedOriginalHeight + (
        hasTranslation ? LyricTableCellModel.translationSpacing : 0
      ),
      width: width,
      height: translationHeight
    )

    baseGlyph.updateLayoutIfNeeded(width: textFrame.width)
    sungGlyph.updateLayoutIfNeeded(width: textFrame.width)
    rebuildMask()
    applyProgress()
    updateBlurredImageIfNeeded()
  }

  func display(model: LyricTableCellModel) {
    viewModel = model
    needsBlurredImage = true
    refresh(animated: false)
  }

  /// Rebinds the cell to its row without discarding the cached blur snapshot.
  func sync(model: LyricTableCellModel, animated: Bool) {
    viewModel = model
    refresh(animated: animated)
  }

  func refresh(animated: Bool = false) {
    guard let model = viewModel else { return }
    let isActive = model.isActiveLine && !model.isFullyHighlighted

    baseGlyph.text = model.isFullyHighlighted
      ? model.activeBrightText
      : (isActive ? model.activeDimText : model.inactiveText)
    sungGlyph.text = isActive ? model.activeBrightText : nil
    sungGlyph.isHidden = !isActive
    translationLabel.attributedText = (model.isActiveLine || model.isFullyHighlighted)
      ? model.activeTranslationText
      : model.inactiveTranslationText
    translationLabel.isHidden = model.activeTranslationText == nil

    baseGlyph.updateLayoutIfNeeded(width: baseGlyph.bounds.width)
    sungGlyph.updateLayoutIfNeeded(width: sungGlyph.bounds.width)
    rebuildMask()
    applyProgress()

    updateBlurredImageIfNeeded()

    // The blurred copy is only meant for inactive lines. Hiding it outright keeps the
    // karaoke fill from ever compositing on top of the soft copy.
    blurredImageView.isHidden = model.isActiveLine || model.isFullyHighlighted
    setNeedsLayout()

    let applyScale = {
      let transform = (model.isActiveLine || model.isFullyHighlighted)
        ? CGAffineTransform.identity
        : CGAffineTransform(scaleX: 0.97, y: 0.97)
      self.glyphContainer.transform = transform
      self.blurredImageView.transform = transform
      self.translationLabel.transform = transform
    }
    let applyBlurAlpha = {
      self.blurredImageView.alpha = (model.isActiveLine || model.isFullyHighlighted) ? 0 : 1
    }
    if animated {
      // Swapping the text directly avoids the 22pt/27pt crossfade snapshot, which
      // momentarily draws two differently sized copies of the line on top of each other.
      UIView.animate(
        withDuration: 0.18,
        delay: 0,
        options: [.curveEaseOut, .beginFromCurrentState, .allowUserInteraction],
        animations: applyBlurAlpha
      )
      UIView.animate(
        withDuration: 0.32,
        delay: 0,
        usingSpringWithDamping: 0.78,
        initialSpringVelocity: 0.2,
        options: [.allowUserInteraction, .beginFromCurrentState],
        animations: applyScale
      )
    } else {
      applyBlurAlpha()
      applyScale()
    }
  }

  /// Called at display rate. Only the syllable mask changes; text is never re-laid out.
  func applyProgress() {
    guard let model = viewModel,
          model.isActiveLine,
          !model.isFullyHighlighted
    else {
      syllableMask.reset()
      return
    }
    syllableMask.apply(progress: model.syllableProgress)
  }

  private func rebuildMask() {
    guard let model = viewModel,
          model.isActiveLine,
          !model.isFullyHighlighted,
          !model.syllables.isEmpty,
          let layout = sungGlyph.layout
    else {
      syllableMask.update(rects: [])
      return
    }
    let rects = model.syllables.map { layout.rects(for: $0.range) }
    syllableMask.update(rects: rects)
  }

  private func updateBlurredImageIfNeeded() {
    guard let model = viewModel, let inactive = model.inactiveText else { return }
    let size = baseGlyph.bounds.size
    guard size.width > 0, size.height > 0 else { return }
    guard needsBlurredImage || blurredImageSize != size else { return }
    needsBlurredImage = false
    blurredImageSize = size

    let savedText = baseGlyph.text
    baseGlyph.text = inactive
    baseGlyph.updateLayoutIfNeeded(width: size.width)
    baseGlyph.setNeedsDisplay()
    baseGlyph.layoutIfNeeded()

    let format = UIGraphicsImageRendererFormat()
    format.scale = UIScreen.main.scale
    format.opaque = false
    let snapshot = UIGraphicsImageRenderer(bounds: baseGlyph.bounds, format: format)
      .image { _ in
        baseGlyph.layer.render(in: UIGraphicsGetCurrentContext()!)
      }

    baseGlyph.text = savedText
    baseGlyph.updateLayoutIfNeeded(width: size.width)
    baseGlyph.setNeedsDisplay()

    if let cgImage = snapshot.cgImage {
      let ciImage = CIImage(cgImage: cgImage)
      let radius = 2.2 * snapshot.scale
      let blurred = ciImage
        .clampedToExtent()
        .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: radius])
        .cropped(to: ciImage.extent)
      if let output = Self.blurContext.createCGImage(blurred, from: ciImage.extent) {
        blurredImageView.image = UIImage(
          cgImage: output,
          scale: snapshot.scale,
          orientation: .up
        )
      }
    }
  }

  override var accessibilityLabel: String? {
    get {
      guard let lyric = viewModel?.lyric else { return nil }
      guard let translation = lyric.translation,
            !translation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      else { return lyric.value }
      return lyric.value + "\n" + translation
    }
    set {}
  }
}
