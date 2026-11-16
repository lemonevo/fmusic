//
//  Created by Dimitrios Chatzieleftheriou on 18/06/2020.
//  Copyright © 2020 Decimal. All rights reserved.
//
//  Inspired by Thong Nguyen's StreamingKit. All rights reserved.
//

import AVFoundation
import OSLog

final class AudioPlayerRenderProcessor: NSObject {
  /// The AVAudioEngine's `AVAudioEngineManualRenderingBlock` render block from manual rendering
  var renderBlock: AVAudioEngineManualRenderingBlock?

  /// A block that notifies if the audio entry has finished playing
  var audioFinishedPlaying: ((_ entry: AudioEntry?) -> ())?

  private let playerContext: AudioPlayerContext
  private let rendererContext: AudioRendererContext
  private let outputAudioFormat: AudioStreamBasicDescription

  init(
    playerContext: AudioPlayerContext,
    rendererContext: AudioRendererContext,
    outputAudioFormat: AudioStreamBasicDescription
  ) {
    self.playerContext = playerContext
    self.rendererContext = rendererContext
    self.outputAudioFormat = outputAudioFormat
  }

  func attachCallback(on player: AVAudioUnit, audioFormat: AVAudioFormat) {
    // swiftformat:disable isEmpty -- AUAudioUnitBusArray has no isEmpty on Catalyst
    if player.auAudioUnit.inputBusses.count > 0 {
      do {
        try player.auAudioUnit.inputBusses[0].setFormat(audioFormat)
      } catch {
        Logger.error(
          "Player auAudioUnit inputbus failure %@",
          category: .audioRendering,
          args: error.localizedDescription
        )
      }
    }
    // set the max frames to render
    player.auAudioUnit.maximumFramesToRender = maxFramesPerSlice

    // sets the render provider callback
    player.auAudioUnit.outputProvider = renderProvider
  }

