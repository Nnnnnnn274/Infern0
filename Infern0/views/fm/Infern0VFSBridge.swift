import Combine
import Foundation
import SwiftUI
import UIKit

enum method: String, CaseIterable {
    case vfs = "VFS"
    case sbx = "SBX"
    case hybrid = "Hybrid"
}

enum fmAppsDisplayMode: String, CaseIterable {
    case UUID = "UUID"
    case bundleID = "Bundle ID"
    case appName = "App Name"
}

enum logsdisplaymode: String, CaseIterable {
    case tabs = "In Tabs"
    case toolbar = "In Toolbar"
    case content = "Directly in ContentView"
}

final class Infern0LaraLogger: ObservableObject {
    @Published private(set) var logs: [String] = []

    func log(_ message: String) {
        let timestamp = DateFormatter.localizedString(
            from: Date(),
            dateStyle: .none,
            timeStyle: .medium
        )
        DispatchQueue.main.async {
            self.logs.append("[\(timestamp)] \(message)")
            if self.logs.count > 300 {
                self.logs.removeFirst(self.logs.count - 300)
            }
        }
        NSLog("[LARA] %@", message)
    }

    func clear() {
        logs.removeAll()
    }
}

let globallogger = Infern0LaraLogger()

final class laramgr: ObservableObject {
    static let shared = laramgr()
    static let fontpath = "/System/Library/Fonts/Core/SFUI.ttf"
    static let italicfontpath = "/System/Library/Fonts/Core/SFUIItalic.ttf"
    static let monofontpath = "/System/Library/Fonts/Core/SFUIMono.ttf"

    @Published var dsready = false
    @Published var vfsready = false
    @Published var sbxready = false
    @Published var initializing = false
    @Published var progress = 0.0
    @Published var status = "Lara has not been initialized."

    private init() {
        vfs_setlogcallback { messagePointer in
            guard let messagePointer else { return }
            globallogger.log("(vfs) \(String(cString: messagePointer))")
        }
        vfs_setprogresscallback { value in
            DispatchQueue.main.async {
                guard laramgr.shared.initializing else { return }
                laramgr.shared.progress = max(laramgr.shared.progress, value)
            }
        }
        refresh()
    }

    func refresh() {
        dsready = ds_is_ready()
        vfsready = vfs_isready()
        // Main's Lara VFS is the access primitive used by the restored frontend.
        // Keep the legacy selectors usable without selecting a second backend.
        sbxready = vfsready
        if vfsready {
            status = "Lara VFS is ready."
        } else if dsready {
            status = "Kernel session ready. Initialize VFS to browse or change files."
        } else {
            status = "Run the shared Lara session, then initialize VFS."
        }
    }

    func runSharedSession() {
        guard !initializing else {
            logmsg("A Lara operation is already running.")
            return
        }
        initializing = true
        progress = 0.05
        status = "Preparing the shared Lara session..."
        globallogger.log("Starting the backend already bundled with main.")

        DispatchQueue.global(qos: .userInitiated).async {
            lara_offsets_init()
            let result = ds_is_ready() ? 0 : ds_run()
            let ready = result == 0 && ds_is_ready()
            let base = ready ? ds_get_kernel_base() : 0

            DispatchQueue.main.async {
                self.initializing = false
                self.progress = 1
                self.refresh()
                self.status = ready
                    ? String(format: "Shared Lara session ready — kernel base 0x%llx.", base)
                    : "The shared Lara session failed safely (result \(result))."
                globallogger.log(self.status)
            }
        }
    }

    func initializeFullVFS() {
        guard !initializing else {
            logmsg("A Lara operation is already running.")
            return
        }
        if vfs_isready() {
            refresh()
            logmsg("Lara VFS is already ready.")
            return
        }

        initializing = true
        progress = 0.05
        status = "Preparing the shared Lara session..."
        globallogger.log("VFS initialization requested.")

        DispatchQueue.global(qos: .userInitiated).async {
            lara_offsets_init()
            var sessionReady = ds_is_ready()
            if !sessionReady {
                DispatchQueue.main.async {
                    self.progress = 0.25
                    self.status = "Starting the shared Lara session..."
                }
                sessionReady = ds_run() == 0 && ds_is_ready()
            }

            guard sessionReady else {
                DispatchQueue.main.async {
                    self.finish(success: false, message: "Kernel session failed; VFS was not started.")
                }
                return
            }

            DispatchQueue.main.async {
                self.progress = 0.55
                self.status = "Initializing Lara VFS..."
                globallogger.log("Kernel session ready; calling the existing VFS initializer.")
            }

            let result = vfs_init()
            let ready = result == 0 && vfs_isready()
            DispatchQueue.main.async {
                self.finish(
                    success: ready,
                    message: ready
                        ? "Lara VFS is ready for the file manager and font controls."
                        : "VFS initialization failed safely (result \(result))."
                )
            }
        }
    }

