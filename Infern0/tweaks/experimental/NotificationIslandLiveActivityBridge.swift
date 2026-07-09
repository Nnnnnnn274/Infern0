//
//  NotificationIslandLiveActivityBridge.swift
//  Cyanide
//

import ActivityKit
import Dispatch
import Foundation
import UIKit

@objc(NotificationIslandLiveActivityBridge)
final class NotificationIslandLiveActivityBridge: NSObject {
    @objc static func canPresent() -> Bool {
        guard #available(iOS 16.2, *) else { return false }
        return ActivityAuthorizationInfo().areActivitiesEnabled
    }

    @objc static func prepare() -> Bool {
        guard #available(iOS 16.2, *) else {
            print("[NISLAND] ActivityKit unavailable on this iOS version")
            return false
        }
        guard activityKitEnabled() else { return false }
        return runSync("prepare") {
            await NotificationIslandLiveActivityController.shared.prepare()
        }
    }

    @objc static func show(title: String, body: String, source: String, requestIdentifier: String) -> Bool {
        guard #available(iOS 16.2, *) else {
            print("[NISLAND] ActivityKit unavailable on this iOS version")
            return false
        }
        guard activityKitEnabled() else { return false }
        return runSync("show") {
            await NotificationIslandLiveActivityController.shared.show(
                title: title,
                body: body,
                source: source,
                requestIdentifier: requestIdentifier
            )
        }
    }

    @objc static func showSample() -> Bool {
        guard #available(iOS 16.2, *) else {
            print("[NISLAND] ActivityKit unavailable on this iOS version")
            return false
        }
        guard activityKitEnabled() else { return false }
        let prepared = runSync("sample prepare") {
            await NotificationIslandLiveActivityController.shared.prepare()
        }
        guard prepared else { return false }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            UIApplication.shared.perform(NSSelectorFromString("suspend"))
        }
        Thread.sleep(forTimeInterval: 0.9)

        return show(
            title: "Notification Island",
            body: "Ready.",
            source: "Cyanide",
            requestIdentifier: "cyanide.sample.\(Date().timeIntervalSince1970)"
        )
    }

    @objc static func end() {
        guard #available(iOS 16.2, *) else { return }
        Task {
            await NotificationIslandLiveActivityController.shared.end()
        }
    }

    private static func activityKitEnabled() -> Bool {
        guard #available(iOS 16.2, *) else {
            print("[NISLAND] ActivityKit unavailable on this iOS version")
            return false
        }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            print("[NISLAND] ActivityKit disabled by system settings")
            return false
        }
        return true
    }

    private static func runSync(_ label: String, operation: @escaping @Sendable () async -> Bool) -> Bool {
        let semaphore = DispatchSemaphore(value: 0)
        let result = LockedResult()
        Task {
            let ok = await operation()
            result.set(ok)
            semaphore.signal()
        }
        let timeout = semaphore.wait(timeout: .now() + 3)
        if timeout == .timedOut {
            print("[NISLAND] ActivityKit \(label) timed out")
            return false
        }
        return result.value
    }
}

private final class LockedResult: @unchecked Sendable {
    private let lock = NSLock()
    private var storedValue = false

    var value: Bool {
        lock.lock()
        defer { lock.unlock() }
        return storedValue
    }

    func set(_ newValue: Bool) {
        lock.lock()
        storedValue = newValue
        lock.unlock()
    }
}

