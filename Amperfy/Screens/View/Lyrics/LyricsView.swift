//
//  LyricsView.swift
//  Amperfy
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

import AmperfyKit
import CoreMedia
import Foundation
import UIKit

@MainActor
private final class LyricsDisplayLinkProxy {
  weak var owner: LyricsView?

  init(owner: LyricsView) {
    self.owner = owner
  }

  @objc func tick(_ link: CADisplayLink) {
    owner?.stepScrollSpring()
  }
}

class LyricsView: UITableView, UITableViewDataSource, UITableViewDelegate {
  private var lyrics: StructuredLyrics? = nil
  private var lyricModels: [LyricTableCellModel] = []
  private var lastIndex: Int?
  private var lineSpacing: CGFloat = 30
  private var scrollAnimation = true
  private var suppressAutoScrollUntil: Date?
  private let autoScrollSuppressionInterval: TimeInterval = 5.0
  private var lastLayoutWidth: CGFloat = 0
  private var lastLayoutHeight: CGFloat = 0
  private var isInitialScroll = true
  private var needsRealignAfterUserScroll = false
  // Start the switch slightly ahead of the timestamp so the fade/scroll animation has
  // finished by the time the line is actually sung.
  private let lyricsLeadTime: TimeInterval = 0.25

  // Apple Music fills the active line while it is sung. The line timestamps only give us
  // line starts, so the fill speed is estimated from the character count and the gap to
  // the next line.
  private var lineFillDurations: [Double] = []
  private var lastFillUpdateTimestamp: CFTimeInterval = 0

  // Apple Music keeps the line positions moving with a critically damped spring instead of
  // restarting a fixed-duration animation on every playback tick.
  private var springLink: CADisplayLink?
  private var springProxy: LyricsDisplayLinkProxy?
  private var scrollTargetY: CGFloat = 0
  private var scrollVelocity: CGFloat = 0
  private var scrollSpringIsSoft = false
  private var lastSpringTimestamp: CFTimeInterval = 0
  private lazy var fadeMask: CAGradientLayer = {
    let mask = CAGradientLayer()
    mask.colors = [
      UIColor.white.withAlphaComponent(0).cgColor,
      UIColor.white.cgColor,
      UIColor.white.cgColor,
      UIColor.white.withAlphaComponent(0).cgColor,
    ]
    mask.locations = [0, 0.2, 0.8, 1]
    return mask
  }()

  public var onLyricSelected: ((LyricsLine) -> ())?

  override init(frame: CGRect, style: UITableView.Style) {
    super.init(frame: frame, style: style)
    commonInit()
  }

  public required init?(coder aDecoder: NSCoder) {
    super.init(coder: aDecoder)
    commonInit()
  }

  private func commonInit() {
    register(LyricTableCell.self, forCellReuseIdentifier: LyricTableCell.typeName)

    separatorStyle = .none
    clipsToBounds = true

    dataSource = self
    delegate = self
    allowsSelection = true

    backgroundColor = .clear
    layer.mask = fadeMask
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    reloadInsets()

    // Row heights depend on the available width. Re-measure once the table has a real size
    // (the large player adds this view before its container is laid out).
    var needsRealign = false
    if bounds.width > 0, abs(bounds.width - lastLayoutWidth) > 0.5 {
      lastLayoutWidth = bounds.width
      reloadData()
      needsRealign = true
    }
    if bounds.height > 0, abs(bounds.height - lastLayoutHeight) > 0.5 {
      lastLayoutHeight = bounds.height
      needsRealign = true
    }
    if needsRealign, let lastIndex {
      scrollToRow(lastIndex, animated: false)
    }

    fadeMask.frame = bounds
    layer.masksToBounds = true
  }

  public func display(lyrics: StructuredLyrics, scrollAnimation: Bool) {
    self.lyrics = lyrics
    self.scrollAnimation = scrollAnimation
    reloadViewModels()
  }

  public func highlightAllLyrics() {
    lyricModels.forEach {
      $0.isActiveLine = true
      $0.isFullyHighlighted = true
    }
    reloadData()
  }

  public func clear() {
    stopScrollSpring()
    lyrics = nil
    reloadViewModels()
  }

