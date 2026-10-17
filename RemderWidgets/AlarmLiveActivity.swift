import ActivityKit
import AlarmKit
import SwiftUI
import WidgetKit

/// Shown by the system while a reminder's alarm is snoozed: a countdown until it rings again.
struct AlarmLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: AlarmAttributes<ReminderAlarmMetadata>.self) { context in
            AlarmLockScreenView(context: context)
        } dynamicIsland: { context in
            let tint = context.attributes.tintColor
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: "alarm.fill")
                        .font(.title2)
                        .foregroundStyle(tint)
                        .padding(.leading, 6)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    AlarmTimeText(mode: context.state.mode)
                        .font(.system(size: 28, weight: .heavy, design: .rounded))
                        .foregroundStyle(tint)
                        .frame(maxWidth: 120, alignment: .trailing)
                        .padding(.trailing, 6)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text(context.attributes.metadata?.title ?? "Reminder")
                        .font(.headline)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 6)
                }
            } compactLeading: {
                Image(systemName: "alarm.fill").foregroundStyle(tint)
            } compactTrailing: {
                AlarmTimeText(mode: context.state.mode)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(tint)
                    .frame(maxWidth: 52)
            } minimal: {
                Image(systemName: "alarm.fill").foregroundStyle(tint)
            }
        }
    }
}

private struct AlarmLockScreenView: View {
    @Environment(\.colorScheme) private var colorScheme
    let context: ActivityViewContext<AlarmAttributes<ReminderAlarmMetadata>>

    var body: some View {
        let primary: Color = colorScheme == .dark ? .white : .black
        HStack(spacing: 14) {
            Image(systemName: "alarm.fill")
                .font(.title2)
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(context.attributes.tintColor.gradient, in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text("Snoozed")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(primary.opacity(0.6))
                Text(context.attributes.metadata?.title ?? "Reminder")
                    .font(.headline)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            AlarmTimeText(mode: context.state.mode)
                .font(.system(size: 34, weight: .heavy, design: .rounded))
                .frame(maxWidth: 130, alignment: .trailing)
        }
        .foregroundStyle(primary)
        .padding(16)
        .activityBackgroundTint(colorScheme == .dark ? .black : .white)
        .activitySystemActionForegroundColor(primary)
    }
}

private struct AlarmTimeText: View {
    let mode: AlarmPresentationState.Mode

    var body: some View {
        switch mode {
        case .countdown(let countdown):
            Text(timerInterval: Date.now...max(Date.now, countdown.fireDate), countsDown: true)
                .monospacedDigit()
                .multilineTextAlignment(.trailing)
        case .paused:
            Text("Paused")
        case .alert:
            Text("Now")
        @unknown default:
            Text("")
        }
    }
}
