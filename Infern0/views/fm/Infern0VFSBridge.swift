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

    private init() {
        refresh()
    }

    func refresh() {
        dsready = ds_is_ready()
        vfsready = vfs_isready()
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
        status = "Preparing Lara offsets..."
        globallogger.log("Preparing Lara offsets.")

        DispatchQueue.global(qos: .userInitiated).async {
            init_offsets()
            lara_offsets_init()

            DispatchQueue.main.async {
                self.progress = 0.12
                self.status = "Running Lara's Darksword kernel session..."
                globallogger.log("Running Darksword.")
            }

            var exploitOK = ds_is_ready()
            if !exploitOK {
                exploitOK = ds_run() == 0 && ds_is_ready()
            }
            guard exploitOK else {
                DispatchQueue.main.async {
                    self.finish(success: false, message: "Darksword failed; VFS was not started.")
                }
                return
            }

            DispatchQueue.main.async {
                self.dsready = true
                self.progress = 0.55
                self.status = "Resolving kernel offsets..."
                globallogger.log("Darksword ready; resolving kernel offsets.")
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
