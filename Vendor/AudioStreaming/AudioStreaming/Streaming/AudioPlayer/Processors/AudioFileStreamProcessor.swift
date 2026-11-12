//
//  Created by Dimitrios Chatzieleftheriou on 16/06/2020.
//  Copyright © 2020 Decimal. All rights reserved.
//
//  Inspired by Thong Nguyen's StreamingKit. All rights reserved.
//

import AVFoundation
import CoreAudio
import OSLog
import os

enum AudioConvertStatus: Int32 {
    case done = 100
    case processed = 0
}

struct AudioConvertInfo {
    var done: Bool
    let numberOfPackets: UInt32
    var audioBuffer = AudioBuffer()
    let packDescription: UnsafeMutablePointer<AudioStreamPacketDescription>?
}

enum FileStreamProcessorEffect {
    case processSource
    case raiseError(AudioPlayerError)
}

/// An object that handles the processing of AudioFileStream, its packets etc.
final class AudioFileStreamProcessor {
    private let maxCompressedPacketForBitrate = 4096

    var fileStreamCallback: ((FileStreamProcessorEffect) -> Void)?

    private let playerContext: AudioPlayerContext
    private let rendererContext: AudioRendererContext
    private let outputAudioFormat: AudioStreamBasicDescription
    
    // Add Ogg Vorbis processor
    private lazy var oggVorbisProcessor = OggVorbisStreamProcessor(
        playerContext: playerContext,
        rendererContext: rendererContext,
        outputAudioFormat: outputAudioFormat
    )

    var audioFileStream: AudioFileStreamID?
    var audioConverter: AudioConverterRef?
    var discontinuous: Bool = false
    var inputFormat = AudioStreamBasicDescription()

    var currentFileFormat: String = ""
    let fileFormatsForDelayedConverterCreation: Set = ["fa4m", "f4pm"]
    
    // Track if we're processing Ogg Vorbis
    private var isProcessingOggVorbis: Bool = false

    /// FLAC seeks in this player are byte offsets derived from the average bitrate, so the
    /// decoder can start seconds away from the requested time while the reported position
    /// stays at the request. Every FLAC frame header carries its exact frame/sample number;
    /// that number is used to correct the reported position and, if the landing is far off,
    /// to request a better byte offset once.
    private struct FlacSeekCorrection {
        weak var entry: AudioEntry?
        let requestedTime: Double
        var byteOffset: Int64
        var attempts: Int
        var blockSize: Int
    }

    private var flacSeekCorrection: FlacSeekCorrection?
    private let flacSeekLock = NSLock()
    private let flacSeekMaxAttempts = 2
    private let flacSeekTolerance = 0.25

    var isFileStreamOpen: Bool {
        audioFileStream != nil || isProcessingOggVorbis
    }

    init(playerContext: AudioPlayerContext,
         rendererContext: AudioRendererContext,
         outputAudioFormat: AudioStreamBasicDescription)
    {
        self.playerContext = playerContext
        self.rendererContext = rendererContext
        self.outputAudioFormat = outputAudioFormat
        
        // Set up Ogg Vorbis processor callback
        oggVorbisProcessor.processorCallback = { [weak self] effect in
            self?.fileStreamCallback?(effect)
        }
    }

    /// Opens the `AudioFileStream`
    ///
    /// - parameter fileHint: An `AudioFileTypeID` value indicating the file type.
    ///
    /// - Returns: An `OSStatus` value indicating if an error occurred or not.

    func openFileStream(with fileHint: AudioFileTypeID) -> OSStatus {
        // Check if this is an Ogg Vorbis file
        if fileHint == kAudioFileOggType {
            isProcessingOggVorbis = true
            return noErr
        } else {
            isProcessingOggVorbis = false
            let data = UnsafeMutableRawPointer.from(object: self)
            return AudioFileStreamOpen(data, _propertyListenerProc, _propertyPacketsProc, fileHint, &audioFileStream)
        }
    }

    /// Closes the currently open `AudioFileStream` instance, if opened.
    func closeFileStreamIfNeeded() {
        flacSeekLock.lock()
        flacSeekCorrection = nil
        flacSeekLock.unlock()
        if isProcessingOggVorbis {
            isProcessingOggVorbis = false
            oggVorbisProcessor.cleanup()
            return
        }
        
        guard let fileStream = audioFileStream else {
            Logger.debug("audio file stream not opened", category: .generic)
            return
        }
        AudioFileStreamClose(fileStream)
        audioFileStream = nil
    }

    /// Parses the given data using `AudioFileStreamParseBytes`
    ///
    /// - parameter data: A `Data` object containing the audio data to be parsed.
    ///
    /// - Returns: An `OSStatus` value indicating if an error occurred or not.
    func parseFileStreamBytes(data: Data) -> OSStatus {
        guard !data.isEmpty else { return 0 }

        // Check if we're processing Ogg Vorbis
        if isProcessingOggVorbis {
            return oggVorbisProcessor.parseOggVorbisData(data: data)
        }

        // Data that belongs to a byte offset we are about to replace must not reach the parser.
        if handleFlacSeekCorrectionIfNeeded(data: data) {
            return noErr
        }

        guard let stream = audioFileStream else { return 0 }
        let flags: AudioFileStreamParseFlags = discontinuous ? .discontinuity : .init()
        return data.withUnsafeBytes { buffer -> OSStatus in
            AudioFileStreamParseBytes(stream, UInt32(buffer.count), buffer.baseAddress, flags)
        }
    }

