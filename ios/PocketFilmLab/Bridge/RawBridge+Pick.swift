import PhotosUI
import UIKit
import UniformTypeIdentifiers

/// Picking: one Photos (or Files) picker, any number of photos, RAW preferred.
extension RawBridge {
    func open(source: String, reply: @escaping (Any?, String?) -> Void) {
        #if DEBUG
        // Screenshots only: `-PFLDebugOpenRaw <path>[,<path>...]` opens those files instead
        // of showing a picker. Compiled out of release builds; the real pickers are not exercised.
        if let paths = UserDefaults.standard.string(forKey: "PFLDebugOpenRaw") {
            let copies = paths.split(separator: ",").compactMap { Self.copyToTemp(URL(fileURLWithPath: String($0))) }
            startBatch(PickResult(urls: copies, skipped: 0, truncated: 0), reply: reply)
            return
        }
        #endif
        guard let presenter else { reply(nil, "No window"); return }
        beginOpen(reply: reply)
        if source == "files" {
            let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.rawImage, .jpeg, .png, .heic, .heif], asCopy: true)
            picker.allowsMultipleSelection = true
            picker.delegate = self
            presenter.present(picker, animated: true)
        } else {
            var config = PHPickerConfiguration()
            config.filter = .images
            config.selectionLimit = 0 // any number
            config.selection = .ordered
            config.preferredAssetRepresentationMode = .current
            let picker = PHPickerViewController(configuration: config)
            picker.delegate = self
            presenter.present(picker, animated: true)
        }
    }

    /// Waits for a picker result. A cancelled picker replies {cancelled: true} and leaves
    /// the current batch open.
    func beginOpen(reply: @escaping (Any?, String?) -> Void) {
        openToken += 1
        pendingOpen = { [weak self] pick in
            guard let self else { return }
            guard let pick else { reply(["cancelled": true], nil); return }
            self.startBatch(pick, reply: reply)
        }
    }

    func finishOpen(_ pick: PickResult?) {
        let done = pendingOpen
        pendingOpen = nil
        done?(pick)
    }

    /// Delivers a picker result. A result for an older picker, or after clear, is
    /// dropped and its copies removed: it must not reopen a closed page. Main thread.
    func finishPick(_ pick: PickResult, token: Int) {
        guard token == openToken, pendingOpen != nil else {
            for url in pick.urls { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
            return
        }
        finishOpen(pick)
    }

    /// Copies a file into a fresh temp folder (a picker's copy is removed when its
    /// callback returns). The original is never written. Safe off the main thread.
    static func copyToTemp(_ source: URL) -> URL? {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("raw-\(UUID().uuidString)")
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let dest = dir.appendingPathComponent(source.lastPathComponent)
            try FileManager.default.copyItem(at: source, to: dest)
            return dest
        } catch {
            try? FileManager.default.removeItem(at: dir)
            return nil
        }
    }

    /// The representation to load: RAW first, else the photo's own JPEG/PNG/HEIC.
    static func preferredType(_ identifiers: [String]) -> UTType? {
        let types = identifiers.compactMap(UTType.init)
        return types.first { $0.conforms(to: .rawImage) }
            ?? types.first { $0.conforms(to: .jpeg) || $0.conforms(to: .png) || $0.conforms(to: .heic) || $0.conforms(to: .heif) }
            ?? types.first { $0.conforms(to: .image) }
    }
}

extension RawBridge: PHPickerViewControllerDelegate {
    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true)
        guard !results.isEmpty else { finishOpen(nil); return }
        let token = openToken
        let wanted = Array(results.prefix(Self.maxBatch))
        let truncated = results.count - wanted.count
        var copies = [URL?](repeating: nil, count: wanted.count)
        let lock = NSLock()
        let group = DispatchGroup()
        for (i, result) in wanted.enumerated() {
            let provider = result.itemProvider
            guard let type = Self.preferredType(provider.registeredTypeIdentifiers) else { continue }
            group.enter()
            provider.loadFileRepresentation(forTypeIdentifier: type.identifier) { url, _ in
                // Background thread: copy only (the picker's file is gone after this returns).
                let copy = url.flatMap(Self.copyToTemp)
                lock.lock(); copies[i] = copy; lock.unlock()
                group.leave()
            }
        }
        group.notify(queue: .main) { [weak self] in
            let urls = copies.compactMap { $0 }
            let pick = PickResult(urls: urls, skipped: wanted.count - urls.count, truncated: truncated)
            if let self { self.finishPick(pick, token: token) }
            else { for url in urls { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) } }
        }
    }
}

extension RawBridge: UIDocumentPickerDelegate {
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        let token = openToken
        let wanted = Array(urls.prefix(Self.maxBatch))
        // Copy on the render queue: large RAW files must not block the main thread.
        queue.async {
            let copies = wanted.compactMap(Self.copyToTemp)
            let pick = PickResult(urls: copies, skipped: wanted.count - copies.count, truncated: urls.count - wanted.count)
            DispatchQueue.main.async { self.finishPick(pick, token: token) }
        }
    }

    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        finishOpen(nil)
    }
}
