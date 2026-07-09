//
//  NotificationIslandWidgetBundle.swift
//  NotificationIslandWidget
//

import ActivityKit
import SwiftUI
import WidgetKit

@main
struct NotificationIslandWidgetBundle: WidgetBundle {
    var body: some Widget {
        NotificationIslandLiveActivityWidget()
    }
}

struct NotificationIslandLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: NotificationIslandActivityAttributes.self) { context in
            if context.state.isVisible {
                NotificationIslandLockScreenView(context: context)
                    .activityBackgroundTint(Color.black.opacity(0.88))
                    .activitySystemActionForegroundColor(.white)
            } else {
                EmptyView()
            }
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    if context.state.isVisible {
                        Label {
                            Text(context.state.source)
                                .font(.caption2.weight(.semibold))
                                .lineLimit(1)
                        } icon: {
                            Image(systemName: "bell.fill")
                        }
                    }
                }

                DynamicIslandExpandedRegion(.trailing) {
                    if context.state.isVisible {
                        Text("Now")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                }

                DynamicIslandExpandedRegion(.bottom) {
                    if context.state.isVisible {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(context.state.title)
                                .font(.caption.weight(.semibold))
                                .lineLimit(1)
                            if !context.state.body.isEmpty {
                                Text(context.state.body)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.8)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            } compactLeading: {
                if context.state.isVisible {
                    Image(systemName: "bell.fill")
                } else {
                    EmptyView()
                }
            } compactTrailing: {
                if context.state.isVisible {
                    Text(compactText(for: context.state))
                        .font(.caption2.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                } else {
                    EmptyView()
                }
            } minimal: {
                if context.state.isVisible {
                    Image(systemName: "bell.fill")
                } else {
                    EmptyView()
                }
            }
            .keylineTint(.orange)
        }
    }

    private func compactText(for state: NotificationIslandActivityAttributes.ContentState) -> String {
        if state.source.count <= 8 { return state.source }
        return String(state.source.prefix(7)) + "..."
    }
}

private struct NotificationIslandLockScreenView: View {
    let context: ActivityViewContext<NotificationIslandActivityAttributes>

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "bell.fill")
                .font(.headline)
                .foregroundStyle(.orange)
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 3) {
                Text(context.state.source)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(context.state.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                if !context.state.body.isEmpty {
                    Text(context.state.body)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
    }
}
