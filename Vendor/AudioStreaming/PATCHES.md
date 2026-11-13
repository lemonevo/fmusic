# Local patches to AudioStreaming

Source: https://github.com/dimitris-c/AudioStreaming, tag `1.4.4`
(revision `a729ee28fece29d80a749419d96df0693200f124`), MIT.

Only `AudioCodecs/` and `AudioStreaming/` are vendored; the sample app and tests are not.
`Package.swift` is trimmed to the two library targets.

## FLAC seek position (`AudioFileStreamProcessor.swift`)

The upstream seek converts the requested time to a byte offset with the file's average
bitrate (`AudioFileStreamSeek` flags the offset as estimated for VBR streams) and then
reports the requested time as the playback position (`AudioEntry.progress` returns
`seekRequest.time` while the seek is pending). For VBR FLAC the byte estimate can be
several seconds off: on a 23 MB test file a seek to 193.8 s started decoding at 186.6 s
while the clock said 193.8 s, so lyrics scrolled ~7 s ahead of the audio.

The patch parses the first FLAC frame header that arrives after a seek (RFC 9639 §9.1,
CRC-8 validated) and:

1. sets `seekTime` to the frame's real sample position, so the reported time matches the
   audio that is actually decoded;
2. if the landing is more than 0.25 s away from the request, re-requests data at a
   corrected byte offset (local bytes/second from two frames, global average as fallback)
   up to two times. The test file converges to <0.1 s.

Ogg Vorbis and the other decoders are untouched. `closeFileStreamIfNeeded()` clears the
pending correction.

## Seek requested while paused (`AudioPlayer.swift`)

`seek(to:)` only records `seekRequest`, and `processSource()` returns immediately while
the player is `.paused`, so a seek made during a pause is never applied.
`resume()` used to restart the engine and the source without looking at the request:
the position stayed at `seekRequest.time` forever, or the already read-ahead entry ran
out and the app replayed the track from the start.

`resume()` now checks `audioPlayingEntry.seekRequest.requested`. When a seek is pending
it does not start the player hardware directly, but runs `processSource()` on the source
queue after the engine/source are resumed: with `readingEntry === playingEntry` this
applies the seek in place, otherwise `processSource` rebuilds the reading entry and the
seek is applied when the first packets of the new stream arrive. Playback starts
afterwards, guarded by the new `isPlayerHardwareRunning` flag (set in `startPlayer`,
cleared in `pauseEngine`/`stopEngine`) so the paths that already started the player are
not started twice.

## When updating the vendored copy

Re-apply these patches and bump the revision above. Keep the dependency pointing at
`Vendor/AudioStreaming` (`XCLocalSwiftPackageReference` in `fmusic.xcodeproj`).