  /// Provides data to the audio engine
  ///
  /// - parameter inNumberFrames: An `AVAudioFrameCount` provided by the `AudioEngine` instance
  /// - returns An optional `UnsafePointer` of `AudioBufferList`
  func inRender(inNumberFrames: AVAudioFrameCount) -> UnsafePointer<AudioBufferList>? {
    playerContext.entriesLock.lock()
    let playingEntry = playerContext.audioPlayingEntry
    let readingEntry = playerContext.audioReadingEntry
    playerContext.entriesLock.unlock()
    let isMuted = playerContext.muted.value
    let state = playerContext.internalState

    rendererContext.lock.lock()
    var waitForBuffer = false
    var bufferList = rendererContext.inOutAudioBufferList[0]
    let bufferContext = rendererContext.bufferContext
    let frameSizeInBytes = bufferContext.sizeInBytes
    let used = bufferContext.frameUsedCount
    let start = bufferContext.frameStartIndex
    let crossfade = rendererContext.crossfadeState
    #if DEBUG
      assert(
        start < bufferContext.totalFrameCount,
        "frameStartIndex (\(start)) >= totalFrameCount (\(bufferContext.totalFrameCount)) - logic error!"
      )
      assert(
        used <= bufferContext.totalFrameCount,
        "frameUsedCount (\(used)) > totalFrameCount (\(bufferContext.totalFrameCount)) - logic error!"
      )
    #endif
    let signal = rendererContext.waiting.value && used < bufferContext.totalFrameCount / 2

    var playingFramesState: EntryFramesState?
    if let playingEntry = playingEntry {
      playingEntry.lock.lock()
      let framesState = playingEntry.framesState
      playingEntry.lock.unlock()
      playingFramesState = framesState

      if state == .waitingForData {
        var requiredFramesToStart = rendererContext.framesRequiredToStartPlaying
        if framesState.lastFrameQueued >= 0 {
          requiredFramesToStart = min(
            requiredFramesToStart,
            Double(playingEntry.framesState.lastFrameQueued)
          )
        }

        if readingEntry === playingEntry, framesState.queued < Int(requiredFramesToStart) {
          waitForBuffer = true
        }
      } else if state == .rebuffering {
        var requiredFramesToStart = rendererContext.framesRequiredAfterRebuffering
        if framesState.lastFrameQueued >= 0 {
          requiredFramesToStart = min(
            requiredFramesToStart,
            Double(framesState.lastFrameQueued - framesState.queued)
          )
        }
        if used < Int(requiredFramesToStart) {
          waitForBuffer = true
        }
      } else if state == .waitingForDataAfterSeek {
        var requiredFramesToStart = 1024
        if framesState.lastFrameQueued >= 0 {
          requiredFramesToStart = min(
            requiredFramesToStart,
            framesState.lastFrameQueued - framesState.queued
          )
        }
        if used < requiredFramesToStart {
          waitForBuffer = true
        }
      }
    }
    rendererContext.lock.unlock()

    var totalFramesCopied: UInt32 = 0
    if used > 0 && !waitForBuffer && playingEntry != nil && state
      .contains(.running) && state != .paused {
      // When a crossfade has been prepared, the outgoing entry must not read into the raw
      // head of the incoming entry. The head is skipped at the entry switch instead.
      var framesAvailableFromCurrent = Int(used)
      var crossfadeHeadFrames = 0
      var incomingPostHeadIndex: UInt32?
      if let crossfade, let playingEntry, playingEntry.id == crossfade.outgoingId,
         let framesState = playingFramesState, framesState.lastFrameQueued >= 0 {
        framesAvailableFromCurrent = min(
          framesAvailableFromCurrent,
          max(0, framesState.lastFrameQueued - framesState.played)
        )
        crossfadeHeadFrames = crossfade.frames
        incomingPostHeadIndex = (crossfade.incomingStartIndex + UInt32(crossfade.frames)) %
          bufferContext.totalFrameCount
      }

      let framesToCopyCurrent = min(Int(inNumberFrames), framesAvailableFromCurrent)
      var copiedFrames = 0
      if framesToCopyCurrent > 0 {
        copyRingFrames(from: Int(start), count: framesToCopyCurrent, to: bufferList, byteOffset: 0)
        copiedFrames = framesToCopyCurrent
      }

      if copiedFrames < Int(inNumberFrames), let incomingPostHeadIndex {
        let usedAfterCurrent = Int(used) - framesToCopyCurrent
        let availableIncoming = max(0, usedAfterCurrent - crossfadeHeadFrames)
        let framesToCopyIncoming = min(Int(inNumberFrames) - copiedFrames, availableIncoming)
        if framesToCopyIncoming > 0 {
          copyRingFrames(
            from: Int(incomingPostHeadIndex),
            count: framesToCopyIncoming,
            to: bufferList,
            byteOffset: copiedFrames * Int(frameSizeInBytes)
          )
          copiedFrames += framesToCopyIncoming
        }
      }

      totalFramesCopied = UInt32(copiedFrames)
      bufferList.mBuffers.mNumberChannels = 2
      bufferList.mBuffers.mDataByteSize = frameSizeInBytes * totalFramesCopied
      if isMuted, let mData = bufferList.mBuffers.mData {
        memset(mData, 0, Int(bufferList.mBuffers.mDataByteSize))
      }

      if totalFramesCopied > 0 {
        rendererContext.lock.lock()
        #if DEBUG
          if totalFramesCopied > bufferContext.frameUsedCount {
            Logger.debug(
              "Buffer race: tried to consume %d frames but only %d available (reset likely occurred)",
              category: .audioRendering,
              args: totalFramesCopied,
              bufferContext.frameUsedCount
            )
          }
        #endif
        bufferContext
          .frameStartIndex = (bufferContext.frameStartIndex + totalFramesCopied) % bufferContext
          .totalFrameCount
        if totalFramesCopied <= bufferContext.frameUsedCount {
          bufferContext.frameUsedCount -= totalFramesCopied
        } else {
          bufferContext.frameUsedCount = 0
        }
        rendererContext.lock.unlock()
      }

      if playerContext.internalState != .playing {
        playerContext.setInternalState(to: .playing, when: { state -> Bool in
          state.contains(.running) && state != .paused
        })
      }
    }

    if totalFramesCopied < inNumberFrames {
      let delta = inNumberFrames - totalFramesCopied
      if let mData = bufferList.mBuffers.mData {
        memset(mData + Int(totalFramesCopied * frameSizeInBytes), 0, Int(delta * frameSizeInBytes))
      }

      if !(
        playingEntry == nil || state == .waitingForDataAfterSeek || state == .waitingForData ||
          state == .rebuffering
      ) {
        if playerContext.internalState != .rebuffering {
          playerContext.setInternalState(to: .rebuffering, when: { state -> Bool in
            state.contains(.running) && state != .paused
          })
        }
      } else if state == .waitingForDataAfterSeek {
        if totalFramesCopied == 0 {
          rendererContext.waitingForDataAfterSeekFrameCount
            .write { $0 += Int32(inNumberFrames - totalFramesCopied) }
          if rendererContext.waitingForDataAfterSeekFrameCount
            .value > Int(rendererContext.framesRequiredForDataAfterSeekPlaying) {
            if playerContext.internalState != .playing {
              playerContext.setInternalState(to: .playing) { state -> Bool in
                state.contains(.running) && state != .playing
              }
            }
          }
        } else {
          rendererContext.waitingForDataAfterSeekFrameCount.write { $0 = 0 }
        }
      }
    }

    guard let currentPlayingEntry = playingEntry else {
      return nil
    }
    currentPlayingEntry.lock.lock()

    var extraFramesPlayedNotAssigned = 0
    var framesPlayedForCurrent = Int(totalFramesCopied)

    if currentPlayingEntry.framesState.lastFrameQueued >= 0 {
      let playedFrames = currentPlayingEntry.framesState.lastFrameQueued - currentPlayingEntry
        .framesState.played
      framesPlayedForCurrent = min(playedFrames, framesPlayedForCurrent)
    }

    currentPlayingEntry.framesState.played += Int(framesPlayedForCurrent)
    extraFramesPlayedNotAssigned = Int(totalFramesCopied) - framesPlayedForCurrent

    let lastFramePlayed = currentPlayingEntry.framesState.played == currentPlayingEntry.framesState
      .lastFrameQueued

    currentPlayingEntry.lock.unlock()
    if signal || lastFramePlayed {
      playerContext.entriesLock.lock()
      let entry = playerContext.audioPlayingEntry
      playerContext.entriesLock.unlock()
      if lastFramePlayed, playingEntry === entry {
        audioFinishedPlaying?(playingEntry)

        while extraFramesPlayedNotAssigned > 0 {
          playerContext.entriesLock.lock()
          let newEntry = playerContext.audioPlayingEntry
          playerContext.entriesLock.unlock()
          if let newEntry = newEntry {
            var framesPlayedForCurrent = extraFramesPlayedNotAssigned

            newEntry.lock.lock()
            let framesState = newEntry.framesState
            if newEntry.framesState.lastFrameQueued > 0 {
              framesPlayedForCurrent = min(
                framesState.lastFrameQueued - framesState.played,
                framesPlayedForCurrent
              )
            }

            newEntry.framesState.played += framesPlayedForCurrent

            if framesState.played == framesState.lastFrameQueued {
              newEntry.lock.unlock()
              audioFinishedPlaying?(newEntry)
            } else {
              newEntry.lock.unlock()
            }

            extraFramesPlayedNotAssigned -= framesPlayedForCurrent

          } else {
            break
          }
        }
      }
      if rendererContext.waiting.value {
        rendererContext.packetsSemaphore.signal()
      }
    }

    rendererContext.inOutAudioBufferList[0].mBuffers.mData = bufferList.mBuffers.mData
    rendererContext.inOutAudioBufferList[0].mBuffers.mDataByteSize = bufferList.mBuffers
      .mDataByteSize
    rendererContext.inOutAudioBufferList[0].mBuffers.mNumberChannels = outputAudioFormat
      .mChannelsPerFrame

    return UnsafePointer(rendererContext.inOutAudioBufferList)
  }