  public func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
    lyricModels.count
  }

  public func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
    guard let model = lyricModels.object(at: indexPath.row) else { return 0.0 }
    return lineSpacing + model.calcHeight(containerWidth: bounds.width)
  }

  public func tableView(
    _ tableView: UITableView,
    estimatedHeightForRowAt indexPath: IndexPath
  )
    -> CGFloat {
    guard let model = lyricModels.object(at: indexPath.row) else { return 0.0 }
    return lineSpacing + model.calcHeight(containerWidth: bounds.width)
  }

  public func tableView(
    _ tableView: UITableView,
    cellForRowAt indexPath: IndexPath
  )
    -> UITableViewCell {
    let cell = dequeueReusableCell(
      withIdentifier: LyricTableCell.typeName,
      for: indexPath
    ) as! LyricTableCell
    if let model = lyricModels.object(at: indexPath.row) {
      cell.display(model: model)
    }
    return cell
  }

  public func tableView(
    _ tableView: UITableView,
    shouldHighlightRowAt indexPath: IndexPath
  )
    -> Bool {
    guard lyrics?.synced == true,
          let model = lyricModels.object(at: indexPath.row),
          model.lyric?.start != nil
    else { return false }
    return true
  }

  public func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
    guard lyrics?.synced == true,
          let model = lyricModels.object(at: indexPath.row),
          let lyric = model.lyric,
          lyric.start != nil
    else { return }
    // A tap is a deliberate jump, not manual scrolling: follow it immediately instead of
    // applying the drag-suppression window, otherwise the list stays on the old position
    // for seconds while the audio already plays the tapped line.
    suppressAutoScrollUntil = nil
    needsRealignAfterUserScroll = false
    scrollToRow(indexPath.row, animated: true, soft: true)
    onLyricSelected?(lyric)
  }

  public func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
    suppressAutoScrollUntil = Date().addingTimeInterval(autoScrollSuppressionInterval)
    needsRealignAfterUserScroll = true
    stopScrollSpring()
  }

  public func scrollViewDidEndDragging(
    _ scrollView: UIScrollView,
    willDecelerate decelerate: Bool
  ) {
    if !decelerate {
      suppressAutoScrollUntil = Date().addingTimeInterval(autoScrollSuppressionInterval)
    }
  }

  public func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
    suppressAutoScrollUntil = Date().addingTimeInterval(autoScrollSuppressionInterval)
  }

  /// A line change must not leave stale emphasis on rows whose cell was created while they
  /// were current, so every visible row is re-rendered from its model state.
  private func refreshAllVisibleCells(animated: Bool) {
    for cell in visibleCells {
      guard let indexPath = indexPath(for: cell),
            let model = lyricModels.object(at: indexPath.row),
            let lyricCell = cell as? LyricTableCell
      else { continue }
      lyricCell.sync(model: model, animated: animated)
    }
  }

  private func scrollToRow(_ row: Int, animated: Bool, soft: Bool = false) {
    guard row >= 0, row < numberOfRows(inSection: 0) else { return }
    let rowRect = rectForRow(at: IndexPath(row: row, section: 0))
    let lowerBound = -contentInset.top
    let upperBound = max(lowerBound, contentSize.height - bounds.height + contentInset.bottom)
    let target = min(max(rowRect.midY - bounds.height / 2, lowerBound), upperBound)

    guard animated,
          window != nil,
          !UIAccessibility.isReduceMotionEnabled
    else {
      stopScrollSpring()
      scrollTargetY = target
      contentOffset = CGPoint(x: contentOffset.x, y: target)
      return
    }

    // Catalyst rounds content offsets to half points, so a spring would never settle the
    // last fraction of a point. Snap the final step instead of spinning forever.
    if abs(target - contentOffset.y) <= 1.6 {
      stopScrollSpring()
      scrollTargetY = target
      contentOffset = CGPoint(x: contentOffset.x, y: target)
      return
    }

    if springLink != nil, abs(target - scrollTargetY) < 0.5 { return }
    scrollTargetY = target
    scrollSpringIsSoft = soft
    startScrollSpringIfNeeded()
  }

  private func startScrollSpringIfNeeded() {
    guard springLink == nil else { return }
    let proxy = LyricsDisplayLinkProxy(owner: self)
    let link = CADisplayLink(target: proxy, selector: #selector(LyricsDisplayLinkProxy.tick(_:)))
    link.add(to: .main, forMode: .common)
    springProxy = proxy
    springLink = link
    lastSpringTimestamp = CACurrentMediaTime()
  }

  private func stopScrollSpring() {
    springLink?.invalidate()
    springLink = nil
    springProxy = nil
    scrollVelocity = 0
  }

  fileprivate func stepScrollSpring() {
    let now = CACurrentMediaTime()
    var deltaTime = now - lastSpringTimestamp
    lastSpringTimestamp = now
    guard deltaTime > 0, deltaTime <= 0.1 else { return }

    if abs(scrollTargetY - contentOffset.y) <= 1.6, abs(scrollVelocity) < 40 {
      stopScrollSpring()
      contentOffset = CGPoint(x: contentOffset.x, y: scrollTargetY)
      return
    }

    // Normal line changes settle without overshoot; larger jumps (seeks, realigning after
    // the user scrolled) use the softer, slightly underdamped spring from AMLL's seek mode.
    let stiffness: CGFloat = scrollSpringIsSoft ? 90 : 190
    let damping: CGFloat = scrollSpringIsSoft ? 15 : 1.05 * 2 * sqrt(stiffness)
    let displacement = contentOffset.y - scrollTargetY
    scrollVelocity += (-stiffness * displacement - damping * scrollVelocity) * CGFloat(deltaTime)
    var newY = contentOffset.y + scrollVelocity * CGFloat(deltaTime)

    let lowerBound = -contentInset.top
    let upperBound = max(lowerBound, contentSize.height - bounds.height + contentInset.bottom)
    newY = min(max(newY, lowerBound), upperBound)

    if abs(scrollTargetY - newY) < 0.35, abs(scrollVelocity) < 4 {
      stopScrollSpring()
      newY = scrollTargetY
    }
    contentOffset = CGPoint(x: contentOffset.x, y: newY)
  }

  private func reloadViewModels() {
    lyricModels.removeAll()
    lineFillDurations.removeAll()
    lastIndex = nil
    isInitialScroll = true
    needsRealignAfterUserScroll = false
    stopScrollSpring()
    reloadInsets()

    guard let lyrics = lyrics else {
      reloadData()
      return
    }

    lineFillDurations = Self.fillDurations(for: lyrics.line)
    for (index, lyric) in lyrics.line.enumerated() {
      let model = LyricTableCellModel(
        lyric: lyric,
        estimatedDuration: lineFillDurations.object(at: index) ?? 0
      )
      lyricModels.append(model)
    }
    reloadData()
  }

  private static func fillDurations(for lines: [LyricsLine]) -> [Double] {
    lines.indices.map { index in
      let line = lines[index]
      let characterCount = line.value.reduce(0) { $0 + ($1.isWhitespace ? 0 : 1) }
      let estimated = Double(characterCount) * 0.36
      guard let start = line.start else { return max(estimated, 0.4) }
      let nextStart = lines[(index + 1)...].first(where: { $0.start != nil })?.start
      guard let nextStart else { return max(estimated, 0.4) }
      let gap = Double(nextStart - start) / 1_000
      guard gap > 0 else { return max(estimated, 0.4) }
      return max(0.4, min(estimated, gap * 0.9))
    }
  }

  private func updateActiveFill(rawSeconds: Double) {
    guard let row = lastIndex,
          row < lyricModels.count,
          let model = lyricModels.object(at: row),
          model.isActiveLine,
          !model.isFullyHighlighted
    else { return }

    // 30 Hz is plenty: the mask moves on the GPU and the glyph layout never changes.
    let now = CACurrentMediaTime()
    guard now - lastFillUpdateTimestamp >= 1.0 / 30.0 else { return }
    guard model.updateProgress(at: rawSeconds) else { return }
    lastFillUpdateTimestamp = now

    if let cell = cellForRow(at: IndexPath(row: row, section: 0)) as? LyricTableCell {
      cell.applyProgress()
    }
  }

  func reloadInsets() {
    let insets = UIEdgeInsets(
      top: frame.height / 2,
      left: 0,
      bottom: frame.height / 2,
      right: 0
    )
    if contentInset != insets {
      contentInset = insets
    }
  }

  func scroll(toTime time: CMTime) {
    guard let lyrics = lyrics,
          !lyricModels.isEmpty,
          lyrics.synced, // if the lyrics are not synced -> only display
          time.seconds.isFinite
    else { return }

    // The fill follows the raw audio clock (plus LRC offset). Word-timed lyrics use
    // their timestamps directly; the estimated fallback adds a small lead internally
    // so the first character is already lit when the line becomes current.
    defer {
      updateActiveFill(
        rawSeconds: time.seconds + (Double(lyrics.offset) / 1_000)
      )
    }

    let isAutoScrollAllowed: Bool = {
      guard let suppressUntil = suppressAutoScrollUntil else { return true }
      return Date() >= suppressUntil
    }()

    // A positive LRC offset makes the lyrics appear sooner.
    let adjustedSeconds = max(
      0,
      time.seconds + lyricsLeadTime + (Double(lyrics.offset) / 1_000)
    )
    let searchTime = CMTime(seconds: adjustedSeconds, preferredTimescale: 1_000)
    let isFirstSync = isInitialScroll

    guard let indexOfNextLine = lyrics.line.firstIndex(where: { $0.startTime >= searchTime }) else {
      // After the last line starts there is no next line; keep it highlighted until the song ends.
      let lastRow = lyricModels.count - 1
      if lastIndex != lastRow {
        let previousIndex = lastIndex
        if let lastIndex {
          lyricModels.object(at: lastIndex)?.isActiveLine = false
        }
        lastIndex = lastRow
        lyricModels.object(at: lastRow)?.isActiveLine = true
        refreshAllVisibleCells(animated: !isFirstSync)
        if isAutoScrollAllowed {
          let isRealigning = needsRealignAfterUserScroll
          needsRealignAfterUserScroll = false
          let soft = isRealigning ||
            (previousIndex.map { abs(lastRow - $0) > 1 } ?? false)
          scrollToRow(lastRow, animated: scrollAnimation && !isFirstSync, soft: soft)
        }
      } else if isAutoScrollAllowed, needsRealignAfterUserScroll {
        needsRealignAfterUserScroll = false
        scrollToRow(lastRow, animated: scrollAnimation, soft: true)
      }
      isInitialScroll = false
      return
    }

    // Before the first timestamp nothing is sung yet; show the first line without highlighting it.
    if indexOfNextLine == 0, searchTime < lyrics.line[0].startTime {
      let hadActiveLine = lastIndex != nil
      if let lastIndex {
        lyricModels.object(at: lastIndex)?.isActiveLine = false
        refreshAllVisibleCells(animated: !isFirstSync)
      }
      lastIndex = nil
      // A replay or a stream restart lands here with the list still scrolled to the old
      // line; keep the first line centered instead of only doing it on the first sync.
      if isAutoScrollAllowed {
        let isRealigning = needsRealignAfterUserScroll
        needsRealignAfterUserScroll = false
        scrollToRow(
          0,
          animated: scrollAnimation && !isFirstSync,
          soft: isRealigning || hadActiveLine
        )
      }
      isInitialScroll = false
      return
    }

    var prevIndex: Int?
    let indexOfCurrentLine = max(indexOfNextLine - 1, 0)
    if let lastIndex {
      lyricModels.object(at: lastIndex)?.isActiveLine = false
      prevIndex = lastIndex
    }
    lastIndex = indexOfCurrentLine
    lyricModels.object(at: indexOfCurrentLine)?.isActiveLine = true
    isInitialScroll = false

    let didChangeIndex = prevIndex != indexOfCurrentLine
    if didChangeIndex {
      refreshAllVisibleCells(animated: !isFirstSync)
    }

    if isAutoScrollAllowed, didChangeIndex || needsRealignAfterUserScroll {
      let isRealigning = needsRealignAfterUserScroll
      needsRealignAfterUserScroll = false
      let soft = isRealigning ||
        (prevIndex.map { abs(indexOfCurrentLine - $0) > 1 } ?? false)
      scrollToRow(indexOfCurrentLine, animated: scrollAnimation && !isFirstSync, soft: soft)
    }
  }

  deinit {
    stopScrollSpring()
  }
}
