import SwiftUI

struct ContentView: View {
    @State private var status = ""

    var body: some View {
        VStack(spacing: 20) {
            Button("Initialize VFS") {
                let result = vfs_init()
                status = "vfs_init() returned \(result)"
            }

            Text(status)
                .font(.caption)
        }
        .padding()
    }
}
