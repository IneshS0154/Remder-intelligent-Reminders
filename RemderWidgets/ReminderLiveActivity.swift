import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

struct ReminderLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ReminderActivityAttributes.self) { context in
            let style = ActivityStyle(context: context)
            LockScreenView(context: context, style: style)
        } dynamicIsland: { context in
            let style = ActivityStyle(context: context)
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    BellBadge(style: style, size: 44)
                        .padding(.leading, 4)
                        .padding(.top, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Countdown(style: style, fontSize: 30)
                        .frame(maxWidth: 120, alignment: .trailing)
                        .padding(.trailing, 4)
                        .padding(.top, 4)
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(context.attributes.title)
                            .font(.headline)
                            .lineLimit(1)
                        DueLabel(style: style)
                            .foregroundStyle(.white.opacity(0.7))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 4)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack(spacing: 12) {
                        ProgressBar(style: style, trackColor: .white.opacity(0.2))
                            .tint(style.colors.first)
                        DoneButton(reminderID: context.attributes.reminderID, style: style, filled: true)
                    }
                    .padding(.horizontal, 4)
                    .padding(.top, 8)
                }
            } compactLeading: {
                Image(systemName: "bell.fill")
                    .foregroundStyle(style.colors.first!)
            } compactTrailing: {
                Countdown(style: style, fontSize: 14)
                    .frame(maxWidth: 52)
                    .foregroundStyle(style.colors.first!)
            } minimal: {
                ProgressRing(style: style)
            }
            .keylineTint(style.colors.first)
        }
    }
}

// MARK: - Style

/// Everything the views need, derived once from the activity context.
private struct ActivityStyle {
    let title: String
    let notes: String?
    let category: String?
    let reminderID: String
    let dueDate: Date
    let startDate: Date
    let isDue: Bool
    let colors: [Color]

    init(context: ActivityViewContext<ReminderActivityAttributes>) {
        title = context.attributes.title
        notes = context.attributes.notes
        category = context.attributes.category
        reminderID = context.attributes.reminderID
        dueDate = context.state.dueDate
        // Guard the range: progress needs start < due.
        startDate = min(context.state.startDate ?? dueDate.addingTimeInterval(-900), dueDate.addingTimeInterval(-1))
        isDue = context.isStale || dueDate <= .now

        switch context.attributes.priority {
        case 2: colors = [Color(red: 1.0, green: 0.45, blue: 0.24), Color(red: 0.89, green: 0.13, blue: 0.29)]
        case 0: colors = [Color(red: 0.2, green: 0.8, blue: 0.66), Color(red: 0.05, green: 0.55, blue: 0.55)]
        default: colors = [Color(red: 0.49, green: 0.47, blue: 1.0), Color(red: 0.31, green: 0.22, blue: 0.86)]
        }
    }

    var gradient: LinearGradient {
        LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

// MARK: - Lock Screen

private struct LockScreenView: View {
    @Environment(\.colorScheme) private var colorScheme
    let context: ActivityViewContext<ReminderActivityAttributes>
    let style: ActivityStyle

    /// Matches the system: a white card with black text in Light Mode, black with white in Dark Mode.
    private var background: Color { colorScheme == .dark ? .black : .white }
    private var primary: Color { colorScheme == .dark ? .white : .black }
    /// The priority color, used as an accent on the pill, progress and Done button.
    private var accent: Color { colorScheme == .dark ? style.colors.first! : style.colors.last! }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header: brand pill, category, due time.
            HStack(spacing: 8) {
                HStack(spacing: 5) {
                    Image(systemName: "bell.fill")
                        .font(.system(size: 10, weight: .bold))
                    Text("REMDER")
                        .font(.system(size: 11, weight: .heavy))
                        .tracking(1.2)
                }
                .foregroundStyle(accent)
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(accent.opacity(0.14), in: Capsule())

                if let category = style.category {
                    Text(category)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(primary.opacity(0.6))
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                DueLabel(style: style)
                    .foregroundStyle(primary.opacity(0.6))
            }

            // Title and the big countdown.
            HStack(alignment: .bottom, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(style.title)
                        .font(.title3.weight(.bold))
                        .lineLimit(2)
                        .minimumScaleFactor(0.85)
                    if let notes = style.notes, !notes.isEmpty {
                        Text(notes)
                            .font(.subheadline)
                            .foregroundStyle(primary.opacity(0.6))
                            .lineLimit(1)
                    } else {
                        Text(style.isDue ? "It's time" : "Coming up")
                            .font(.subheadline)
                            .foregroundStyle(primary.opacity(0.6))
                    }
                }

                Spacer(minLength: 8)

                Countdown(style: style, fontSize: 38)
                    .frame(maxWidth: 130, alignment: .trailing)
            }

            // Progress toward the due time, and Done.
            HStack(spacing: 14) {
                ProgressBar(style: style, trackColor: primary.opacity(0.1))
                    .tint(accent)
                DoneButton(reminderID: style.reminderID, style: style, filled: true)
            }
        }
        .foregroundStyle(primary)
        .padding(16)
        .activityBackgroundTint(background)
        .activitySystemActionForegroundColor(primary)
    }
}

