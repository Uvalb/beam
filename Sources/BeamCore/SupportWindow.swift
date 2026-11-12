// SPDX-License-Identifier: GPL-3.0-or-later
import AppKit
import SwiftUI

@MainActor
final class SupportModel: ObservableObject {
    enum Message: Equatable { case none, checking, thanks, error(String) }

    @Published var licenseKey = ""
    @Published var message: Message = .none
    @Published var isSupporter = Support.isSupporter

    func activate() {
        let key = licenseKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty, message != .checking else { return }
        message = .checking
        Task {
            do {
                let (result, info) = try await LicenseCheck.run(key: key)
                switch result {
                case .valid:
                    Support.markSupporter(info, key: key)
                    isSupporter = true
                    message = .thanks
                case .invalid:
                    message = .error("That key wasn’t recognised. Check that you copied all of it, or write to support@beamlauncher.app and we’ll sort it out.")
                case .testKey:
                    message = .error("That’s a test-mode key, which can’t unlock a real supporter badge.")
                case .wrongProduct:
                    message = .error("That key belongs to a different product.")
                }
            } catch LicenseError.offline {
                message = .error("Couldn’t reach the license server. Check your connection and try again; Beam checks once now, then rarely.")
            } catch {
                message = .error("The license server gave an unexpected answer. Please try again in a moment.")
            }
        }
    }
}

struct SupportView: View {
    @ObservedObject var model: SupportModel

    var body: some View {
        Form {
            if model.message != .thanks {
                Section {
                Text(model.isSupporter
                     ? "You’re a Beam supporter. Thank you ♥ The reminders are off for good."
                     : "Paste the supporter key from the thank-you page after checkout to turn off the support reminders. Thank you for keeping Beam alive ♥")
                    .fixedSize(horizontal: false, vertical: true)
            }
            }
            if !model.isSupporter {
                Section {
                    HStack {
                        TextField("BEAM-XXXXX-XXXXX-XXXXX-XXXXX", text: $model.licenseKey)
                            .onSubmit { model.activate() }
                        Button("Activate") { model.activate() }
                            .disabled(model.licenseKey.trimmingCharacters(in: .whitespaces).isEmpty || model.message == .checking)
                    }
                    switch model.message {
                    case .checking: HStack { ProgressView().controlSize(.small); Text("Checking your key…") }
                    case .error(let text): Text(text).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
                    default: EmptyView()
                    }
                } footer: {
                    Text("Beam checks your key with beamlauncher.app now and about once a month after, so a refund ends the badge. The only other request is the optional update check, which sends no system profile.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            if model.message == .thanks {
                Section { Label("Thank you! Your key checked out, and Beam won’t remind you again.", systemImage: "heart.fill").foregroundStyle(.pink) }
            }
        }
        .formStyle(.grouped)
        .frame(width: 480)
        .fixedSize(horizontal: false, vertical: true)
    }
}

@MainActor
final class SupportWindowController: NSObject {
    private let model = SupportModel()
    private lazy var window: NSWindow = {
        let w = NSWindow(contentViewController: NSHostingController(rootView: SupportView(model: model)))
        w.title = "Beam Launcher License"
        w.styleMask = [.titled, .closable]
        w.isReleasedWhenClosed = false
        return w
    }()

    /// `key` comes from a `beam://license?key=…` link; it's filled in and checked right away.
    func show(key: String = "") {
        model.isSupporter = Support.isSupporter
        if !key.isEmpty, !model.isSupporter {
            model.licenseKey = key
            model.activate()
        }
        if !window.isVisible { window.center() }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}
