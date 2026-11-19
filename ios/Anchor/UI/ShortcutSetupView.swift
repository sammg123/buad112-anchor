import SwiftUI

/// iOS lets no app switch the screen to black and white, so the student makes two tiny shortcuts once.
struct ShortcutSetupView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("iOS doesn't let apps turn your screen gray, so Anchor uses two one-step shortcuts. You make them once.")
                        .font(.callout).foregroundStyle(Theme.inkSoft)
                    step("1", "Settings › Accessibility › Display & Text Size › Color Filters. Pick **Grayscale**, then turn Color Filters back **off**.")
                    step("2", "Open **Shortcuts**, tap **+**, add the action **Set Color Filters**, set it to **On**. Name it exactly **Anchor Gray**.")
                    step("3", "Make one more: **Set Color Filters** to **Off**, named exactly **Anchor Color**.")
                    step("4", "Test both below. The first time, Shortcuts may ask to allow Anchor. Tap **Always Allow**.")
                    HStack(spacing: 12) {
                        Button("Test gray") { model.runShortcut(.gray) }.buttonStyle(InkButtonStyle())
                        Button("Test color") { model.runShortcut(.color) }.buttonStyle(InkButtonStyle(outline: true))
                    }
                    Button("Open Shortcuts") {
                        if let url = URL(string: "shortcuts://") { UIApplication.shared.open(url) }
                    }
                    .buttonStyle(InkButtonStyle(outline: true))
                }
                .padding(24)
            }
            .background(Theme.paper.ignoresSafeArea())
            .navigationTitle("Black and white")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }

    private func step(_ number: String, _ text: LocalizedStringKey) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(number).font(Theme.hand(22)).foregroundStyle(Theme.pen)
            Text(text).font(.body).foregroundStyle(Theme.ink)
        }
    }
}