    private func finish(success: Bool, message: String) {
        initializing = false
        progress = 1
        refresh()
        status = message
        globallogger.log(message)
    }

    func logmsg(_ message: String) {
        status = message
        globallogger.log(message)
    }

    func vfsread(path: String, maxSize: Int = 512 * 1024) -> Data? {
        guard vfs_isready() else {
            logmsg("Read rejected because VFS is not ready: \(path)")
            return nil
        }
        let size = vfs_filesize(path)
        guard size >= 0 else {
            logmsg("Could not determine file size: \(path)")
            return nil
        }
        guard size > 0 else { return Data() }
        let count = min(Int(size), maxSize)
        var bytes = [UInt8](repeating: 0, count: count)
        let read = path.withCString { vfs_read($0, &bytes, count, 0) }
        guard read >= 0 else {
            logmsg("VFS read failed: \(path)")
            return nil
        }
        return Data(bytes.prefix(Int(read)))
    }

    func vfslistdir(path: String) -> [(name: String, isDir: Bool)]? {
        guard vfs_isready() else {
            logmsg("Directory listing rejected because VFS is not ready: \(path)")
            return nil
        }
        var pointer: UnsafeMutablePointer<vfs_entry_t>?
        var count: Int32 = 0
        let result = path.withCString { vfs_listdir($0, &pointer, &count) }
        guard result == 0, let entries = pointer else {
            logmsg("Directory listing failed (\(result)): \(path)")
            return nil
        }
        defer { vfs_freelisting(entries) }

        var items: [(String, Bool)] = []
        for index in 0..<Int(count) {
            let entry = entries[index]
            let name = withUnsafePointer(to: entry.name) { pointer in
                pointer.withMemoryRebound(to: CChar.self, capacity: 256) {
                    String(cString: $0)
                }
            }
            items.append((name, entry.d_type == 4))
        }
        logmsg("Listed \(items.count) entries in \(path).")
        return items.sorted { $0.0.localizedCaseInsensitiveCompare($1.0) == .orderedAscending }
    }

    func vfsoverwritefromlocalpath(target: String, source: String) -> Bool {
        guard vfs_isready(), FileManager.default.fileExists(atPath: source) else {
            logmsg("Write rejected: initialize VFS and verify the source file first.")
            return false
        }
        let result = target.withCString { targetPointer in
            source.withCString { sourcePointer in
                vfs_overwritefile(targetPointer, sourcePointer)
            }
        }
        logmsg(result == 0
            ? "Overwrote \(target)."
            : "Failed to overwrite \(target) (result \(result)).")
        return result == 0
    }

    func vfsoverwritewithdata(target: String, data: Data) -> Bool {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("infern0-vfs-\(UUID().uuidString)")
        do {
            try data.write(to: tempURL, options: .atomic)
            defer { try? FileManager.default.removeItem(at: tempURL) }
            return vfsoverwritefromlocalpath(target: target, source: tempURL.path)
        } catch {
            logmsg("Could not prepare VFS write: \(error.localizedDescription)")
            return false
        }
    }

    func respring() {
        logmsg("Font applied. Use Infern0's Respring control to reload system fonts.")
    }
}

@MainActor
private struct LaraStatusControls: View {
    @ObservedObject var manager: laramgr

    var body: some View {
        Section {
            LabeledContent("Kernel Session", value: manager.dsready ? "Ready" : "Not Ready")
            LabeledContent("VFS", value: manager.vfsready ? "Ready" : "Not Ready")
            Text(manager.status)
                .font(.footnote)
                .foregroundStyle(.secondary)
            if manager.initializing {
                ProgressView(value: manager.progress)
            }
            Button(manager.dsready ? "Refresh Session Status" : "Run Shared Lara Session") {
                manager.dsready ? manager.refresh() : manager.runSharedSession()
            }
            .disabled(manager.initializing)
            Button(manager.vfsready ? "Refresh VFS Status" : "Initialize Lara VFS") {
                manager.vfsready ? manager.refresh() : manager.initializeFullVFS()
            }
            .disabled(manager.initializing)
        } header: {
            Text("Runtime Controls")
        } footer: {
            Text("These controls call the Lara backend already present on main. No alternate backend is installed or selected by this frontend.")
        }
    }
}

@MainActor
private struct LaraDetailedLog: View {
    var body: some View {
        Section {
            if globallogger.logs.isEmpty {
                Text("No Lara activity yet.")
                    .foregroundStyle(.secondary)
            }
            ForEach(Array(globallogger.logs.enumerated()), id: \.offset) { _, line in
                Text(line)
                    .font(.system(size: 11, design: .monospaced))
                    .textSelection(.enabled)
            }
            if !globallogger.logs.isEmpty {
                Button("Clear Lara Log", role: .destructive) {
                    globallogger.clear()
                }
            }
        } header: {
            Text("Detailed Lara Log")
        }
    }
}

@MainActor
private struct Infern0VFSLauncher: View {
    @ObservedObject private var manager = laramgr.shared

