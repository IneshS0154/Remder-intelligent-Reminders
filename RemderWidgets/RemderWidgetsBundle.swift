import SwiftUI
import WidgetKit

@main
struct RemderWidgetsBundle: WidgetBundle {
    var body: some Widget {
        UpcomingWidget()
        ReminderLiveActivity()
        AlarmLiveActivity()
    }
}
