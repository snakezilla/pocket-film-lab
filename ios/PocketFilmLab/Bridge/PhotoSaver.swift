import Photos
import UIKit

/// What the page is told about Photos access. Add-only access is enough to save.
enum PhotoAccess: String {
    case authorized, limited, denied, restricted, notDetermined

    var canSave: Bool { self == .authorized || self == .limited }

    init(_ status: PHAuthorizationStatus) {
        switch status {
        case .authorized: self = .authorized
        case .limited: self = .limited
        case .denied: self = .denied
        case .restricted: self = .restricted
        default: self = .notDetermined
        }
    }
}

/// Adds finished files to the Photos library. A protocol so tests can stand in for Photos.
protocol PhotoSaving {
    /// Asks for add-only access if it was never asked; calls back on the main thread.
    func requestAccess(_ done: @escaping (PhotoAccess) -> Void)
    /// Adds the file as a new photo; calls back on the main thread. The file is not
    /// moved or deleted here: the caller removes its temp file afterwards.
    func save(_ file: URL, done: @escaping (Error?) -> Void)
}

/// The real Photos library, add-only access (NSPhotoLibraryAddUsageDescription).
struct SystemPhotoSaver: PhotoSaving {
    enum Failure: Error, LocalizedError {
        case notAllowed
        case failed
        var errorDescription: String? {
            switch self {
            case .notAllowed: return "Silver Hour needs your OK to add photos. Turn it on in Settings."
            case .failed: return "Photos didn’t take that one. Try again."
            }
        }
    }

    func requestAccess(_ done: @escaping (PhotoAccess) -> Void) {
        let current = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        guard current == .notDetermined else { done(PhotoAccess(current)); return }
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            DispatchQueue.main.async { done(PhotoAccess(status)) }
        }
    }

    func save(_ file: URL, done: @escaping (Error?) -> Void) {
        guard PhotoAccess(PHPhotoLibrary.authorizationStatus(for: .addOnly)).canSave else {
            done(Failure.notAllowed)
            return
        }
        PHPhotoLibrary.shared().performChanges({
            let options = PHAssetResourceCreationOptions()
            options.shouldMoveFile = false
            PHAssetCreationRequest.forAsset().addResource(with: .photo, fileURL: file, options: options)
        }, completionHandler: { ok, error in
            DispatchQueue.main.async { done(ok ? nil : (error ?? Failure.failed)) }
        })
    }
}
