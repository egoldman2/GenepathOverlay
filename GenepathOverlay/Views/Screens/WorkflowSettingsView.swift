import SwiftUI

struct WorkflowSettingsView: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                AppSetupCard {
                    Button {
                        appModel.beginWorkflow()
                    } label: {
                        Label("Back", systemImage: "chevron.left")
                    }
                    .buttonStyle(.bordered)

                    PageEyebrow(title: "Settings")

                    Text("Workflow settings")
                        .font(.system(size: 34, weight: .bold, design: .rounded))

                    Text("Tracking and alignment tools for guided transfer mode.")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    TrackingCardView()
                }
            }
        }
        .foregroundStyle(AppUIStyle.primaryTextColor)
        .preferredColorScheme(.dark)
    }
}