    var body: some View {
        Group {
            if manager.vfsready {
                SantanderView()
            } else {
                NavigationStack {
                    List {
                        LaraStatusControls(manager: manager)
                        LaraDetailedLog()
                    }
                    .navigationTitle("Lara VFS")
                    .refreshable { manager.refresh() }
                    .onAppear { manager.refresh() }
                }
            }
        }
    }
}

@MainActor
private struct LaraFontLauncher: View {
    @ObservedObject private var manager = laramgr.shared

    var body: some View {
        Group {
            if manager.vfsready {
                FontPicker(mgr: manager)
            } else {
                NavigationStack {
                    List {
                        Section {
                            Text("Fonts use Lara VFS to replace the selected system font file. Initialize VFS before using font controls.")
                                .foregroundStyle(.secondary)
                        } header: {
                            Text("Font Manager")
                        }
                        LaraStatusControls(manager: manager)
                        LaraDetailedLog()
                    }
                    .navigationTitle("Lara Fonts")
                    .refreshable { manager.refresh() }
                    .onAppear { manager.refresh() }
                }
            }
        }
    }
}

@MainActor
private struct LaraSettingsView: View {
    @ObservedObject private var manager = laramgr.shared
    @AppStorage("selectedMethod") private var selectedMethod: method = .hybrid
    @AppStorage("selectedFMAppsDisplayMode") private var displayMode: fmAppsDisplayMode = .appName
    @AppStorage("fmRecursiveSearch") private var recursiveSearch = false
    @AppStorage("keepAlive") private var keepAlive = false
    @AppStorage("stashKRW") private var stashKRW = false
    @AppStorage("keepSpringBoardRemoteCallAliveIOS16") private var keepSpringBoardRemoteCallAlive = false
    @AppStorage("logsdisplaymode") private var logDisplayMode: logsdisplaymode = .toolbar
    @AppStorage("loggerNoBS") private var disableLogDividers = true
    @AppStorage("showFMInTabs") private var showFileManagerInTabs = true
    @AppStorage("rcDockUnlimited") private var allowUnlimitedDockIcons = false

    var body: some View {
        NavigationStack {
            List {
                LaraStatusControls(manager: manager)

                Section {
                    Picker("Access Method", selection: $selectedMethod) {
                        ForEach(method.allCases, id: \.self) {
                            Text($0.rawValue).tag($0)
                        }
                    }
                    .pickerStyle(.segmented)
                    Picker("App Names", selection: $displayMode) {
                        ForEach(fmAppsDisplayMode.allCases, id: \.self) {
                            Text($0.rawValue).tag($0)
                        }
                    }
                    Toggle("Recursive Search", isOn: $recursiveSearch)
                    Toggle("Show File Manager in Tabs", isOn: $showFileManagerInTabs)
                } header: {
                    Text("File Manager")
                } footer: {
                    Text("VFS, SBX, and Hybrid remain available as frontend layout modes. Main's existing Lara VFS supplies file access.")
                }

                Section("Logging") {
                    Toggle("Disable Log Dividers", isOn: $disableLogDividers)
                    Picker("Logs Display", selection: $logDisplayMode) {
                        ForEach(logsdisplaymode.allCases, id: \.self) {
                            Text($0.rawValue).tag($0)
                        }
                    }
                }

                Section("Session") {
                    Toggle("Keep Alive", isOn: $keepAlive)
                    Toggle("Stash KRW Primitives", isOn: $stashKRW)
                    Toggle("Keep SpringBoard RemoteCall Alive", isOn: $keepSpringBoardRemoteCallAlive)
                    Toggle("Allow More Than 10 Dock Icons", isOn: $allowUnlimitedDockIcons)
                }

                Section("Upstream") {
                    Link("Lara by rooootdev", destination: URL(string: "https://github.com/rooootdev/lara")!)
                    Text("The Lara toolbox and Santander frontend are upstream AGPL-3.0 work. Infern0 provides this native Tools-tab presentation and connects it to the backend already bundled in main.")
                        .font(.footnote)
                }

                LaraDetailedLog()
            }
            .navigationTitle("Lara Settings")
            .refreshable { manager.refresh() }
            .onAppear { manager.refresh() }
        }
    }
}

@objc(LaraVFSFeatureBridge)
@MainActor
final class LaraVFSFeatureBridge: NSObject {
    @objc static func makeViewController() -> UIViewController {
        UIHostingController(rootView: Infern0VFSLauncher())
    }
}

@objc(LaraFontFeatureBridge)
@MainActor
final class LaraFontFeatureBridge: NSObject {
    @objc static func makeViewController() -> UIViewController {
        UIHostingController(rootView: LaraFontLauncher())
    }
}

@objc(LaraSettingsFeatureBridge)
@MainActor
final class LaraSettingsFeatureBridge: NSObject {
    @objc static func makeViewController() -> UIViewController {
        UIHostingController(rootView: LaraSettingsView())
    }
}
