import SwiftData
import SwiftUI

enum AppSection: String, CaseIterable, Identifiable {
    case reminders, notes, insights, settings, about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .reminders: return "Reminders"
        case .notes: return "Notes"
        case .insights: return "Insights"
        case .settings: return "Settings"
        case .about: return "About"
        }
    }

    var icon: String {
        switch self {
        case .reminders: return "bell"
        case .notes: return "note.text"
        case .insights: return "flame"
        case .settings: return "gearshape"
        case .about: return "info.circle"
        }
    }
}

/// App-wide navigation state shared by the sidebar and the screens it switches between.
@Observable
final class AppNavigation {
    var section: AppSection = .reminders
    /// Category the reminder lists are filtered to; nil shows every reminder.
    var selectedCategory: String?
    var isSidebarOpen = false
    /// True while a screen is pushed inside a section (e.g. Settings › Sound), so the
    /// left-edge swipe goes back instead of opening the sidebar.
    var isShowingDetail = false
}

/// Hosts the current section and the slide-in sidebar used to switch between sections.
struct RootView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @State private var navigation = AppNavigation()
    @State private var appLock = AppLock.shared
    @Query private var reminders: [Reminder]
    private static let slide = Animation.spring(duration: 0.4, bounce: 0.12)

    /// Horizontal finger movement while dragging the open sidebar closed.
    @GestureState(resetTransaction: Transaction(animation: slide)) private var closeTranslation: CGFloat = 0
    /// Horizontal finger movement while swiping in from the left edge to open the sidebar.
    @State private var openTranslation: CGFloat = 0

    private let sidebarWidth: CGFloat = 300

    /// 0 = closed, 1 = fully open; follows the finger while dragging.
    private var progress: CGFloat {
        let value = navigation.isSidebarOpen
            ? 1 + min(0, closeTranslation) / sidebarWidth
            : openTranslation / sidebarWidth
        return min(1, max(0, value))
    }

    var body: some View {
        ZStack {
            if appLock.isLocked {
                LockView(appLock: appLock)
                    .transition(.opacity)
            } else {
                mainContent
            }

            if appLock.isEnabled, scenePhase != .active, !appLock.isAuthenticating {
                PrivacyCover()
            }
        }
        .onChange(of: scenePhase) { appLock.scenePhaseChanged(to: scenePhase) }
        .task { CategoryStore.seedIfNeeded(modelContext) }
        // Keep notifications and countdowns in sync whenever the app comes forward,
        // even while the app lock is showing.
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            await SyncEngine.shared.syncNow()
            await NotificationManager.shared.requestAuthorizationIfNeeded()
            await NotificationManager.shared.resync(reminders: reminders)
        }
    }

    private var mainContent: some View {
        ZStack(alignment: .leading) {
            content
                .environment(navigation)

            Color.black
                .opacity(0.3 * progress)
                .ignoresSafeArea()
                .allowsHitTesting(navigation.isSidebarOpen)
                .onTapGesture { setSidebar(open: false) }

            SidebarView(navigation: navigation, close: { setSidebar(open: false) })
                .frame(width: sidebarWidth)
                .shadow(color: .black.opacity(0.18 * progress), radius: 16, x: 6)
                .offset(x: (progress - 1) * (sidebarWidth + 24))
                .allowsHitTesting(navigation.isSidebarOpen)
        }
        .gesture(closeDrag, including: navigation.isSidebarOpen ? .all : .subviews)
        .gesture(
            LeadingEdgePan(isEnabled: !navigation.isSidebarOpen && !navigation.isShowingDetail) { translation in
                openTranslation = max(0, translation)
            } onEnd: { translation, velocity in
                let shouldOpen = translation > sidebarWidth / 3 || velocity > 500
                withAnimation(Self.slide) {
                    navigation.isSidebarOpen = shouldOpen
                    openTranslation = 0
                }
            }
        )
        .onChange(of: DeepLinkRouter.shared.pendingReminderID) {
            // A reminder fired or its notification was tapped: show it on the Reminders screen.
            if DeepLinkRouter.shared.pendingReminderID != nil {
                navigation.section = .reminders
                setSidebar(open: false)
            }
        }
        .onChange(of: navigation.isSidebarOpen) { _, isOpen in
            if isOpen { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch navigation.section {
        case .reminders: RemindersView()
        case .notes: NotesView()
        case .insights: InsightsView()
        case .settings: SettingsView()
        case .about: AboutView()
        }
    }

    private var closeDrag: some Gesture {
        DragGesture(minimumDistance: 10)
            .updating($closeTranslation, body: { value, state, transaction in
                state = value.translation.width
                transaction.animation = .interactiveSpring
            })
            .onEnded { value in
                let predicted = value.predictedEndTranslation.width
                if value.translation.width < -sidebarWidth / 3 || predicted < -sidebarWidth / 2 {
                    setSidebar(open: false)
                }
            }
    }

    private func setSidebar(open: Bool) {
        withAnimation(Self.slide) { navigation.isSidebarOpen = open }
    }
}

/// Swipe in from the screen's left edge. Uses UIKit's edge-pan recognizer so it doesn't
/// swallow taps or fight with scrolling the way a SwiftUI drag over the content would.
private struct LeadingEdgePan: UIGestureRecognizerRepresentable {
    var isEnabled: Bool
    var onChange: (CGFloat) -> Void
    /// Final horizontal translation and velocity (points per second).
    var onEnd: (CGFloat, CGFloat) -> Void

    func makeUIGestureRecognizer(context: Context) -> UIScreenEdgePanGestureRecognizer {
        let recognizer = UIScreenEdgePanGestureRecognizer()
        recognizer.edges = .left
        return recognizer
    }

    func updateUIGestureRecognizer(_ recognizer: UIScreenEdgePanGestureRecognizer, context: Context) {
        recognizer.isEnabled = isEnabled
    }

    func handleUIGestureRecognizerAction(_ recognizer: UIScreenEdgePanGestureRecognizer, context: Context) {
        let view = recognizer.view
        switch recognizer.state {
        case .began, .changed:
            onChange(recognizer.translation(in: view).x)
        case .ended:
            onEnd(recognizer.translation(in: view).x, recognizer.velocity(in: view).x)
        case .cancelled, .failed:
            onEnd(0, 0)
        default:
            break
        }
    }
}

extension View {
    /// Top bar shared by every section: menu button and title on the left, in line with trailing buttons.
    func sectionNavigationBar(title: String) -> some View {
        navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(removing: .title)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    SidebarButton()
                }
                ToolbarItem(placement: .topBarLeading) {
                    Text(title)
                        .font(.title.bold())
                        .lineLimit(1)
                        .fixedSize()
                }
                .sharedBackgroundVisibility(.hidden)
            }
    }
}

struct SidebarButton: View {
    @Environment(AppNavigation.self) private var navigation

    var body: some View {
        Button {
            withAnimation(.spring(duration: 0.4, bounce: 0.12)) { navigation.isSidebarOpen = true }
        } label: {
            Image(systemName: "line.3.horizontal")
        }
        .accessibilityLabel("Menu")
    }
}
