import Foundation
import CryptoKit

actor TransferEngine {
    typealias Reporter = @Sendable (TransferUpdate) async -> Void
    private let fm = FileManager.default
    private let extensions: [String: MediaKind] = ["jpg": .photo, "jpeg": .photo, "mp4": .video]

    func scan(volumes: [URL]) -> [MediaFile] {
        var result: [MediaFile] = []
        let keys: [URLResourceKey] = [.isRegularFileKey, .contentModificationDateKey, .creationDateKey]
        for volume in volumes {
            let dcim = volume.appendingPathComponent("DCIM", isDirectory: true)
            guard let enumerator = fm.enumerator(at: dcim, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles]) else { continue }
            for case let url as URL in enumerator {
                guard let kind = extensions[url.pathExtension.lowercased()],
                      (try? url.resourceValues(forKeys: Set(keys)).isRegularFile) == true else { continue }
                result.append(MediaFile(source: url, kind: kind, capturedAt: captureDate(for: url)))
            }
        }
        return result.sorted { $0.source.path < $1.source.path }
    }

    func transfer(
        volumes: [URL],
        destination: URL,
        removeVerifiedDuplicates: Bool,
        report: Reporter
    ) async {
        var update = TransferUpdate(stage: .scanning)
        await report(update)
        let files = scan(volumes: volumes)
        update.found = files.count
        await report(update)
        guard !files.isEmpty else {
            update.stage = .complete; update.message = "No new media found."; await report(update); return
        }
        do {
            try ensureWritable(destination)
            for file in files {
                do {
                    update.stage = .copying; update.currentFile = file.source.lastPathComponent; update.bytesPerSecond = 0; await report(update)
                    let target = try targetURL(for: file, root: destination)
                    let finalURL: URL
                    let existingDuplicate = try existingDuplicate(of: file.source, startingAt: target)
                    if let existingDuplicate {
                        finalURL = existingDuplicate
                    } else {
                        finalURL = try unusedURL(startingAt: target)
                        let temporary = partialURL(for: finalURL)
                        let copyStartedAt = Date()
                        var copiedBytes = 0
                        try await resumableCopy(from: file.source, to: temporary) { byteCount in
                            copiedBytes += byteCount
                            let elapsed = max(Date().timeIntervalSince(copyStartedAt), 0.001)
                            update.bytesPerSecond = Double(copiedBytes) / elapsed
                            await report(update)
                        }
                        update.stage = .verifying; update.bytesPerSecond = 0; await report(update)
                        guard try filesEqual(file.source, temporary) else {
                            throw TransferError.verificationFailed(file.source.lastPathComponent)
                        }
                        try fm.moveItem(at: temporary, to: finalURL)
                    }
                    guard try filesEqual(file.source, finalURL) else { throw TransferError.sourceChanged(file.source.lastPathComponent) }
                    update.copied += 1; await report(update)

                    if existingDuplicate != nil, !removeVerifiedDuplicates {
                        update.duplicatesRetained += 1
                        await report(update)
                        continue
                    }

                    // Per-file commit: once this exact source is verified at the
                    // destination, remove it immediately so restarts only scan
                    // unfinished work. Matching DJI proxy/auxiliary files follow it.
                    update.stage = .deleting; update.currentFile = file.source.lastPathComponent; await report(update)
                    try fm.removeItem(at: file.source)
                    update.deleted += 1; await report(update)
                    for companion in companionFiles(for: file.source) where fm.fileExists(atPath: companion.path) {
                        try fm.removeItem(at: companion)
                    }
                } catch {
                    update.bytesPerSecond = 0
                    update.copyErrors.append("\(file.source.lastPathComponent): \(error.localizedDescription)")
                    await report(update)
                }
            }

            // Remove stale LRF/AIS files whose corresponding media was already
            // committed by an earlier run. Never remove a companion for media
            // that is still present and may need retrying.
            for auxiliary in orphanedAuxiliaryFiles(on: volumes) {
                do {
                    try fm.removeItem(at: auxiliary)
                } catch {
                    // Auxiliary cleanup is intentionally silent in the UI; it
                    // must not affect media copy/deletion counts or errors.
                }
            }

            guard update.copyErrors.isEmpty else {
                update.stage = .failed
                update.currentFile = ""
                update.message = "Finished with \(update.copyErrors.count) error(s). Verified files were committed; failed files remain for retry."
                await report(update)
                return
            }
            update.stage = .complete
            update.currentFile = ""
            update.bytesPerSecond = 0
            update.message = update.duplicatesRetained > 0
                ? "Import finished. \(update.duplicatesRetained) verified duplicate(s) were retained on the source."
                : "Import finished and verified originals were removed."
            await report(update)
        } catch {
            update.stage = .failed; update.message = error.localizedDescription; await report(update)
        }
    }

    private func companionFiles(for media: URL) -> [URL] {
        let base = media.deletingPathExtension()
        return ["LRF", "AIS", "lrf", "ais"].map { base.appendingPathExtension($0) }
    }

    private func orphanedAuxiliaryFiles(on volumes: [URL]) -> [URL] {
        var result: [URL] = []
        for volume in volumes {
            let dcim = volume.appendingPathComponent("DCIM", isDirectory: true)
            guard let enumerator = fm.enumerator(at: dcim, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) else { continue }
            for case let url as URL in enumerator {
                let ext = url.pathExtension.lowercased()
                if (ext == "lrf" || ext == "ais"),
                   (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true {
                    let base = url.deletingPathExtension()
                    let hasMedia = ["MP4", "mp4", "JPG", "jpg", "JPEG", "jpeg"].contains {
                        fm.fileExists(atPath: base.appendingPathExtension($0).path)
                    }
                    if !hasMedia { result.append(url) }
                }
            }
        }
        return result
    }

    private func captureDate(for url: URL) -> Date {
        let name = url.lastPathComponent
        if let range = name.range(of: #"\d{14}"#, options: .regularExpression) {
            let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.dateFormat = "yyyyMMddHHmmss"
            if let date = formatter.date(from: String(name[range])) { return date }
        }
        let values = try? url.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey])
        return values?.creationDate ?? values?.contentModificationDate ?? Date()
    }

    private func targetURL(for file: MediaFile, root: URL) throws -> URL {
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.dateFormat = "yyyy-MM-dd"
        let folder = root.appendingPathComponent(file.kind.rawValue, isDirectory: true).appendingPathComponent(formatter.string(from: file.capturedAt), isDirectory: true)
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent(file.source.lastPathComponent)
    }

    private func unusedURL(startingAt url: URL) throws -> URL {
        guard fm.fileExists(atPath: url.path) else { return url }
        let base = url.deletingPathExtension().lastPathComponent, ext = url.pathExtension, folder = url.deletingLastPathComponent()
        for index in 1...9999 {
            let candidate = folder.appendingPathComponent("\(base)-\(index).\(ext)")
            if !fm.fileExists(atPath: candidate.path) { return candidate }
        }
        throw CocoaError(.fileWriteFileExists)
    }

    private func existingDuplicate(of source: URL, startingAt target: URL) throws -> URL? {
        let folder = target.deletingLastPathComponent()
        let base = target.deletingPathExtension().lastPathComponent
        let ext = target.pathExtension.lowercased()
        let candidates = try fm.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ).filter { candidate in
            guard (try? candidate.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else { return false }
            guard candidate.pathExtension.lowercased() == ext else { return false }
            let candidateBase = candidate.deletingPathExtension().lastPathComponent
            guard candidateBase == base || candidateBase.hasPrefix("\(base)-") else { return false }
            let suffix = candidateBase.dropFirst(base.count + 1)
            return candidateBase == base || (!suffix.isEmpty && suffix.allSatisfy(\.isNumber))
        }.sorted { $0.lastPathComponent < $1.lastPathComponent }

        for candidate in candidates where try filesEqual(source, candidate) {
            return candidate
        }
        return nil
    }

    private func partialURL(for finalURL: URL) -> URL {
        finalURL.deletingLastPathComponent()
            .appendingPathComponent(".\(finalURL.lastPathComponent).dji-partial")
    }

    /// Continues a previous partial copy only when its complete byte prefix still
    /// matches the source. A mismatched or oversized partial is safely replaced.
    private func resumableCopy(from source: URL, to partial: URL, progress: (Int) async -> Void) async throws {
        let sourceSize = try source.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        var offset = 0
        if fm.fileExists(atPath: partial.path) {
            let partialSize = try partial.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            let prefixMatches = partialSize <= sourceSize
                ? try prefixesEqual(source, partial, byteCount: partialSize)
                : false
            if prefixMatches {
                offset = partialSize
            } else {
                try fm.removeItem(at: partial)
            }
        }
        if !fm.fileExists(atPath: partial.path) {
            guard fm.createFile(atPath: partial.path, contents: nil) else {
                throw CocoaError(.fileWriteUnknown)
            }
        }

        let input = try FileHandle(forReadingFrom: source)
        let output = try FileHandle(forWritingTo: partial)
        defer { try? input.close(); try? output.close() }
        try input.seek(toOffset: UInt64(offset))
        try output.seekToEnd()
        while true {
            let data = try input.read(upToCount: 4 * 1024 * 1024) ?? Data()
            if data.isEmpty { break }
            try output.write(contentsOf: data)
            await progress(data.count)
        }
        try output.synchronize()
    }

    private func prefixesEqual(_ source: URL, _ partial: URL, byteCount: Int) throws -> Bool {
        guard byteCount > 0 else { return true }
        let sourceHandle = try FileHandle(forReadingFrom: source)
        let partialHandle = try FileHandle(forReadingFrom: partial)
        defer { try? sourceHandle.close(); try? partialHandle.close() }
        var remaining = byteCount
        while remaining > 0 {
            let count = min(4 * 1024 * 1024, remaining)
            let sourceData = try sourceHandle.read(upToCount: count) ?? Data()
            let partialData = try partialHandle.read(upToCount: count) ?? Data()
            guard sourceData == partialData, sourceData.count == count else { return false }
            remaining -= count
        }
        return true
    }

    private func ensureWritable(_ url: URL) throws {
        var isDirectory: ObjCBool = false
        guard fm.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw TransferError.destinationUnavailable
        }
        let probe = url.appendingPathComponent(".dji-media-mover-write-test-\(UUID().uuidString)")
        guard fm.createFile(atPath: probe.path, contents: Data()) else { throw TransferError.destinationUnavailable }
        try fm.removeItem(at: probe)
    }

    private func filesEqual(_ lhs: URL, _ rhs: URL) throws -> Bool {
        let left = try lhs.resourceValues(forKeys: [.fileSizeKey]).fileSize
        let right = try rhs.resourceValues(forKeys: [.fileSizeKey]).fileSize
        guard left == right else { return false }
        return try digest(lhs) == digest(rhs)
    }

    private func digest(_ url: URL) throws -> SHA256.Digest {
        let handle = try FileHandle(forReadingFrom: url); defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            let data = try handle.read(upToCount: 4 * 1024 * 1024) ?? Data()
            if data.isEmpty { break }
            hasher.update(data: data)
        }
        return hasher.finalize()
    }
}
