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

final class Infern0LaraLogger: ObservableObject {
    @Published var logs: [String] = []

    func log(_ message: String) {
        logs.append(message)
        NSLog("[LARA] %@", message)
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
    @Published var status = "VFS has not been initialized."
    @Published var resolvingOffsets = false
    @Published var offsetsReady = false
    @Published var offsetProgress = 0.0
    @Published var offsetStatus = "Kernelcache offsets have not been checked."

    private init() {
        refresh()
    }

    func refresh() {
        dsready = ds_is_ready()
        vfsready = vfs_isready()
        let defaults = UserDefaults.standard
        offsetsReady = defaults.object(forKey: "lara.kernprocoff") != nil &&
            defaults.object(forKey: "lara.rootvnodeoff") != nil
    }

    func resolveKernelcacheOffsets() {
        guard !resolvingOffsets else { return }
        resolvingOffsets = true
        offsetProgress = 0.02
        offsetStatus = "Loading Lara's device offset profile..."
        globallogger.log("Offset Grabber: loading Lara device profile.")

        DispatchQueue.global(qos: .userInitiated).async {
            lara_offsets_init()

            DispatchQueue.main.async {
                self.offsetProgress = 0.12
                self.offsetStatus = "Starting the shared Infern0 kernel session..."
                globallogger.log("Offset Grabber: requesting shared Infern0 KRW.")
            }

            let exploitResult = ds_is_ready() ? 0 : ds_run()
            guard exploitResult == 0, ds_is_ready() else {
                DispatchQueue.main.async {
                    self.resolvingOffsets = false
                    self.offsetsReady = false
                    self.offsetProgress = 1.0
                    self.offsetStatus = "Kernel session failed safely; offsets were not changed."
                    globallogger.log("Offset Grabber: Infern0 KRW failed safely.")
                }
                return
            }

            DispatchQueue.main.async {
                self.dsready = true
                self.offsetProgress = 0.42
                self.offsetStatus = "Checking the cached Lara kernelcache..."
                globallogger.log("Offset Grabber: checking cached kernelcache.")
            }

            var resolved = lara_emergencyfixfunctiontobereplacedlateronquestionmark()
            if !resolved {
                DispatchQueue.main.async {
                    self.offsetProgress = 0.58
                    self.offsetStatus = "Fetching kernelcache with Lara's offset grabber..."
                    globallogger.log("Offset Grabber: invoking Lara/libgrabkernel2.")
                }
                resolved = lara_dlkcache()
            }

            let verified = resolved && lara_verifykernoffsets()
            DispatchQueue.main.async {
                self.resolvingOffsets = false
                self.offsetsReady = verified
                self.offsetProgress = 1.0
                self.offsetStatus = verified
                    ? "Lara kernelcache offsets resolved and verified."
                    : "Offset resolution failed; existing values were not marked ready."
                globallogger.log(verified
                    ? "Offset Grabber: offsets resolved and verified."
                    : "Offset Grabber: resolution or verification failed.")
                self.refresh()
            }
        }
    }

    func clearKernelcacheOffsets() {
        guard !resolvingOffsets else { return }
        lara_clearkerncachedata()
        offsetsReady = false
        offsetProgress = 0.0
        offsetStatus = "Kernelcache and saved Lara offsets were removed."
        globallogger.log("Offset Grabber: cleared kernelcache and saved offsets.")
    }

    func logmsg(_ message: String) {
        status = message
        globallogger.log(message)
    }

    func initializeFullVFS() {
        guard !initializing else { return }
        if vfs_isready() {
            refresh()
            logmsg("VFS is already ready.")
            return
        }

        initializing = true
        progress = 0.02
        status = "Preparing Lara compatibility offsets..."
        globallogger.log("Preparing Lara compatibility offsets.")

        DispatchQueue.global(qos: .userInitiated).async {
            lara_offsets_init()

            DispatchQueue.main.async {
                self.progress = 0.12
                self.status = "Starting Infern0's kernel session..."
                globallogger.log("Lara Darksword is disabled; using Infern0 KRW.")
            }

            var exploitOK = ds_is_ready()
            if !exploitOK {
                exploitOK = ds_run() == 0 && ds_is_ready()
            }
            guard exploitOK else {
                DispatchQueue.main.async {
                    self.finish(success: false, message: "Infern0 kernel session failed safely; VFS was not started.")
                }
                return
            }

            DispatchQueue.main.async {
                self.dsready = true
                self.progress = 0.55
                self.status = "Resolving Lara VFS offsets..."
                globallogger.log("Infern0 KRW ready; resolving Lara VFS offsets.")
            }

            var offsetsOK = lara_emergencyfixfunctiontobereplacedlateronquestionmark()
            if !offsetsOK {
                offsetsOK = lara_dlkcache()
            }
            guard offsetsOK else {
                DispatchQueue.main.async {
                    self.finish(success: false, message: "Kernel offsets could not be resolved.")
                }
                return
            }

            DispatchQueue.main.async {
                self.progress = 0.72
                self.status = "Initializing VFS and sandbox access..."
                globallogger.log("Offsets ready; initializing VFS and SBX.")
            }

            let vfsResult = vfs_init()
            let sandboxResult = sbx_escape(ds_get_our_proc())
            let vfsOK = vfsResult == 0 && vfs_isready()
            let sbxOK = sandboxResult == 0

            DispatchQueue.main.async {
                self.sbxready = sbxOK
                self.vfsready = vfsOK
                let mode = sbxOK ? "VFS + SBX hybrid" : "VFS-only"
                self.finish(
                    success: vfsOK,
                    message: vfsOK ? "\(mode) file manager is ready." : "VFS initialization failed."
                )
            }
        }
    }

    private func finish(success: Bool, message: String) {
        initializing = false
        progress = 1.0
        status = message
        globallogger.log(message)
        refresh()
    }

    func vfsread(path: String, maxSize: Int = 512 * 1024) -> Data? {
        guard vfs_isready() else { return nil }
        let size = vfs_filesize(path)
        guard size > 0 else { return size == 0 ? Data() : nil }
        let count = min(Int(size), maxSize)
        var bytes = [UInt8](repeating: 0, count: count)
        let read = path.withCString { vfs_read($0, &bytes, count, 0) }
        guard read >= 0 else { return nil }
        return Data(bytes.prefix(Int(read)))
    }

    func vfslistdir(path: String) -> [(name: String, isDir: Bool)]? {
        guard vfs_isready() else {
            logmsg("VFS listdir rejected: not ready (\(path)).")
            return nil
        }
        var pointer: UnsafeMutablePointer<vfs_entry_t>?
        var count: Int32 = 0
        let result = path.withCString { vfs_listdir($0, &pointer, &count) }
        guard result == 0, let entries = pointer else {
            logmsg("VFS listdir failed (\(path)), result \(result).")
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
            logmsg("VFS overwrite rejected: VFS is not ready or the source is missing.")
            return false
        }
        let result = target.withCString { targetPointer in
            source.withCString { sourcePointer in
                vfs_overwritefile(targetPointer, sourcePointer)
            }
        }
        logmsg(result == 0 ? "Overwrote \(target)." : "Failed to overwrite \(target) (result \(result)).")
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
        logmsg("Font applied. Use Infern0's Respring control to reload system fonts safely.")
    }
}

@MainActor
private struct Infern0VFSLauncher: View {
    @ObservedObject private var manager = laramgr.shared
    @AppStorage("selectedmethod") private var selectedMethod: method = .hybrid

