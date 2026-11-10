// SPDX-License-Identifier: GPL-3.0-or-later
import CoreServices
import Foundation

/// Watches the app folders with FSEvents and calls `onChange` (on the main queue) after
/// installs, removals and renames, so the app list stays current without rescanning when
/// the panel opens. FSEvents' latency coalesces bursts (an installer writes many files).
/// Changes inside an `.app` bundle (an app updating itself) are ignored.
final class AppWatcher {
    private var stream: FSEventStreamRef?
    private let onChange: () -> Void
    private let queue = DispatchQueue(label: "beam.appwatcher", qos: .utility)

    init(roots: [String], latency: TimeInterval = 2, onChange: @escaping () -> Void) {
        self.onChange = onChange
        let paths = roots.filter { FileManager.default.fileExists(atPath: $0) } as CFArray
        var ctx = FSEventStreamContext(version: 0, info: Unmanaged.passUnretained(self).toOpaque(),
                                       retain: nil, release: nil, copyDescription: nil)
        let callback: FSEventStreamCallback = { _, info, count, paths, _, _ in
            guard let info else { return }
            let me = Unmanaged<AppWatcher>.fromOpaque(info).takeUnretainedValue()
            // kFSEventStreamCreateFlagUseCFTypes: `paths` is a CFArray of CFStrings (without the
            // flag it is a C array of C strings, and reading it as an array crashes).
            let list = (Unmanaged<CFArray>.fromOpaque(paths).takeUnretainedValue() as NSArray) as? [String] ?? []
            if list.prefix(count).contains(where: { AppWatcher.isRelevant($0) }) {
                DispatchQueue.main.async { me.onChange() }
            }
        }
        stream = FSEventStreamCreate(nil, callback, &ctx, paths, FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
                                     latency, FSEventStreamCreateFlags(kFSEventStreamCreateFlagUseCFTypes))
        if let stream {
            FSEventStreamSetDispatchQueue(stream, queue)
            FSEventStreamStart(stream)
        }
    }

    deinit {
        if let stream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
        }
    }

    /// A changed directory outside any app bundle (a root itself or a vendor subfolder).
    /// FSEvents reports directories with a trailing slash.
    static func isRelevant(_ path: String) -> Bool {
        let p = path.hasSuffix("/") ? String(path.dropLast()) : path
        return !p.hasSuffix(".app") && !p.contains(".app/")
    }
}
