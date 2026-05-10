import SwiftUI
import WidgetKit
import ActivityKit

@main
struct MileageTrackerWidgetBundle: WidgetBundle {
    var body: some Widget {
        MileageTrackerLiveActivity()
    }
}

struct MileageTrackerLiveActivity: Widget {
    let kind = "MileageTrackerLiveActivity"

    var body: some WidgetConfiguration {
        ActivityConfiguration(for: TripActivityAttributes.self) { context in
            HStack(alignment: .center, spacing: 16) {
                VStack(spacing: 4) {
                    Image(systemName: "car.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(.green)
                    Text("Recording")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(context.state.durationDisplay)
                        .font(.system(size: 28, weight: .bold, design: .monospaced))
                    Text(context.state.distanceDisplay)
                        .font(.system(size: 18, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.green)
                }
                Spacer()
                if !context.attributes.vehicleName.isEmpty {
                    Text(context.attributes.vehicleName)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .frame(width: 60, alignment: .trailing)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .activityBackgroundTint(.black.opacity(0.3))
            .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 4) {
                        Image(systemName: "car.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(.green)
                        Text(context.state.durationDisplay)
                            .font(.system(size: 18, weight: .semibold, design: .monospaced))
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.state.distanceDisplay)
                        .font(.system(size: 18, weight: .semibold, design: .monospaced))
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.attributes.vehicleName.isEmpty ? "Recording" : context.attributes.vehicleName)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        Circle().fill(.green).frame(width: 6, height: 6)
                        Text("Trip in progress").font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                }
            } compactLeading: {
                Image(systemName: "car.fill").foregroundStyle(.green)
            } compactTrailing: {
                Text(context.state.durationDisplay)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .frame(maxWidth: 48)
            } minimal: {
                Image(systemName: "car.fill").foregroundStyle(.green)
            }
        }
    }
}