    // MARK: - FLAC seek correction

    private struct FlacFrameHeader {
        let bytePosition: Int
        let blockingStrategy: UInt8
        let number: UInt64
        let blockSize: Int
    }

    /// Returns true when the chunk belongs to an offset that was replaced by a correction seek
    /// and therefore must not be parsed.
    private func handleFlacSeekCorrectionIfNeeded(data: Data) -> Bool {
        flacSeekLock.lock()
        let pending = flacSeekCorrection
        flacSeekLock.unlock()
        guard var correction = pending, let entry = correction.entry else { return false }

        let sampleRate = Double(entry.audioStreamFormat.mSampleRate)
        guard sampleRate > 0 else {
            clearFlacSeekCorrection()
            return false
        }

        guard let frame = data.withUnsafeBytes({ buffer -> FlacFrameHeader? in
            guard let base = buffer.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                return nil
            }
            return firstValidFlacFrame(in: base, count: buffer.count,
                                       expectedTime: correction.requestedTime,
                                       sampleRate: sampleRate)
        }) else {
            // No complete frame yet; keep waiting for the next chunk.
            return false
        }

        if correction.blockSize == 0 {
            let streamBlockSize = Int(entry.audioStreamFormat.mFramesPerPacket)
            correction.blockSize = streamBlockSize > 0 ? streamBlockSize : frame.blockSize
        }
        let blockSize = correction.blockSize > 0 ? correction.blockSize : frame.blockSize
        guard blockSize > 0 else {
            clearFlacSeekCorrection()
            return false
        }

        let sample = frame.blockingStrategy == 0
            ? Double(frame.number) * Double(blockSize)
            : Double(frame.number)
        let actualTime = min(max(sample / sampleRate, 0), entry.duration())
        let delta = correction.requestedTime - actualTime

        if abs(delta) > flacSeekTolerance, correction.attempts < flacSeekMaxAttempts {
            let bytesPerSecond = localBytesPerSecond(in: data, blockSize: blockSize,
                                                     sampleRate: sampleRate)
                ?? globalBytesPerSecond(entry: entry)
            guard bytesPerSecond > 0 else {
                entry.lock.lock()
                entry.seekTime = actualTime
                entry.lock.unlock()
                clearFlacSeekCorrection()
                return false
            }
            let minOffset = Int64(entry.audioStreamState.dataOffset)
            let maxOffset = Int64(max(entry.length - 2 * Int(entry.processedPacketsState.bufferSize), 0))
            let corrected = min(max(correction.byteOffset + Int64(delta * bytesPerSecond), minOffset), maxOffset)
            correction.attempts += 1
            correction.byteOffset = corrected
            flacSeekLock.lock()
            flacSeekCorrection = correction
            flacSeekLock.unlock()
            os_log(.default, "FLAC seek correction: requested=%.3f landed=%.3f, retrying at byte %lld", correction.requestedTime, actualTime, corrected)
            applySeekOffset(corrected, entry: entry)
            return true
        }

