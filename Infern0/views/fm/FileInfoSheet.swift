//
//  FileInfoSheet.swift
//  lara
//
//  Created by lunginspector on 5/22/26.
//

import SwiftUI
import UniformTypeIdentifiers

struct FileInfoProperties {
    var id = UUID()
    var fileExists: Bool
    var kind: String
    var uttype: String
    var size: Int
    var created: String
    var modified: String
    var isSymlink: Bool
    var posixPerms: String
    var owner: String
    var group: String
    var readable: Bool
    var writable: Bool
    var executable: Bool
}

struct infosheetcontent: View {
    let entry: santanderitem
    @State private var fileInfo: FileInfoProperties?
    
    var body: some View {
        Group {
            if let info = fileInfo {
                santanderinfosheet(name: entry.name, file: info)
            } else {
                ProgressView()
                    .onAppear {
                        DispatchQueue.global(qos: .userInitiated).async {
                            let info = santanderfs.fileDetails(path: entry.path)
                            DispatchQueue.main.async {
                                fileInfo = info
                            }
                        }
                    }
            }
        }
    }
}

struct santanderinfosheet: View {
    @Environment(\.dismiss) var dismiss
    
    var name: String
    var file: FileInfoProperties
    
    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 12) {
                        Image(systemName: file.kind == "directory" ? "folder" : "doc")
                        VStack(alignment: .leading) {
                            Text(name)
                            if file.kind == "file" {
                                Text("\(ByteCountFormatter.string(fromByteCount: Int64(file.size), countStyle: .file))")
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                
                Section(header: HeaderLabel(text: "File Information", icon: "info.circle")) {
                    LabeledContent("UTType") {
                        Text(file.uttype)
                    }
                    LabeledContent("Creation Date") {
                        Text(file.created)
                    }
                    LabeledContent("Last Modified") {
                        Text(file.modified)
                    }
                    LabeledContent("Symlink") {
                        Image(systemName: file.isSymlink ? "checkmark" : "xmark")
                    }
                }
                
                Section(header: HeaderLabel(text: "Permissions", icon: "shield")) {
                    LabeledContent("POSIX Permissions") {
                        Text(file.posixPerms)
                    }
                    LabeledContent("Owner") {
                        Text(file.owner)
                    }
                    LabeledContent("Group") {
                        Text(file.group)
                    }
                    LabeledContent("Readable") {
                        Image(systemName: file.readable ? "checkmark" : "xmark")
                    }
                    LabeledContent("Writable") {
                        Image(systemName: file.writable ? "checkmark" : "xmark")
                    }
                    LabeledContent("Executable") {
                        Image(systemName: file.executable ? "checkmark" : "xmark")
                    }
                }
            }
            .navigationTitle("File Info")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: {
                        dismiss()
                    }) {
                        Image(systemName: "xmark")
                    }
                }
            }
        }
    }
}

struct santandernamesheet: View {
    let title: String
    let itemname: String
    let placeholder: String
    let actiontitle: String
    let apply: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""

    var body: some View {
        NavigationStack {
            Form {
                Section(itemname) {
                    TextField(placeholder, text: $name)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                if name.isEmpty {
                    name = placeholder
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(actiontitle) {
                        apply(name)
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

struct santandernewfilesheet: View {
    let itemname: String
    let apply: (String, String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name = "untitled.txt"
    @State private var text = ""

    var body: some View {
        NavigationStack {
            Form {
                Section(itemname) {
                    TextField("Filename", text: $name)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }

                Section("Contents") {
                    TextEditor(text: $text)
                        .frame(minHeight: 180)
                        .font(.system(.body, design: .monospaced))
                }
            }
            .navigationTitle("Create File")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Create") {
                        apply(name, text)
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

struct santanderchmodsheet: View {
    let item: santanderitem
    let apply: (UInt16) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var text = ""

    var body: some View {
        NavigationStack {
            Form {
                Section(item.name) {
                    TextField("e.g. 755", text: $text)
                        .keyboardType(.numberPad)
                        .font(.system(.body, design: .monospaced))
                }
            }
            .navigationTitle("Chmod")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Apply") {
                        guard let mode = UInt16(text, radix: 8) else { return }
                        apply(mode)
                        dismiss()
                    }
                    .disabled(UInt16(text, radix: 8) == nil)
                }
            }
        }
    }
}

struct santanderchownsheet: View {
    let item: santanderitem
    let apply: (UInt32, UInt32) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var uid = ""
    @State private var gid = ""

    var body: some View {
        NavigationStack {
            Form {
                Section(item.name) {
                    TextField("UID (e.g. 501)", text: $uid)
                        .keyboardType(.numberPad)
                    TextField("GID (e.g. 501)", text: $gid)
                        .keyboardType(.numberPad)
                }
            }
            .navigationTitle("Chown")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Apply") {
                        guard let uid = UInt32(uid), let gid = UInt32(gid) else { return }
                        apply(uid, gid)
                        dismiss()
                    }
                    .disabled(UInt32(uid) == nil || UInt32(gid) == nil)
                }
            }
        }
    }
}

struct santanderfiledoc: FileDocument {
    static var readableContentTypes: [UTType] { [.data] }
    let url: URL

    init(url: URL) {
        self.url = url
    }

    init(configuration: ReadConfiguration) throws {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        let data = configuration.file.regularFileContents ?? Data()
        try data.write(to: tmp)
        self.url = tmp
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        return try FileWrapper(url: url, options: .immediate)
    }
}