  /// Copies frames out of the decoded ring buffer, splitting at the ring boundary.
  private func copyRingFrames(
    from startIndex: Int,
    count: Int,
    to buffer: AudioBufferList,
    byteOffset: Int
  ) {
    guard count > 0,
          let source = rendererContext.audioBuffer.mData,
          let destination = buffer.mBuffers.mData
    else { return }
    let totalFrames = Int(rendererContext.bufferContext.totalFrameCount)
    let frameBytes = Int(rendererContext.bufferContext.sizeInBytes)
    let firstChunk = min(count, totalFrames - startIndex)
    memcpy(
      destination + byteOffset,
      source + startIndex * frameBytes,
      firstChunk * frameBytes
    )
    let remaining = count - firstChunk
    if remaining > 0 {
      memcpy(
        destination + byteOffset + firstChunk * frameBytes,
        source,
        remaining * frameBytes
      )
    }
  }

  func render(
    inNumberFrames: UInt32,
    ioData: UnsafeMutablePointer<AudioBufferList>,
    flags _: UnsafeMutablePointer<AudioUnitRenderActionFlags>
  )
    -> OSStatus {
    var status = noErr

    rendererContext.inOutAudioBufferList[0].mBuffers.mData = ioData.pointee.mBuffers.mData
    rendererContext.inOutAudioBufferList[0].mBuffers.mDataByteSize = ioData.pointee.mBuffers
      .mDataByteSize
    rendererContext.inOutAudioBufferList[0].mBuffers.mNumberChannels = outputAudioFormat
      .mChannelsPerFrame

    let renderStatus = renderBlock?(inNumberFrames, rendererContext.inOutAudioBufferList, &status)

    // Regardless of the returned status code, the output buffer's
    // `mDataByteSize` field will indicate the amount of PCM data bytes
    // rendered by the engine
    let bytesTotal = rendererContext.inOutAudioBufferList[0].mBuffers.mDataByteSize

    if bytesTotal == 0 {
      guard let renderStatus = renderStatus else { return noErr }
      switch renderStatus {
      case .success:
        return noErr
      case .insufficientDataFromInputNode:
        return noErr
      case .cannotDoInCurrentContext:
        Logger.error("cannotDoInCurrentContext", category: .audioRendering)
        return 0
      case .error:
        Logger.error("generic error", category: .audioRendering)
        return 0
      @unknown default:
        Logger.error("unknown error", category: .audioRendering)
        return 0
      }
    }
    return status
  }

  func renderProvider(
    flags: UnsafeMutablePointer<AudioUnitRenderActionFlags>,
    timeStamp _: UnsafePointer<AudioTimeStamp>,
    inNumberFrames: AUAudioFrameCount,
    inputBusNumber: Int,
    inputData: UnsafeMutablePointer<AudioBufferList>
  )
    -> AUAudioUnitStatus {
    guard inputBusNumber == 0 else { return noErr }
    return render(
      inNumberFrames: inNumberFrames,
      ioData: inputData,
      flags: flags
    )
  }
}