        entry.lock.lock()
        entry.seekTime = actualTime
        entry.lock.unlock()
        clearFlacSeekCorrection()
        os_log(.default, "FLAC seek correction: requested=%.3f landed=%.3f attempts=%d", correction.requestedTime, actualTime, correction.attempts)
        return false
    }


    private func clearFlacSeekCorrection() {
        flacSeekLock.lock()
        flacSeekCorrection = nil
        flacSeekLock.unlock()
    }

    /// Same state transition as the tail of `processSeek()`, used for a second attempt.
    private func applySeekOffset(_ offset: Int64, entry: AudioEntry) {
        if let converted = audioConverter {
            AudioConverterReset(converted)
        }
        entry.reset()
        entry.seek(at: Int(offset))
        rendererContext.waitingForDataAfterSeekFrameCount.write { $0 = 0 }
        playerContext.setInternalState(to: .waitingForDataAfterSeek)
        rendererContext.resetBuffers()
    }

    private func globalBytesPerSecond(entry: AudioEntry) -> Double {
        let byteLength = Double(max(Int64(entry.length) - Int64(entry.audioStreamState.dataOffset), 0))
        let duration = entry.duration()
        if duration > 0 { return byteLength / duration }
        let bitrate = entry.calculatedBitrate()
        return bitrate > 0 ? bitrate / 8.0 : 0
    }

    private func localBytesPerSecond(in data: Data, blockSize: Int, sampleRate: Double) -> Double? {
        data.withUnsafeBytes { buffer -> Double? in
            guard let base = buffer.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                return nil
            }
            var frames: [FlacFrameHeader] = []
            var index = 0
            while index < buffer.count - 8, frames.count < 2 {
                guard let frame = flacFrameHeader(in: base, count: buffer.count, at: index) else {
                    index += 1
                    continue
                }
                frames.append(frame)
                index = frame.bytePosition + 1
            }
            guard frames.count == 2 else { return nil }
            let first = frames[0]
            let second = frames[1]
            let time1 = first.blockingStrategy == 0
                ? Double(first.number) * Double(blockSize) / sampleRate
                : Double(first.number) / sampleRate
            let time2 = second.blockingStrategy == 0
                ? Double(second.number) * Double(blockSize) / sampleRate
                : Double(second.number) / sampleRate
            let timeDelta = time2 - time1
            guard timeDelta > 0 else { return nil }
            return Double(second.bytePosition - first.bytePosition) / timeDelta
        }
    }

    private func firstValidFlacFrame(in bytes: UnsafePointer<UInt8>, count: Int,
                                     expectedTime: Double, sampleRate: Double) -> FlacFrameHeader? {
        var index = 0
        while index < count - 8 {
            guard let frame = flacFrameHeader(in: bytes, count: count, at: index) else {
                index += 1
                continue
            }
            let block = frame.blockSize
            if block > 0 {
                let time = frame.blockingStrategy == 0
                    ? Double(frame.number) * Double(block) / sampleRate
                    : Double(frame.number) / sampleRate
                // A false sync in compressed data rarely passes the header CRC, but keep the
                // position plausible anyway.
                if abs(time - expectedTime) < 30 {
                    return frame
                }
            }
            index += 1
        }
        return nil
    }

    /// Parses one FLAC frame header (RFC 9639 section 9.1); returns nil when the bytes at
    /// `index` are not the start of a valid header.
    private func flacFrameHeader(in bytes: UnsafePointer<UInt8>, count: Int,
                                 at index: Int) -> FlacFrameHeader? {
        guard index + 8 <= count else { return nil }
        guard bytes[index] == 0xFF, (bytes[index + 1] & 0xFE) == 0xF8 else { return nil }

        let blockingStrategy = bytes[index + 1] & 0x01
        let blockSizeCode = (bytes[index + 2] & 0xF0) >> 4
        let sampleRateCode = bytes[index + 2] & 0x0F

        var position = index + 4
        guard position < count else { return nil }
        let first = bytes[position]
        var leadingOnes = 0
        var mask: UInt8 = 0x80
        while first & mask != 0 {
            leadingOnes += 1
            mask >>= 1
        }
        let number: UInt64
        if leadingOnes == 0 {
            number = UInt64(first & 0x7F)
            position += 1
        } else if leadingOnes == 1 || leadingOnes > 6 {
            return nil
        } else {
            var value = UInt64(first & (0xFF >> (leadingOnes + 1)))
            position += 1
            for _ in 1 ..< leadingOnes {
                guard position < count, bytes[position] & 0xC0 == 0x80 else { return nil }
                value = (value << 6) | UInt64(bytes[position] & 0x3F)
                position += 1
            }
            number = value
        }

        var blockSize = 0
        switch blockSizeCode {
        case 1: blockSize = 192
        case 2 ... 5: blockSize = 576 << (blockSizeCode - 2)
        case 6:
            guard position < count else { return nil }
            blockSize = Int(bytes[position]) + 1
            position += 1
        case 7:
            guard position + 1 < count else { return nil }
            blockSize = Int(bytes[position]) << 8 | Int(bytes[position + 1])
            blockSize += 1
            position += 2
        case 8 ... 15:
            blockSize = 256 << (blockSizeCode - 8)
        default:
            blockSize = 0
        }
        switch sampleRateCode {
        case 12: position += 1
        case 13, 14: position += 2
        default: break
        }
        guard position < count else { return nil }
        guard flacHeaderCrc8(bytes, from: index, to: position) == bytes[position] else { return nil }
        return FlacFrameHeader(bytePosition: index, blockingStrategy: blockingStrategy,
                               number: number, blockSize: blockSize)
    }

    private func flacHeaderCrc8(_ bytes: UnsafePointer<UInt8>, from start: Int, to end: Int) -> UInt8 {
        var crc: UInt8 = 0
        for index in start ..< end {
            crc ^= bytes[index]
            for _ in 0 ..< 8 {
                crc = (crc & 0x80) != 0 ? (crc << 1) ^ 0x07 : (crc << 1)
            }
        }
        return crc
    }

    
    /// Flushes any remaining packets from the AudioFileStream parser.
    ///
    /// This must be called at the end of a stream to ensure the final packet is delivered,
    /// particularly important for formats like FLAC that use sync words to determine packet boundaries.
    ///
    /// As documented in AudioFileStream.h:
    /// "At the end of the stream, this function must be called once with null data pointer
    /// and zero data byte size to flush any remaining packets out of the parser."
    ///
    /// - Returns: An `OSStatus` value indicating if an error occurred or not.
    func flushRemainingPackets() -> OSStatus {
        // Ogg Vorbis doesn't need flushing (handled internally)
        if isProcessingOggVorbis {
            return noErr
        }
        
        guard let stream = audioFileStream else { return noErr }
        
        // Call AudioFileStreamParseBytes with 0 bytes and nil data to flush the final packet
        let status = AudioFileStreamParseBytes(stream, 0, nil, [])
        
        if status != noErr {
            Logger.debug("Failed to flush AudioFileStream packets: \(status)", category: .generic)
        }
        
        return status
    }

    func processSeek() {
        guard let readingEntry = playerContext.audioReadingEntry else {
            return
        }
        
        // If processing Ogg Vorbis, use the Ogg Vorbis processor
        if isProcessingOggVorbis {
            oggVorbisProcessor.processSeek()
            return
        }
        
        guard let stream = audioFileStream else { return }

        guard readingEntry.calculatedBitrate() > 0.0 || (playerContext.audioPlayingEntry?.length ?? 0) > 0 else {
            return
        }

        let dataOffset = Double(readingEntry.audioStreamState.dataOffset)
        let dataLengthInBytes = Double(readingEntry.audioDataLengthBytes())
        let entryDuration = readingEntry.duration()
        let duration = entryDuration < readingEntry.progress && entryDuration > 0 ? readingEntry.progress : entryDuration
      
        guard duration > 0.0 else { return }

        var seekByteOffset = Int64(dataOffset + (readingEntry.seekRequest.time / duration) * dataLengthInBytes)

        if seekByteOffset > readingEntry.length - (2 * Int(readingEntry.processedPacketsState.bufferSize)) {
            seekByteOffset = Int64(readingEntry.length - (2 * Int(readingEntry.processedPacketsState.bufferSize)))
        }

        readingEntry.lock.lock()
        readingEntry.seekTime = readingEntry.seekRequest.time
        readingEntry.lock.unlock()

        let bitrate = readingEntry.calculatedBitrate()
        if readingEntry.packetDuration > 0, bitrate > 0 {
            var ioFlags = AudioFileStreamSeekFlags(rawValue: 0)
            var packetsAlignedByteOffset: Int64 = 0
            let seekPacket = Int64(floor(readingEntry.seekRequest.time / readingEntry.packetDuration))

            let seekStatus = AudioFileStreamSeek(stream, seekPacket, &packetsAlignedByteOffset, &ioFlags)
            let dataOffset = Int64(readingEntry.audioStreamState.dataOffset)
            if seekStatus == noErr, !ioFlags.contains(.offsetIsEstimated) {
                let delta = Double((seekByteOffset - dataOffset) - packetsAlignedByteOffset) / (bitrate * 8)
                readingEntry.lock.lock()
                readingEntry.seekTime -= delta
                readingEntry.lock.unlock()
                seekByteOffset = packetsAlignedByteOffset + dataOffset
            }
        }

        if let converted = audioConverter {
            AudioConverterReset(converted)
        }

                if readingEntry.audioStreamFormat.mFormatID == kAudioFormatFLAC {
            flacSeekLock.lock()
            flacSeekCorrection = FlacSeekCorrection(
                entry: readingEntry,
                requestedTime: readingEntry.seekRequest.time,
                byteOffset: seekByteOffset,
                attempts: 0,
                blockSize: 0
            )
            flacSeekLock.unlock()
            
        }

        readingEntry.reset()
        readingEntry.seek(at: Int(seekByteOffset))
        rendererContext.waitingForDataAfterSeekFrameCount.write { $0 = 0 }
        playerContext.setInternalState(to: .waitingForDataAfterSeek)
        rendererContext.resetBuffers()
    }

    /// Creates an `AudioConverter` instance to be used for converting the remote audio data to the canonical audio format
    ///
    /// - parameter fromFormat: An `AudioStreamBasicDescription` indicating the format of the remote audio
    /// - parameter toFormat: An `AudioStreamBasicDescription` indicating the local format in which the fromFormat will be converted to.
    func createAudioConverter(from fromFormat: AudioStreamBasicDescription, to toFormat: AudioStreamBasicDescription) {
        var inputFormat = fromFormat
        if let converter = audioConverter {
            if memcmp(&inputFormat, &self.inputFormat, MemoryLayout<AudioStreamBasicDescription>.size) == 0 {
                AudioConverterReset(converter)
                return
            }
        }
        disposeAudioConverter()

        var classDesc = AudioClassDescription()
        var outputFormat = toFormat
        if getHardwareCodecClassDescription(formatId: inputFormat.mFormatID, classDesc: &classDesc) {
            AudioConverterNewSpecific(&inputFormat, &outputFormat, 1, &classDesc, &audioConverter)
        }

        if audioConverter == nil {
            let audioConverterStatus = AudioConverterNew(&inputFormat, &outputFormat, &audioConverter)
            guard audioConverterStatus == noErr else {
                let audioConverterError = AudioConverterError(osstatus: audioConverterStatus)
                fileStreamCallback?(.raiseError(.audioSystemError(.converterError(audioConverterError))))
                return
            }
        }
        self.inputFormat = inputFormat
        assignMagicCookieToConverterIfNeeded()
    }

    private func assignMagicCookieToConverterIfNeeded() {
        // magic cookie info
        if let fileStream = audioFileStream {
            var cookieSize: UInt32 = 0
            guard AudioFileStreamGetPropertyInfo(fileStream, kAudioFileStreamProperty_MagicCookieData, &cookieSize, nil) == noErr else {
                return
            }
            var cookie: [UInt8] = Array(repeating: 0, count: Int(cookieSize))
            guard AudioFileStreamGetProperty(fileStream, kAudioFileStreamProperty_MagicCookieData, &cookieSize, &cookie) == noErr else {
                return
            }
            guard let converter = audioConverter else {
                fileStreamCallback?(.raiseError(.audioSystemError(.fileStreamError(.unknownError))))
                return
            }
            guard AudioConverterSetProperty(converter, kAudioConverterDecompressionMagicCookie, cookieSize, cookie) == noErr else {
                fileStreamCallback?(.raiseError(.audioSystemError(.fileStreamError(.unknownError))))
                return
            }
        }
    }

    /// Disposes the `AudioConverter` instance, if any.
    private func disposeAudioConverter() {
        guard let converter = audioConverter else { return }
        AudioConverterDispose(converter)
        audioConverter = nil
    }

    /// Parses any relevant properties as received by the opened `AudioFileStream`
    ///
    /// - parameter fileStream: An instance of `AudioFileStreamID` that is used to get information from.
    /// - parameter propertyId: A value of `AudioFileStreamPropertyID` indicating the file stream property.
    /// - parameter flags: A value of `UnsafeMutablePointer<AudioFileStreamPropertyFlags>`

    func propertyListenerProc(fileStream: AudioFileStreamID,
                              propertyId: AudioFileStreamPropertyID,
                              flags _: UnsafeMutablePointer<AudioFileStreamPropertyFlags>)
    {
        guard let entry = playerContext.audioReadingEntry else { return }
        switch propertyId {
        case kAudioFileStreamProperty_DataOffset:
            processDataOffset(entry: entry, fileStream: fileStream)
        case kAudioFileStreamProperty_FileFormat:
            processFileFormat(fileStream: fileStream)
        case kAudioFileStreamProperty_DataFormat:
            processDataFormat(entry: entry, fileStream: fileStream)
        case kAudioFileStreamProperty_AudioDataByteCount:
            processDataByteCount(entry: entry, fileStream: fileStream)
        case kAudioFileStreamProperty_AudioDataPacketCount:
            processAudioDataPacketCount(entry: entry, fileStream: fileStream)
        case kAudioFileStreamProperty_BitRate:
            processBitRate(entry: entry, fileStream: fileStream)
        case kAudioFileStreamProperty_ReadyToProducePackets:
            // check converter for discontinuous stream
            assignMagicCookieToConverterIfNeeded()
            processPacketUpperBoundAndMaxPacketSize(entry: entry, fileStream: fileStream)
            processReadyToProducePackets(entry: entry, fileStream: fileStream)
        case kAudioFileStreamProperty_FormatList:
            processFormatList(entry: entry, fileStream: fileStream)
        case kAudioFileStreamProperty_PacketTableInfo:
            processPacketTableInfo(entry: entry, fileStream: fileStream)
        default:
            break
        }
    }

    // MARK: AudioFileStream properties Processing

    private func processDataOffset(entry: AudioEntry, fileStream: AudioFileStreamID) {
        var offset: UInt64 = 0
        fileStreamGetProperty(value: &offset, fileStream: fileStream, propertyId: kAudioFileStreamProperty_DataOffset)
        entry.lock.lock(); defer { entry.lock.unlock() }
        entry.audioStreamState.processedDataFormat = true
        entry.audioStreamState.dataOffset = offset
    }

    private func processReadyToProducePackets(entry: AudioEntry, fileStream: AudioFileStreamID) {
        var packetCount: UInt64 = 0
        var packetCountSize = UInt32(MemoryLayout.size(ofValue: packetCount))
        AudioFileStreamGetProperty(fileStream, kAudioFileStreamProperty_AudioDataPacketCount, &packetCountSize, &packetCount)
        entry.lock.lock(); defer { entry.lock.unlock() }
        entry.audioStreamState.dataPacketCount = Double(packetCount)
        let entryFormatID = entry.audioStreamFormat.mFormatID
        let isFLAC = entryFormatID == kAudioFormatFLAC
        if entryFormatID != kAudioFormatLinearPCM && !isFLAC {
            discontinuous = true
        }
    }

    private func processFileFormat(fileStream: AudioFileStreamID) {
        var fileFormat: [UInt8] = Array(repeating: 0, count: 4)
        var size = UInt32(4)
        AudioFileStreamGetProperty(fileStream, kAudioFileStreamProperty_FileFormat, &size, &fileFormat)
        if let stringFileFormat = String(data: Data(fileFormat), encoding: .utf8) {
            currentFileFormat = stringFileFormat
        }
    }

    private func processDataFormat(entry: AudioEntry, fileStream: AudioFileStreamID) {
        var audioStreamFormat = AudioStreamBasicDescription()
        entry.lock.lock(); defer { entry.lock.unlock() }
        if !entry.audioStreamState.processedDataFormat {
            fileStreamGetProperty(value: &audioStreamFormat, fileStream: fileStream, propertyId: kAudioFileStreamProperty_DataFormat)

            if entry.audioStreamFormat.mFormatID == 0 {
                entry.audioStreamFormat = audioStreamFormat
            }

            entry.sampleRate = Float(audioStreamFormat.mSampleRate)
            entry.packetDuration = Double(audioStreamFormat.mFramesPerPacket) / Double(entry.sampleRate)

            var packetBufferSize: UInt32 = 0
            var status = fileStreamGetProperty(value: &packetBufferSize,
                                               fileStream: fileStream,
                                               propertyId: kAudioFileStreamProperty_PacketSizeUpperBound)
            if status != 0 || packetBufferSize == 0 {
                status = fileStreamGetProperty(value: &packetBufferSize,
                                               fileStream: fileStream,
                                               propertyId: kAudioFileStreamProperty_MaximumPacketSize)
                if status != 0 || packetBufferSize == 0 {
                    packetBufferSize = 2048 // default value
                }
            }

            entry.processedPacketsState.bufferSize = packetBufferSize

            if !fileFormatsForDelayedConverterCreation.contains(currentFileFormat) {
                createAudioConverter(from: entry.audioStreamFormat, to: outputAudioFormat)
            }
        }
    }

    private func processPacketUpperBoundAndMaxPacketSize(entry: AudioEntry, fileStream: AudioFileStreamID) {
        var packetBufferSize: UInt32 = 0
        var status = fileStreamGetProperty(value: &packetBufferSize,
                                           fileStream: fileStream,
                                           propertyId: kAudioFileStreamProperty_PacketSizeUpperBound)
        if status != 0 || packetBufferSize == 0 {
            status = fileStreamGetProperty(value: &packetBufferSize,
                                           fileStream: fileStream,
                                           propertyId: kAudioFileStreamProperty_MaximumPacketSize)
            if status != 0 || packetBufferSize == 0 {
                packetBufferSize = 2048 // default value
            }
        }
        entry.lock.withLock {
            entry.processedPacketsState.bufferSize = packetBufferSize
        }
    }

    private func processDataByteCount(entry: AudioEntry, fileStream: AudioFileStreamID) {
        var audioDataByteCount: UInt64 = 0
        fileStreamGetProperty(value: &audioDataByteCount, fileStream: fileStream, propertyId: kAudioFileStreamProperty_AudioDataByteCount)
        entry.lock.lock(); defer { entry.lock.unlock() }
        entry.audioStreamState.dataByteCount = audioDataByteCount
    }

    private func processAudioDataPacketCount(entry: AudioEntry, fileStream: AudioFileStreamID) {
        var audioDataPacketCount: UInt64 = 0
        fileStreamGetProperty(value: &audioDataPacketCount, fileStream: fileStream, propertyId: kAudioFileStreamProperty_AudioDataPacketCount)
        entry.lock.lock(); defer { entry.lock.unlock() }
        entry.audioStreamState.dataPacketOffset = audioDataPacketCount
    }

    private func processBitRate(entry: AudioEntry, fileStream: AudioFileStreamID) {
        var bitRate: UInt32 = 0
        let status = fileStreamGetProperty(value: &bitRate, fileStream: fileStream, propertyId: kAudioFileStreamProperty_BitRate)
        guard status == noErr else { return }
        entry.lock.lock(); defer { entry.lock.unlock() }
        entry.audioStreamState.bitRate = Double(bitRate)
    }

    private func processPacketTableInfo(entry: AudioEntry, fileStream: AudioFileStreamID) {
        var pti = AudioFilePacketTableInfo(mNumberValidFrames: 0,
                                           mPrimingFrames: 0,
                                           mRemainderFrames: 0)
        let status = fileStreamGetProperty(value: &pti, fileStream: fileStream, propertyId: kAudioFileStreamProperty_PacketTableInfo)
        guard status == noErr else { return }
        // Use valid frames to refine duration if present
        entry.lock.lock(); defer { entry.lock.unlock() }
        if pti.mNumberValidFrames > 0 {
            entry.audioStreamState.dataPacketCount = Double(pti.mNumberValidFrames) / Double(max(1, entry.audioStreamFormat.mFramesPerPacket))
        }
    }

    private func processFormatList(entry: AudioEntry, fileStream: AudioFileStreamID) {
        let info = fileStreamGetPropertyInfo(fileStream: fileStream, propertyId: kAudioFileStreamProperty_FormatList)
        guard info.status == noErr, info.size > 0 else { return }

        let itemStride = MemoryLayout<AudioFormatListItem>.stride
        let itemCount = Int(info.size) / itemStride
        guard itemCount > 0 else { return }

        var list = [AudioFormatListItem](repeating: AudioFormatListItem(), count: itemCount)
        var size = UInt32(itemCount * itemStride)
        AudioFileStreamGetProperty(fileStream, kAudioFileStreamProperty_FormatList, &size, &list)

        var chosenASBD: AudioStreamBasicDescription?
        for i in 0..<itemCount {
            let asbd = list[i].mASBD
            let formatId = asbd.mFormatID
            if formatId == kAudioFormatMPEG4AAC_HE || formatId == kAudioFormatMPEG4AAC_HE_V2 {
                chosenASBD = asbd
                break
            }
            if chosenASBD == nil {
                chosenASBD = asbd
            }
        }

        if let asbd = chosenASBD {
            entry.lock.withLock { entry.audioStreamFormat = asbd }
            if fileFormatsForDelayedConverterCreation.contains(currentFileFormat) {
                createAudioConverter(from: asbd, to: outputAudioFormat)
            }
        }
    }

    // MARK: Packets Proc

    func propertyPacketsProc(
        inNumberBytes: UInt32,
        inNumberPackets: UInt32,
        inInputData: UnsafeRawPointer,
        inPacketDescriptions: UnsafeMutablePointer<AudioStreamPacketDescription>?
    ) {
        guard let entry = playerContext.audioReadingEntry else { return }
        guard entry.audioStreamState.processedDataFormat else { return }

        guard let converter = audioConverter else {
            Logger.error("Couldn't find audio converter", category: .audioRendering)
            return
        }

        if let playingEntry = playerContext.audioPlayingEntry,
           playingEntry.seekRequest.requested, playingEntry.calculatedBitrate() > 0
        {
            fileStreamCallback?(.processSource)
            if rendererContext.waiting.value {
                rendererContext.packetsSemaphore.signal()
            }
            return
        }

        // reset discontinuity
        discontinuous = false

        var convertInfo = AudioConvertInfo(
            done: false,
            numberOfPackets: inNumberPackets,
            packDescription: inPacketDescriptions
        )
        convertInfo.audioBuffer.mData = UnsafeMutableRawPointer(mutating: inInputData)
        convertInfo.audioBuffer.mDataByteSize = inNumberBytes
        if let playingAudioStreamFormat = playerContext.audioPlayingEntry?.audioStreamFormat {
            convertInfo.audioBuffer.mNumberChannels = playingAudioStreamFormat.mChannelsPerFrame
        }

        updateProcessedPackets(
            inPacketDescriptions: inPacketDescriptions,
            inNumberPackets: inNumberPackets
        )

        var status: OSStatus = noErr
        packetProcess: while status == noErr {
            rendererContext.lock.lock()
            let bufferContext = rendererContext.bufferContext
            var used = bufferContext.frameUsedCount
            var start = bufferContext.frameStartIndex
            var end = (bufferContext.frameStartIndex + bufferContext.frameUsedCount) % bufferContext.totalFrameCount

            var framesLeftInBuffer = bufferContext.totalFrameCount - used
            rendererContext.lock.unlock()

            if framesLeftInBuffer == 0 {
                while true {
                    rendererContext.lock.lock()
                    let bufferContext = rendererContext.bufferContext
                    used = bufferContext.frameUsedCount
                    start = bufferContext.frameStartIndex
                    end = (bufferContext.frameStartIndex + bufferContext.frameUsedCount) % bufferContext.totalFrameCount
                    framesLeftInBuffer = bufferContext.totalFrameCount - used
                    rendererContext.lock.unlock()
                    if framesLeftInBuffer > 0 {
                        break
                    }
                    if playerContext.internalState == .disposed
                        || playerContext.internalState == .pendingNext
                        || playerContext.internalState == .stopped
                    {
                        return
                    }

                    if let playingEntry = playerContext.audioPlayingEntry,
                       playingEntry.seekRequest.requested, playingEntry.calculatedBitrate() > 0
                    {
                        fileStreamCallback?(.processSource)
                        if rendererContext.waiting.value {
                            rendererContext.packetsSemaphore.signal()
                        }
                        return
                    }

                    rendererContext.waiting.write { $0 = true }
                    rendererContext.packetsSemaphore.wait()
                    rendererContext.waiting.write { $0 = false }
                }
            }

            let localBufferList = AudioBufferList.allocate(maximumBuffers: 1)
            defer { localBufferList.unsafeMutablePointer.deallocate() }

            if end >= start {
                var framesAdded: UInt32 = 0
                var framesToDecode: UInt32 = rendererContext.bufferContext.totalFrameCount - end

                let offset = Int(end * rendererContext.bufferContext.sizeInBytes)
                prefillLocalBufferList(
                    bufferList: localBufferList,
                    dataOffset: offset,
                    framesToDecode: framesToDecode
                )

                status = AudioConverterFillComplexBuffer(
                    converter,
                    _converterCallback,
                    &convertInfo,
                    &framesToDecode,
                    localBufferList.unsafeMutablePointer,
                    nil
                )

                framesAdded = framesToDecode

                if status == AudioConvertStatus.done.rawValue {
                    fillUsedFrames(framesCount: framesAdded)
                    return
                } else if status != 0 {
                    fileStreamCallback?(.raiseError(.codecError))
                    return
                }

                framesToDecode = start
                if framesToDecode == 0 {
                    fillUsedFrames(framesCount: framesAdded)
                    continue packetProcess
                }
                prefillLocalBufferList(
                    bufferList: localBufferList,
                    dataOffset: 0,
                    framesToDecode: framesToDecode
                )

                status = AudioConverterFillComplexBuffer(
                    converter,
                    _converterCallback,
                    &convertInfo,
                    &framesToDecode,
                    localBufferList.unsafeMutablePointer,
                    nil
                )

                framesAdded += framesToDecode

                if status == AudioConvertStatus.done.rawValue {
                    fillUsedFrames(framesCount: framesAdded)
                    return
                } else if status == AudioConvertStatus.processed.rawValue {
                    fillUsedFrames(framesCount: framesAdded)
                    continue packetProcess
                } else if status != 0 {
                    fileStreamCallback?(.raiseError(.codecError))
                    return
                }
            } else {
                var framesAdded: UInt32 = 0
                var framesToDecode: UInt32 = start - end

                let offset = Int(end * rendererContext.bufferContext.sizeInBytes)
                prefillLocalBufferList(
                    bufferList: localBufferList,
                    dataOffset: offset,
                    framesToDecode: framesToDecode
                )

                status = AudioConverterFillComplexBuffer(
                    converter,
                    _converterCallback,
                    &convertInfo,
                    &framesToDecode,
                    localBufferList.unsafeMutablePointer,
                    nil
                )

                framesAdded = framesToDecode
                if status == AudioConvertStatus.done.rawValue {
                    fillUsedFrames(framesCount: framesAdded)
                    return
                } else if status == AudioConvertStatus.processed.rawValue {
                    fillUsedFrames(framesCount: framesAdded)
                    continue packetProcess
                } else if status != 0 {
                    fileStreamCallback?(.raiseError(.codecError))
                    return
                }
            }
        }
    }

    /// Fills the `AudioBuffer` with data as required
    ///
    /// - parameter list: An `UnsafeMutableAudioBufferListPointer` object representing the buffer list be filled with data
    /// - parameter dataOffset: An `Int` value indicating any offset to be applied to the buffer data
    /// - parameter framesToDecode: An `UInt32` value indicating the frames to be decoded, used in calculating the data size of the buffer.
    @inline(__always)
    private func prefillLocalBufferList(
        bufferList: UnsafeMutableAudioBufferListPointer,
        dataOffset: Int,
        framesToDecode: UInt32
    ) {
        if let mData = rendererContext.audioBuffer.mData {
            bufferList[0].mData = dataOffset > 0 ? mData + dataOffset : mData
        }
        bufferList[0].mDataByteSize = framesToDecode * rendererContext.bufferContext.sizeInBytes
        bufferList[0].mNumberChannels = rendererContext.audioBuffer.mNumberChannels
    }

    /// Advances the processed frames for buffer and reading entry
    ///
    /// - parameter frameCount: An `UInt32` value to be added to the used count of the buffers.
    @inline(__always)
    private func fillUsedFrames(framesCount: UInt32) {
        rendererContext.lock.lock()
        let writeIndex = (rendererContext.bufferContext.frameStartIndex +
            rendererContext.bufferContext.frameUsedCount) % rendererContext.bufferContext.totalFrameCount
        let generation = rendererContext.bufferGeneration
        rendererContext.bufferContext.frameUsedCount += framesCount
        rendererContext.lock.unlock()

        guard let readingEntry = playerContext.audioReadingEntry else { return }
        readingEntry.lock.lock()
        if readingEntry.framesState.queued == 0 {
            readingEntry.firstFrameRingIndex = writeIndex
            readingEntry.firstFrameBufferGeneration = generation
        }
        readingEntry.framesState.queued += Int(framesCount)
        readingEntry.lock.unlock()
    }

    @inline(__always)
    private func updateProcessedPackets(
        inPacketDescriptions: UnsafeMutablePointer<AudioStreamPacketDescription>?,
        inNumberPackets: UInt32
    ) {
        guard let inPacketDescriptions = inPacketDescriptions else { return }
        guard let readingEntry = playerContext.audioReadingEntry else { return }
        let processedPackCount = readingEntry.processedPacketsState.count
        if processedPackCount < maxCompressedPacketForBitrate {
            let count = min(Int(inNumberPackets), maxCompressedPacketForBitrate - Int(processedPackCount))
            for i in 0 ..< count {
                let packet = inPacketDescriptions[i]
                let packetSize: UInt32 = packet.mDataByteSize
                readingEntry.lock.lock()
                readingEntry.processedPacketsState.sizeTotal += packetSize
                readingEntry.processedPacketsState.count += 1
                readingEntry.lock.unlock()
            }
        }
    }
}

