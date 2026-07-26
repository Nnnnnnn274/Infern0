//
// Small PartyUI dependencies used by Lara's Santander file manager.
//

import Foundation
import SwiftUI
import UIKit

public enum width {
    public static var headerIcon: CGFloat {
        if #available(iOS 19.0, *) { return 24 }
        return 22
    }
}

public struct HeaderLabel: View {
    var text: String
    var icon: String

    public init(text: String, icon: String) {
        self.text = text
        self.icon = icon
    }

    public var body: some View {
        HStack {
            Image(systemName: icon)
                .frame(width: width.headerIcon, alignment: .center)
            Text(text)
        }
    }
}

@MainActor
public func presentShareSheet(with url: URL) {
    guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
          let window = windowScene.windows.first,
          var controller = window.rootViewController else {
        return
    }

    while let presented = controller.presentedViewController {
        controller = presented
    }

    let activity = UIActivityViewController(activityItems: [url], applicationActivities: nil)
    if UIDevice.current.userInterfaceIdiom == .pad {
        activity.popoverPresentationController?.sourceView = controller.view
        activity.popoverPresentationController?.sourceRect = CGRect(
            x: controller.view.bounds.midX,
            y: controller.view.bounds.midY,
            width: 0,
            height: 0
        )
        activity.popoverPresentationController?.permittedArrowDirections = []
    }
    controller.present(activity, animated: true)
}
