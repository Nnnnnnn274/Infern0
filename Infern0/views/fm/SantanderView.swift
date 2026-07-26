//
//  SantanderView.swift
//  symlin2k
//
//  Created by ruter on 15.02.26.
//

import SwiftUI
import Combine

struct SantanderView: View {
    let startpath: String

    @AppStorage("selectedmethod") private var selectedmethod: method = .hybrid
    @ObservedObject private var mgr = laramgr.shared
    
    @State private var showsecret: Bool = false

    init(startPath: String = "/") {
        self.startpath = startPath.isEmpty ? "/" : startPath
    }

    private var readsbx: Bool {
        selectedmethod != .vfs
    }

    private var writevfs: Bool {
        selectedmethod != .sbx
    }

    private var ready: Bool {
        switch selectedmethod {
        case .sbx:
            return mgr.sbxready
        case .vfs:
            return mgr.vfsready
        case .hybrid:
            return mgr.sbxready && mgr.vfsready
        }
    }

    var body: some View {
        Group {
            if ready {
                santanderroot(startpath: startpath, readsbx: readsbx, writevfs: writevfs)
            } else {
                NavigationStack {
                    VStack {
                        Image(systemName: "externaldrive.trianglebadge.exclamationmark")
                            .imageScale(.large)
                        Text("File Manager Not Ready!")
                        Text("Go back to the homepage, click Run Exploit, and then click Initalize System.")
                            .multilineTextAlignment(.center)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

private struct santanderroot: View {
    let readsbx: Bool
    let writevfs: Bool

    @StateObject private var nav: santandernav

    init(startpath: String, readsbx: Bool, writevfs: Bool) {
        self.readsbx = readsbx
        self.writevfs = writevfs
        _nav = StateObject(wrappedValue: santandernav(root: santanderitem(path: startpath, isdir: true)))
    }

    var body: some View {
        NavigationStack(path: $nav.stack) {
            santanderdirview(item: nav.root, readsbx: readsbx, writevfs: writevfs)
                .environmentObject(nav)
                .navigationDestination(for: santanderitem.self) { item in
                    if item.isdir {
                        santanderdirview(item: item, readsbx: readsbx, writevfs: writevfs)
                            .environmentObject(nav)
                    } else {
                        santanderfileview(item: item, readsbx: readsbx, writevfs: writevfs)
                    }
                }
        }
    }
}

final class santandernav: ObservableObject {
    @Published var root: santanderitem
    @Published var stack: [santanderitem] = []

    init(root: santanderitem) {
        self.root = root
    }

    func go(_ item: santanderitem) {
        root = item
        stack.removeAll()
    }
}

extension UIViewController {
    func topMostViewController() -> UIViewController {
        if let presented = presentedViewController {
            return presented.topMostViewController()
        }
        return self
    }
}
