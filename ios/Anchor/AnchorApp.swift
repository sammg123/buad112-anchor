import SwiftUI
import UserNotifications

@main
struct AnchorApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var model = AppModel()
    private let presenter = NotificationPresenter()

    init() {
        UNUserNotificationCenter.current().delegate = presenter
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                // Pulling down Control Center over Anchor is not "on your phone"; only leaving Anchor is.
                .onChange(of: scenePhase, initial: true) { _, phase in model.setAppActive(phase != .background) }
                .onOpenURL { _ in }
        }
    }
}

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Group {
            switch model.screen {
            case .permissions: PermissionsView()
            case .start: StartView()
            case .session: SessionView()
            case .done:
                if let finished = model.finished { DoneView(session: finished) }
            }
        }
        .animation(.smooth(duration: 0.35), value: model.screen)
        .preferredColorScheme(.light)
        .alert("Anchor", isPresented: Binding(get: { model.notice != nil }, set: { if !$0 { model.notice = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.notice ?? "")
        }
    }
}