    private var readyForSelectedMode: Bool {
        switch selectedMethod {
        case .vfs: return manager.vfsready
        case .sbx: return manager.sbxready
        case .hybrid: return manager.vfsready && manager.sbxready
        }
    }

    var body: some View {
        Group {
            if readyForSelectedMode {
                SantanderView()
            } else {
                NavigationStack {
                    List {
                        Section("Access Mode") {
                            Picker("Mode", selection: $selectedMethod) {
                                ForEach(method.allCases, id: \.self) {
                                    Text($0.rawValue).tag($0)
                                }
                            }
                            .pickerStyle(.segmented)
                        }

                        Section("Initialize") {
                            Text(manager.status)
                            if manager.initializing {
                                ProgressView(value: manager.progress)
                            }
                            Button(manager.initializing ? "Initializing..." : "Initialize Full VFS") {
                                manager.initializeFullVFS()
                            }
                            .disabled(manager.initializing)
                        }

                        Section("Detailed Log") {
                            if globallogger.logs.isEmpty {
                                Text("No VFS activity yet.")
                                    .foregroundStyle(.secondary)
                            }
                            ForEach(Array(globallogger.logs.enumerated()), id: \.offset) { _, line in
                                Text(line)
                                    .font(.system(size: 12, design: .monospaced))
                            }
                        }
                    }
                    .navigationTitle("Lara VFS")
                    .onAppear { manager.refresh() }
                }
            }
        }
    }
}

@MainActor
private struct LaraOffsetSnapshotView: View {
    private var entries: [(String, String)] {
        guard let dictionary = alloffs() as? [String: Any] else { return [] }
        return dictionary.map { key, value in
            let number = (value as? NSNumber)?.uint64Value ?? 0
            return (key, String(format: "0x%llx", number))
        }
        .sorted { $0.0.localizedCaseInsensitiveCompare($1.0) == .orderedAscending }
    }

