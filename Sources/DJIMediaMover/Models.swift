import Foundation

enum MediaKind: String, Sendable { case photo = "Photos", video = "Videos" }

struct MediaFile: Identifiable, Sendable {
    let source: URL
    let kind: MediaKind
    let capturedAt: Date
    var id: String { source.path }
}

enum TransferStage: String, Sendable {
    case idle = "Waiting for a DJI drone"
    case scanning = "Scanning media"
    case copying = "Copying"
    case verifying = "Verifying"
    case deleting = "Deleting verified originals"
    case complete = "Complete"
    case failed = "Stopped safely"
}

struct TransferUpdate: Sendable {
    var stage: TransferStage
    var found = 0
    var copied = 0
    var deleted = 0
    var duplicatesRetained = 0
    var currentFile = ""
    var message = ""
    var copyErrors: [String] = []
    var bytesPerSecond: Double = 0
}

enum TransferError: LocalizedError {
    case destinationUnavailable
    case verificationFailed(String)
    case sourceChanged(String)

    var errorDescription: String? {
        switch self {
        case .destinationUnavailable: "The selected destination no longer exists or is not writable. Choose it again in Settings."
        case .verificationFailed(let name): "Verification failed for \(name). This source file was not deleted."
        case .sourceChanged(let name): "The source changed while copying \(name). This source file was not deleted."
        }
    }
}
