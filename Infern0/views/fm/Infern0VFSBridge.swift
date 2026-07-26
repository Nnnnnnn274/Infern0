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

enum laraExploitBackend: String, CaseIterable {
    case infern0 = "Infern0"
    case lara = "Lara"
}

@discardableResult
private func configureSelectedLaraBackend() -> laraExploitBackend {
    let backend = laraExploitBackend(
        rawValue: UserDefaults.standard.string(forKey: "laraExploitBackend") ?? ""
    ) ?? .infern0
    ds_set_backend(backend == .lara ? 1 : 0)
    return backend
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
        configureSelectedLaraBackend()
        dsready = ds_is_ready()
        vfsready = vfs_isready()
        let defaults = UserDefaults.standard
        offsetsReady = defaults.object(forKey: "lara.kernprocoff") != nil &&
            defaults.object(forKey: "lara.rootvnodeoff") != nil
    }

    func applySelectedExploitBackend() {
        let backend = configureSelectedLaraBackend()
        globallogger.log("Selected \(backend.rawValue) kernel backend.")
        refresh()
    }

    func resolveKernelcacheOffsets() {
        guard !resolvingOffsets else { return }
        resolvingOffsets = true
        offsetProgress = 0.02
        offsetStatus = "Loading Lara's device offset profile..."
        globallogger.log("Offset Grabber: loading Lara device profile.")

        DispatchQueue.global(qos: .userInitiated).async {
            lara_offsets_init()
            let backend = configureSelectedLaraBackend()

            DispatchQueue.main.async {
                self.offsetProgress = 0.12
                self.offsetStatus = "Starting \(backend.rawValue) kernel backend..."
                globallogger.log("Offset Grabber: starting \(backend.rawValue) backend.")
            }

            let exploitResult = ds_is_ready() ? 0 : ds_run()
            guard exploitResult == 0, ds_is_ready() else {
                DispatchQueue.main.async {
                    self.resolvingOffsets = false
                    self.offsetsReady = false
                    self.offsetProgress = 1.0
                    self.offsetStatus = "Selected kernel backend failed; offsets were not changed."
                    globallogger.log("Offset Grabber: selected backend failed.")
                }
                return
            }

            DispatchQueue.main.async {
                self.offsetProgress = 0.42
                self.offsetStatus = "Checking the cached Lara kernelcache..."
                globallogger.log("Offset Grabber: exploit completed; checking cached kernelcache.")
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
            let backend = configureSelectedLaraBackend()
            lara_offsets_init()

            DispatchQueue.main.async {
                self.progress = 0.12
                self.status = "Starting \(backend.rawValue)'s kernel session..."
                globallogger.log("Starting \(backend.rawValue) kernel backend.")
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
    @AppStorage("selectedMethod") private var selectedMethod: method = .hybrid

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
private struct LaraOffsetEditorView: View {
    @State private var editable: [String: String] = [:]
    @State private var loaded = false
    @State private var status = "Changes save when you press Done or leave a field."
    @State private var lastFocused: String?
    @FocusState private var focusedOffset: String?

    private var names: [String] {
        editable.keys.sorted { lhs, rhs in
            if lhs == "t1sz_boot" { return true }
            if rhs == "t1sz_boot" { return false }
            return lhs.localizedCaseInsensitiveCompare(rhs) == .orderedAscending
        }
    }

    var body: some View {
        List {
            Section {
                LabeledContent("t1sz_boot") {
                    TextField("0x0", text: binding(for: "t1sz_boot"))
                        .multilineTextAlignment(.trailing)
                        .monospaced()
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focusedOffset, equals: "t1sz_boot")
                        .submitLabel(.done)
                        .onSubmit { persist("t1sz_boot") }
                }
            } header: {
                Text("Address Translation")
            } footer: {
                Text("This is Lara's real editable t1sz_boot value. Lara defaults it to 0x11 on A16+ and M-series iPads when it is still zero. Only change it when your device profile or Lara documentation requires it.")
            }

            Section {
                ForEach(names.filter { $0 != "t1sz_boot" && $0 != "pac_mask" }, id: \.self) { name in
                    LabeledContent {
                        TextField("0x0", text: binding(for: name))
                            .multilineTextAlignment(.trailing)
                            .monospaced()
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .focused($focusedOffset, equals: name)
                            .submitLabel(.done)
                            .onSubmit { persist(name) }
                    } label: {
                        Text(name)
                            .font(.system(size: 11, design: .monospaced))
                    }
                }
            } header: {
                Text("Offsets")
            } footer: {
                Text(status)
            }

            if let pacMask = editable["pac_mask"] {
                Section("Calculated") {
                    LabeledContent("pac_mask", value: pacMask)
                        .font(.system(size: 12, design: .monospaced))
                }
            }
        }
        .navigationTitle("Offsets")
        .onAppear(perform: load)
        .onChange(of: focusedOffset) { current in
            if let previous = lastFocused, previous != current {
                persist(previous)
            }
            lastFocused = current
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Save All", action: persistAll)
            }
        }
    }

    private func binding(for name: String) -> Binding<String> {
        Binding(
            get: { editable[name, default: "0x0"] },
            set: { editable[name] = $0 }
        )
    }

    private func load() {
        guard !loaded else { return }
        lara_offsets_init()
        guard let dictionary = alloffs() as? [String: Any] else { return }
        editable = dictionary.reduce(into: [:]) { result, item in
            let value = (item.value as? NSNumber)?.uint64Value ?? 0
            result[item.key] = String(format: "0x%llx", value)
        }
        loaded = true
    }

    private func parsedValue(for name: String) -> UInt64? {
        let raw = editable[name, default: ""]
            .replacingOccurrences(of: "0x", with: "", options: .caseInsensitive)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return UInt64(raw, radix: 16)
    }

    private func persist(_ name: String) {
        guard name != "pac_mask" else { return }
        guard let value = parsedValue(for: name) else {
            status = "\(name) is not valid hexadecimal and was not saved."
            return
        }
        guard lara_setoffsetvalue(name, value) else {
            status = "\(name) was rejected and was not saved."
            return
        }
        status = "\(name) saved to Lara's active offset table."
        if name == "t1sz_boot",
           let dictionary = alloffs() as? [String: Any],
           let mask = dictionary["pac_mask"] as? NSNumber {
            editable["pac_mask"] = String(format: "0x%llx", mask.uint64Value)
        }
    }

    private func persistAll() {
        var failures: [String] = []
        for name in names where name != "pac_mask" {
            guard let value = parsedValue(for: name), lara_setoffsetvalue(name, value) else {
                failures.append(name)
                continue
            }
        }
        status = failures.isEmpty
            ? "All Lara offsets saved."
            : "\(failures.count) invalid value(s) were not saved."
        load()
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
    @AppStorage("laraExploitBackend") private var exploitBackend: laraExploitBackend = .infern0

    var body: some View {
        NavigationStack {
            List {
                Section("About") {
                    Text("Lara").font(.title2.bold())
                    Text("iOS Toolbox using the DarkSword kernel exploit.")
                    Link("Upstream: rooootdev/lara", destination: URL(string: "https://github.com/rooootdev/lara")!)
                    Link("Main developer: rooootdev", destination: URL(string: "https://github.com/rooootdev")!)
                }

                Section("Exploit") {
                    Picker("Kernel Engine", selection: $exploitBackend) {
                        ForEach(laraExploitBackend.allCases, id: \.self) {
                            Text($0.rawValue).tag($0)
                        }
                    }
                    .pickerStyle(.segmented)
                    .disabled(manager.initializing || manager.resolvingOffsets || manager.vfsready)
                    .onChange(of: exploitBackend) { _ in
                        manager.applySelectedExploitBackend()
                    }

                    Picker("Access Method", selection: $selectedMethod) {
                        ForEach(method.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    NavigationLink("Modify Offsets") {
                        LaraOffsetEditorView()
                    }
                    Text(exploitBackend == .lara
                        ? "Native Lara Darksword will be used by offsets, VFS, sandbox, and Fonts."
                        : "Infern0's maintained KRW engine will be used by offsets, VFS, sandbox, and Fonts.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
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
                    Text("The selected global kernel engine is used for offset acquisition and all imported features. Lara's current resolver and bundled libgrabkernel2 provide the kernelcache offsets.")
                }

                Section("File Manager") {
                    Picker("Display Mode", selection: $displayMode) {
                        ForEach(fmAppsDisplayMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    Toggle("Recursive Search in File Manager", isOn: $recursiveSearch)
                    Toggle("Show File Manager in Tabs", isOn: $showFileManagerInTabs)
                }

                Section("App") {
                    Toggle("Keep Alive", isOn: $keepAlive)
                    Toggle("Disable Log Dividers", isOn: $disableLogDividers)
                    Picker("Logs Display", selection: $logDisplayMode) {
                        ForEach(logsdisplaymode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                }

                Section("RemoteCall") {
                    Toggle("Stash KRW primitives", isOn: $stashKRW)
                    Toggle("Keep SpringBoard RemoteCall alive in background", isOn: $keepSpringBoardRemoteCallAlive)
                    Toggle("Allow >10 dock icons", isOn: $allowUnlimitedDockIcons)
                }

                Section("Upstream Attribution") {
                    Text("The Lara toolbox, Santander VFS UI, offset manager, kernelcache resolver, and related integration are upstream work from Lara by rooootdev and its contributors. Infern0 does not claim these components as original work.")
                    Text("Lara is licensed under GNU AGPL-3.0. Infern0's changes are the Tools-tab integration, separated offset-only exploit entry point, VFS compatibility bridge, crash guards, and write verification.")
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

                Section("Additional Lara Credits") {
                    Link("jailbreak.party — dirtyZero Tweaks", destination: URL(string: "https://github.com/jailbreakdotparty")!)
                    Link("Jurre — EditorView and improvements", destination: URL(string: "https://github.com/jurre111")!)
                    Link("neon — Respring, zipmgr, themes, decryption", destination: URL(string: "https://github.com/neonmodder123")!)
                    Link("Skadz — Respring method", destination: URL(string: "https://github.com/skadz108")!)
                    Link("leminlimez — Cowabunga tweaks", destination: URL(string: "https://github.com/leminlimez")!)
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