@available(iOS 16.2, *)
private actor NotificationIslandLiveActivityController {
    static let shared = NotificationIslandLiveActivityController()

    private var activity: Activity<NotificationIslandActivityAttributes>?
    private var sequence = 0

    func prepare() async -> Bool {
        if activeActivity() != nil { return true }

        do {
            let attributes = NotificationIslandActivityAttributes(stableIdentifier: "cyanide.notification-island")
            let content = ActivityContent(
                state: quietState(),
                staleDate: Date().addingTimeInterval(60 * 60 * 7),
                relevanceScore: 0
            )
            activity = try Activity.request(
                attributes: attributes,
                content: content,
                pushType: nil
            )
            if let activity {
                print("[NISLAND] ActivityKit prepared id=\(activity.id) state=\(activity.activityState) count=\(Activity<NotificationIslandActivityAttributes>.activities.count)")
                return true
            }
            return false
        } catch {
            print("[NISLAND] ActivityKit prepare failed: \(error)")
            return false
        }
    }

    func show(title rawTitle: String, body rawBody: String, source rawSource: String, requestIdentifier: String) async -> Bool {
        let title = rawTitle.isEmpty ? "Notification" : rawTitle
        let body = rawBody
        let source = rawSource.isEmpty ? "Notification" : rawSource
        sequence += 1

        let state = NotificationIslandActivityAttributes.ContentState(
            title: title,
            body: body,
            source: source,
            requestIdentifier: requestIdentifier,
            sequence: sequence,
            isVisible: true
        )
        let content = ActivityContent(
            state: state,
            staleDate: Date().addingTimeInterval(12),
            relevanceScore: 100
        )
        let alert = AlertConfiguration(
            title: LocalizedStringResource(String.LocalizationValue(alertTitle(title: title, source: source))),
            body: LocalizedStringResource(String.LocalizationValue(alertBody(title: title, body: body, source: source))),
            sound: .default
        )

        if activeActivity() == nil {
            let ready = await prepare()
            if !ready {
                return false
            }
        }
        guard let current = activeActivity() else { return false }

        await current.update(content, alertConfiguration: alert)
        activity = current
        print("[NISLAND] ActivityKit update id=\(current.id) state=\(current.activityState) count=\(Activity<NotificationIslandActivityAttributes>.activities.count)")

        let seenSequence = sequence
        Task {
            try? await Task.sleep(nanoseconds: 12_000_000_000)
            await self.quietIfStill(sequence: seenSequence)
        }
        print("[NISLAND] ActivityKit show seq=\(sequence) title='\(title)' source='\(source)'")
        return activeActivity() != nil
    }

    func end() async {
        guard let current = activeActivity() else {
            activity = nil
            return
        }
        await current.end(nil, dismissalPolicy: .immediate)
        activity = nil
        print("[NISLAND] ActivityKit ended")
    }

    private func quietIfStill(sequence seenSequence: Int) async {
        guard sequence == seenSequence else { return }
        guard let current = activeActivity() else { return }
        let content = ActivityContent(
            state: quietState(),
            staleDate: Date().addingTimeInterval(60 * 60 * 7),
            relevanceScore: 0
        )
        await current.update(content)
        print("[NISLAND] ActivityKit quiet id=\(current.id) state=\(current.activityState)")
    }

    private func quietState() -> NotificationIslandActivityAttributes.ContentState {
        NotificationIslandActivityAttributes.ContentState(
            title: "",
            body: "",
            source: "",
            requestIdentifier: "cyanide.notification-island.quiet",
            sequence: sequence,
            isVisible: false
        )
    }

    private func alertTitle(title: String, source: String) -> String {
        guard !source.isEmpty, source != "Cyanide", source != title else {
            return alertLine(title, limit: 34)
        }
        return alertLine(source, limit: 34)
    }

    private func alertBody(title: String, body: String, source: String) -> String {
        let value: String
        if !source.isEmpty, source != "Cyanide", source != title {
            value = body.isEmpty ? title : "\(title): \(body)"
        } else {
            value = body.isEmpty ? source : body
        }
        return alertLine(value, limit: 24)
    }

    private func alertLine(_ value: String, limit: Int) -> String {
        let collapsed = value
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard collapsed.count > limit else { return collapsed }
        return String(collapsed.prefix(max(0, limit - 1))) + "…"
    }

    private func activeActivity() -> Activity<NotificationIslandActivityAttributes>? {
        if let activity, activity.activityState == .active {
            return activity
        }
        if let existing = Activity<NotificationIslandActivityAttributes>.activities.first(where: { $0.activityState == .active }) {
            activity = existing
            return existing
        }
        activity = nil
        return nil
    }
}