// MARK: - AudioFileStream proc method

private func _propertyListenerProc(
    clientData: UnsafeMutableRawPointer,
    fileStream: AudioFileStreamID,
    propertyId: AudioFileStreamPropertyID,
    flags: UnsafeMutablePointer<AudioFileStreamPropertyFlags>
) {
    let processor = clientData.to(type: AudioFileStreamProcessor.self)
    processor.propertyListenerProc(fileStream: fileStream,
                                   propertyId: propertyId,
                                   flags: flags)
}

private func _propertyPacketsProc(
    clientData: UnsafeMutableRawPointer,
    inNumberBytes: UInt32,
    inNumberPackets: UInt32,
    inInputData: UnsafeRawPointer,
    inPacketDescriptions: UnsafeMutablePointer<AudioStreamPacketDescription>?
) {
    let processor = clientData.to(type: AudioFileStreamProcessor.self)
    processor.propertyPacketsProc(inNumberBytes: inNumberBytes,
                                  inNumberPackets: inNumberPackets,
                                  inInputData: inInputData,
                                  inPacketDescriptions: inPacketDescriptions)
}

// MARK: - AudioConverterFillComplexBuffer callback method

private func _converterCallback(
    inAudioConverter _: AudioConverterRef,
    ioNumberDataPackets: UnsafeMutablePointer<UInt32>,
    ioData: UnsafeMutablePointer<AudioBufferList>,
    outDataPacketDescription: UnsafeMutablePointer<UnsafeMutablePointer<AudioStreamPacketDescription>?>?,
    inUserData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let convertInfo = inUserData?.assumingMemoryBound(to: AudioConvertInfo.self) else { return 0 }

    // we need to tell the converter to stop converting after it should stop converting
    if convertInfo.pointee.done {
        ioNumberDataPackets.pointee = 0
        return AudioConvertStatus.done.rawValue
    }
    // calculate the input buffer
    ioData.pointee.mNumberBuffers = 1
    ioData.pointee.mBuffers = convertInfo.pointee.audioBuffer

    // output the packet descriptions
    if outDataPacketDescription != nil {
        outDataPacketDescription?.pointee = convertInfo.pointee.packDescription
    }

    ioNumberDataPackets.pointee = convertInfo.pointee.numberOfPackets
    convertInfo.pointee.done = true

    return AudioConvertStatus.processed.rawValue
}

// MARK: HardwareCodedClass method

private func getHardwareCodecClassDescription(formatId: UInt32, classDesc: UnsafeMutablePointer<AudioClassDescription>) -> Bool {
    #if os(iOS)
        var size: UInt32 = 0
        let formatIdSize = UInt32(MemoryLayout.size(ofValue: formatId))
        var id = formatId
        if AudioFormatGetPropertyInfo(kAudioFormatProperty_Decoders, formatIdSize, &id, &size) != noErr {
            return false
        }
        let count = Int(size) / MemoryLayout<AudioClassDescription>.size
        var encoderDescriptions = Array(repeating: AudioClassDescription(), count: count)
        if AudioFormatGetProperty(kAudioFormatProperty_Decoders, formatIdSize, &id, &size, &encoderDescriptions) != noErr {
            return false
        }

        for item in encoderDescriptions where item.mManufacturer == kAppleHardwareAudioCodecManufacturer {
            classDesc.pointee = item
            return true
        }
    #endif
    return false
}