// MARK: - Pieces

private struct BellBadge: View {
    let style: ActivityStyle
    let size: CGFloat

    var body: some View {
        Image(systemName: style.isDue ? "bell.and.waves.left.and.right.fill" : "bell.fill")
            .font(.system(size: size * 0.42, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(style.gradient, in: Circle())
    }
}

/// Counts down to the due time, then reads "Now".
private struct Countdown: View {
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced
    let style: ActivityStyle
    let fontSize: CGFloat

    var body: some View {
        Group {
            if style.isDue {
                Text("Now")
            } else if isLuminanceReduced {
                // The dimmed Lock Screen hides seconds ("23:--"); show whole minutes instead.
                Text(minutesLeft)
            } else {
                Text(timerInterval: Date.now...style.dueDate, countsDown: true)
                    .monospacedDigit()
            }
        }
        .font(.system(size: fontSize, weight: .heavy, design: .rounded))
        .multilineTextAlignment(.trailing)
        .minimumScaleFactor(0.6)
        .lineLimit(1)
    }

    private var minutesLeft: String {
        let minutes = max(1, Int(ceil(style.dueDate.timeIntervalSinceNow / 60)))
        return minutes >= 60 ? "\(minutes / 60)h \(minutes % 60)m" : "\(minutes) min"
    }
}

private struct DueLabel: View {
    let style: ActivityStyle

    var body: some View {
        Group {
            if style.isDue {
                Text("Due now")
            } else {
                Text("Due \(style.dueDate, format: .dateTime.hour().minute())")
            }
        }
        .font(.caption.weight(.semibold))
    }
}

/// Fills as the due time approaches; the system animates it without app updates.
private struct ProgressBar: View {
    let style: ActivityStyle
    let trackColor: Color

    var body: some View {
        Group {
            if style.isDue {
                ProgressView(value: 1)
            } else {
                ProgressView(timerInterval: style.startDate...style.dueDate, countsDown: false) {
                    EmptyView()
                } currentValueLabel: {
                    EmptyView()
                }
            }
        }
        .progressViewStyle(.linear)
        .background(Capsule().fill(trackColor).frame(height: 4))
    }
}

private struct ProgressRing: View {
    let style: ActivityStyle

    var body: some View {
        ZStack {
            if style.isDue {
                ProgressView(value: 1)
            } else {
                ProgressView(timerInterval: style.startDate...style.dueDate, countsDown: false) {
                    EmptyView()
                } currentValueLabel: {
                    EmptyView()
                }
            }
        }
        .progressViewStyle(.circular)
        .tint(style.colors.first)
        .overlay {
            Image(systemName: "bell.fill")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(style.colors.first!)
        }
    }
}

private struct DoneButton: View {
    let reminderID: String
    let style: ActivityStyle
    /// Filled uses the accent gradient (Dynamic Island); otherwise a white pill on the colored card.
    let filled: Bool

    var body: some View {
        Button(intent: CompleteReminderIntent(reminderID: reminderID)) {
            Label("Done", systemImage: "checkmark")
                .font(.caption.weight(.bold))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .foregroundStyle(filled ? AnyShapeStyle(.white) : AnyShapeStyle(style.colors.last!))
                .background(filled ? AnyShapeStyle(style.gradient) : AnyShapeStyle(.white), in: Capsule())
        }
        .buttonStyle(.plain)
    }
}