    var body: some View {
        List {
            Section {
                ForEach(Array(entries.enumerated()), id: \.offset) { _, entry in
                    LabeledContent(entry.0, value: entry.1)
                        .font(.system(size: 12, design: .monospaced))
                }
            } footer: {
                Text("Read-only snapshot from Lara's OffsetManagementView data. Editing kernel structure offsets manually is intentionally disabled in Infern0.")
            }
        }
        .navigationTitle("Resolved Offsets")
    }
}

@MainActor
private struct LaraSettingsView: View {
    @ObservedObject private var manager = laramgr.shared
    @AppStorage("selectedmethod") private var selectedMethod: method = .hybrid
    @AppStorage("selectedFMAppsDisplayMode") private var displayMode: fmAppsDisplayMode = .appName
    @AppStorage("fmRecursiveSearch") private var recursiveSearch = false

    var body: some View {
        NavigationStack {
            List {
                Section("Lara") {
                    Text("Lara integration settings and kernelcache offset management.")
                    Link("Upstream: rooootdev/lara", destination: URL(string: "https://github.com/rooootdev/lara")!)
                    Link("Main developer: rooootdev", destination: URL(string: "https://github.com/rooootdev")!)
                }

                Section {
                    Text(manager.offsetStatus)
                    if manager.resolvingOffsets {
                        ProgressView(value: manager.offsetProgress)
                    }
                    Button(manager.resolvingOffsets ? "Resolving..." : "Run Exploit Once & Get Offsets") {
                        manager.resolveKernelcacheOffsets()
                    }
                    .disabled(manager.resolvingOffsets)

                    NavigationLink("View Resolved Offsets") {
                        LaraOffsetSnapshotView()
                    }
                    .disabled(!manager.offsetsReady)

                    Button("Remove Kernelcache & Saved Offsets", role: .destructive) {
                        manager.clearKernelcacheOffsets()
                    }
                    .disabled(manager.resolvingOffsets || !manager.offsetsReady)
                } header: {
                    Text("Kernelcache Offset Grabber")
                } footer: {
                    Text("This uses Lara's current kernelcache resolver and bundled libgrabkernel2. The exploit stage uses Infern0's shared, non-crashing KRW bridge; it is acquired once and reused by VFS and Fonts.")
                }

                Section("File Manager") {
                    Picker("Access Mode", selection: $selectedMethod) {
                        ForEach(method.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)

                    Picker("App Folder Labels", selection: $displayMode) {
                        ForEach(fmAppsDisplayMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    Toggle("Recursive Search", isOn: $recursiveSearch)
                }

                Section("Upstream Attribution") {
                    Text("The Lara toolbox, Santander VFS UI, offset manager, kernelcache resolver, and related integration are upstream work from Lara by rooootdev and its contributors. Infern0 does not claim these components as original work.")
                    Text("Lara is licensed under GNU AGPL-3.0. Infern0's changes are the Tools-tab integration, shared KRW compatibility bridge, crash guards, and write verification.")
                    Link("Lara source and AGPL-3.0 license", destination: URL(string: "https://github.com/rooootdev/lara")!)
                    Link("libgrabkernel2 by Alfie CG (MIT)", destination: URL(string: "https://github.com/rooootdev/lara/blob/main/lara/licenses/LICENSE_libgrabkernel2.md")!)
                }

                Section("Lara Credits") {
                    Link("roooot — Main Developer", destination: URL(string: "https://github.com/rooootdev")!)
                    Link("wh1te4ever — darksword-kexploit-fun", destination: URL(string: "https://github.com/wh1te4ever")!)
                    Link("Duy Tran — RemoteCall improvements", destination: URL(string: "https://github.com/khanhduytran0")!)
                    Link("AppInstalleriOS — offsets and development help", destination: URL(string: "https://github.com/AppInstalleriOSGH")!)
                    Link("lunginspector — frontend rewrite", destination: URL(string: "https://github.com/lunginspector")!)
                    Link("hxhlb — bug fixes", destination: URL(string: "https://github.com/hxhlb")!)
                }

                Section("Detailed Lara Log") {
                    if globallogger.logs.isEmpty {
                        Text("No Lara activity yet.").foregroundStyle(.secondary)
                    }
                    ForEach(Array(globallogger.logs.enumerated()), id: \.offset) { _, line in
                        Text(line).font(.system(size: 12, design: .monospaced))
                    }
                }
            }
            .navigationTitle("Lara Settings")
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
        UIHostingController(rootView: FontPicker(mgr: laramgr.shared))
    }
}

@objc(LaraSettingsFeatureBridge)
@MainActor
final class LaraSettingsFeatureBridge: NSObject {
    @objc static func makeViewController() -> UIViewController {
        UIHostingController(rootView: LaraSettingsView())
    }
}
