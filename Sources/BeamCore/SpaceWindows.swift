// SPDX-License-Identifier: GPL-3.0-or-later
import AppKit

// Private APIs for windows on other Spaces. kAXWindowsAttribute only returns windows on
// the current Space, so we enumerate an app's AX elements by remote token (the trick
// alt-tab-macos uses) and focus through SkyLight, which switches Spaces. See decision 0007.

@_silgen_name("_AXUIElementGetWindow")
private func _AXUIElementGetWindow(_ element: AXUIElement, _ id: UnsafeMutablePointer<CGWindowID>) -> AXError

@_silgen_name("_AXUIElementCreateWithRemoteToken")
private func _AXUIElementCreateWithRemoteToken(_ token: CFData) -> Unmanaged<AXUIElement>?

@_silgen_name("GetProcessForPID")
private func GetProcessForPID(_ pid: pid_t, _ psn: UnsafeMutablePointer<ProcessSerialNumber>) -> OSStatus

enum SpaceWindows {
    static func windowID(_ win: AXUIElement) -> CGWindowID {
        var id: CGWindowID = 0
        return _AXUIElementGetWindow(win, &id) == .success ? id : 0
    }

    /// kAXWindows (current Space, front to back) followed by the app's windows on other
    /// Spaces, without duplicates. If the caller knows how many windows the app has
    /// (`expected` windows passing `counts`), the search runs longer but stops once it has
    /// found them all.
    static func windows(of pid: pid_t, expected: Int? = nil,
                        counts: @escaping (AXUIElement) -> Bool = { _ in true }) -> [AXUIElement] {
        let axApp = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(axApp, 0.25)
        var value: CFTypeRef?
        AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &value)
        let current = (value as? [AXUIElement]) ?? []
        var seen = Set(current.filter(counts).map(windowID))
        if let expected, seen.count >= expected { return current }
        let others = expected == nil
            ? allWindows(pid: pid)
            : allWindows(pid: pid, budget: 3, maxID: 1_000_000, until: { win in
                if counts(win) { seen.insert(windowID(win)) }
                return seen.count >= expected! })
        // Window ID 0 means unknown; keep those rather than collapsing them into one.
        var unique = Set(current.map(windowID))
        return current + others.filter { let id = windowID($0); return id == 0 || unique.insert(id).inserted }
    }

    /// Every standard window of `pid`, on any Space. Element IDs are small integers, so
    /// try them in order until the time budget runs out, or `until` accepts a window.
    /// Apps with many windows (Chrome) can need IDs far past 1000 and well over 0.1s.
    static func allWindows(pid: pid_t, budget: TimeInterval = 0.1, maxID: UInt64 = 1000,
                           until: ((AXUIElement) -> Bool)? = nil) -> [AXUIElement] {
        var token = Data(count: 20)
        token.withUnsafeMutableBytes { p in
            p.storeBytes(of: pid, toByteOffset: 0, as: Int32.self)
            p.storeBytes(of: Int32(0), toByteOffset: 4, as: Int32.self)
            p.storeBytes(of: Int32(0x636f636f), toByteOffset: 8, as: Int32.self) // "coco"
        }
        let deadline = Date().addingTimeInterval(budget)
        var result: [AXUIElement] = []
        for elementID: UInt64 in 0..<maxID {
            if Date() > deadline { break }
            token.withUnsafeMutableBytes { $0.storeBytes(of: elementID, toByteOffset: 12, as: UInt64.self) }
            guard let el = _AXUIElementCreateWithRemoteToken(token as CFData)?.takeRetainedValue() else { continue }
            AXUIElementSetMessagingTimeout(el, 0.05)
            var sub: CFTypeRef?
            guard AXUIElementCopyAttributeValue(el, kAXSubroleAttribute as CFString, &sub) == .success,
                  let s = sub as? String, s == kAXStandardWindowSubrole || s == kAXDialogSubrole else { continue }
            result.append(el)
            if until?(el) == true { break }
        }
        return result
    }

    // SkyLight isn't linkable without private-framework flags, so look the symbols up at runtime.
    private static let skyLight = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY)
    private typealias SetFront = @convention(c) (UnsafeMutablePointer<ProcessSerialNumber>, CGWindowID, UInt32) -> CGError
    private typealias PostEvent = @convention(c) (UnsafeMutablePointer<ProcessSerialNumber>, UnsafeMutablePointer<UInt8>) -> CGError
    private static let setFront: SetFront? = dlsym(skyLight, "_SLPSSetFrontProcessWithOptions").map { unsafeBitCast($0, to: SetFront.self) }
    private static let postEvent: PostEvent? = dlsym(skyLight, "SLPSPostEventRecordTo").map { unsafeBitCast($0, to: PostEvent.self) }

    /// Bring a specific window to the front, switching to its Space. Returns false if
    /// the private calls aren't available, so the caller can fall back to plain AX.
    static func focus(pid: pid_t, windowID wid: CGWindowID) -> Bool {
        guard wid != 0, let setFront, let postEvent else { return false }
        var psn = ProcessSerialNumber()
        guard GetProcessForPID(pid, &psn) == noErr else { return false }
        guard setFront(&psn, wid, 0x200 /* user generated */) == .success else { return false }
        // Synthetic key-window events, as WindowServer sends on a click.
        var bytes = [UInt8](repeating: 0, count: 0xf8)
        bytes[0x04] = 0xf8
        bytes[0x3a] = 0x10
        withUnsafeBytes(of: wid) { for (i, b) in $0.enumerated() { bytes[0x3c + i] = b } }
        for i in 0x20..<0x30 { bytes[i] = 0xff }
        bytes[0x08] = 0x01
        _ = postEvent(&psn, &bytes)
        bytes[0x08] = 0x02
        _ = postEvent(&psn, &bytes)
        return true
    }
}
