//
//  StreamingArtifactSanitizer.swift
//  MicroCode
//
//  Incremental front-end for `AIStructuredTurnCodec.stripToolCallArtifacts`.
//
//  The agent stream is append-only, but the original sanitizer re-scanned the
//  ENTIRE accumulated answer on every 75 ms flush (six Foundation `contains`
//  scans + regexes): ~15 ms at 128 KB, ~61 ms at 512 KB on the main actor, which
//  makes long answers progressively janky (O(N^2) over the stream).
//
//  Design: fold the already-finished part of the stream into `committedClean`
//  once, and only re-sanitize the short unfinished tail.
//
//  Soundness argument (checked by a differential fuzz test against the original
//  function, see Scripts/perf/): every artifact pattern starts at one of the
//  `openers` below and no pattern looks backwards. The only other rule,
//  "waiting for tool response", is anchored to a line start. So the text up to
//  the start of the LAST line (head) can be folded into the committed prefix
//  whenever it contains no opener at all: nothing in a continuation can then
//  change how `head` is stripped, and `strip(head + Q) == strip(head) + strip(Q)`.
//  Artifact families nest/overlap (e.g. an `<invoke>` pair is matched before a
//  `<parameter>` pair), so heads that contain an opener are deliberately never
//  committed; artifact-bearing text keeps re-sanitizing from its first opener,
//  which is exactly the previous cost, while prose streams become O(tail).
//

import Foundation

struct StreamingArtifactSanitizer {
    /// Every sentinel that can start a pattern in `AIStructuredTurnCodec.stripToolCallArtifacts`
    /// (the gates of its passes). Keep in sync with that function.
    private static let openers = [
        "[Tool Call:", "<tool_call", "<function_call", "<invoke", "<parameter", "DSML",
        "```tool_call", "```function_call"
    ]

    private static func containsOpener(_ text: String) -> Bool {
        // Byte-level prefilter: every opener contains one of '[' '<' 'D' '`'. Most prose lines contain none, which
        // avoids eight Foundation `contains` calls (each bridges the string to NSString).
        var hasLeadByte = false
        for byte in text.utf8 where byte == 0x5B || byte == 0x3C || byte == 0x44 || byte == 0x60 {
            hasLeadByte = true
            break
        }
        guard hasLeadByte else { return false }
        for opener in openers where text.contains(opener) { return true }
        return false
    }

    /// Exactly `AIStructuredTurnCodec.stripToolCallArtifacts(text)`: every pass of that function is gated by an
    /// opener or by the case-insensitive phrase below, so text without either is returned unchanged.
    private static func strip(_ text: String) -> String {
        if !containsOpener(text) && text.range(of: "waiting for tool response", options: .caseInsensitive) == nil {
            return text
        }
        return AIStructuredTurnCodec.stripToolCallArtifacts(text)
    }

    /// Number of bytes of committed raw text used to prove the new input still extends the old one.
    private static let fingerprintLength = 64

    private var committedRawBytes = 0
    private var committedClean = ""
    private var fingerprint: [UInt8] = []

    init() {}

    mutating func reset() {
        committedRawBytes = 0
        committedClean = ""
        fingerprint.removeAll(keepingCapacity: false)
    }

    /// Returns exactly `AIStructuredTurnCodec.stripToolCallArtifacts(raw)` while doing work
    /// proportional to the unfinished tail instead of the whole answer.
    mutating func sanitize(_ raw: String) -> String {
        var raw = raw
        // Native Swift strings are UTF-8, so `utf8.count` is O(1); `String.count` is a grapheme walk.
        let totalBytes = raw.utf8.count

        if committedRawBytes > 0 && !extendsCommittedPrefix(&raw, totalBytes: totalBytes) {
            reset()
        }

        var tail = Self.tail(of: raw, fromByte: committedRawBytes)

        // Try to fold everything before the last line into the committed prefix.
        // A head that contains ANY opener sentinel is never committed: artifact families nest/overlap and the
        // original pass order (e.g. `<invoke>` pair before `<parameter>` pair) depends on closers that may still arrive.
        // Prose never contains them, so the common (and long) case commits continuously; artifact-bearing text simply
        // keeps re-sanitizing from its first artifact, exactly like before.
        if let boundary = Self.lastLineStartOffset(in: tail), boundary > 0 {
            let head = Self.prefix(of: tail, bytes: boundary)
            if !Self.containsOpener(head) {
                committedClean += Self.strip(head)
                committedRawBytes += boundary
                refreshFingerprint(&raw)
                tail = Self.tail(of: tail, fromByte: boundary)
            }
        }

        let cleanedTail = Self.strip(tail)
        return committedClean.isEmpty ? cleanedTail : committedClean + cleanedTail
    }

    // MARK: - Helpers

    private func extendsCommittedPrefix(_ raw: inout String, totalBytes: Int) -> Bool {
        guard totalBytes >= committedRawBytes, !fingerprint.isEmpty else { return false }
        let count = fingerprint.count
        let utf8 = raw.utf8
        let start = utf8.index(utf8.startIndex, offsetBy: committedRawBytes - count)
        let end = utf8.index(utf8.startIndex, offsetBy: committedRawBytes)
        return utf8[start..<end].elementsEqual(fingerprint)
    }

    private mutating func refreshFingerprint(_ raw: inout String) {
        let count = min(Self.fingerprintLength, committedRawBytes)
        let utf8 = raw.utf8
        let start = utf8.index(utf8.startIndex, offsetBy: committedRawBytes - count)
        let end = utf8.index(utf8.startIndex, offsetBy: committedRawBytes)
        fingerprint = Array(utf8[start..<end])
    }

    /// Byte offset right after the last "\n" (i.e. the start of the last, possibly unfinished line).
    private static func lastLineStartOffset(in text: String) -> Int? {
        var offset = text.utf8.count
        for byte in text.utf8.reversed() {
            if byte == 0x0A { return offset }
            offset -= 1
        }
        return nil
    }

    private static func tail(of text: String, fromByte offset: Int) -> String {
        if offset == 0 { return text }
        let utf8 = text.utf8
        guard offset <= utf8.count else { return "" }
        let index = utf8.index(utf8.startIndex, offsetBy: offset)
        return String(text[index...])
    }

    private static func prefix(of text: String, bytes: Int) -> String {
        let utf8 = text.utf8
        let index = utf8.index(utf8.startIndex, offsetBy: min(bytes, utf8.count))
        return String(text[..<index])
    }
}
