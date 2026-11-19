import SwiftUI

/// The book's cover: fill in the blanks, then drop the anchor where you sit.
struct CoverView: View {
    @Environment(AppModel.self) private var model
    @State private var course = SetupInput.defaultCourse
    @State private var minutes = "25"
    @State private var tuition = ""
    @State private var grayscale = false
    @State private var showingShortcutSetup = false
    @State private var error: String?
    @FocusState private var focused: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.spacing * 3) {
                header
                VStack(spacing: Theme.spacing * 2) {
                    Blank(label: "Course", text: $course, keyboard: .default)
                    Blank(label: "Minutes", text: $minutes, keyboard: .numberPad)
                    Blank(label: "Yearly tuition", text: $tuition, keyboard: .numberPad, placeholder: "$")
                }
                .focused($focused)
                grayscaleRow
                PermissionChecklist()
                rules
                startButton
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 32)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Theme.cover.ignoresSafeArea())
        .sheet(isPresented: $showingShortcutSetup) { ShortcutSetupView() }
        .onAppear(perform: prefill)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { focused = false }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Theme.spacing) {
            Text("EXAMINATION BOOK")
                .font(.caption.weight(.bold))
                .tracking(2)
                .foregroundStyle(Theme.inkSoft)
            Text("ANCHOR")
                .font(Theme.lettering(84))
                .foregroundStyle(Theme.ink)
                .accessibilityAddTraits(.isHeader)
            Text("A study timer you can't quietly quit. Pick up your phone at your spot and it buzzes every 15 seconds until you put it down.")
                .font(.callout)
                .foregroundStyle(Theme.inkSoft)
        }
    }

    private var grayscaleRow: some View {
        VStack(alignment: .leading, spacing: Theme.spacing) {
            Toggle(isOn: $grayscale) {
                Text("Black and white while studying").font(.headline).foregroundStyle(Theme.ink)
            }
            .tint(Theme.ink)
            Button("Set up black and white (one time, 2 min)") { showingShortcutSetup = true }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.ink)
                .underline()
        }
    }

    private var rules: some View {
        VStack(alignment: .leading, spacing: Theme.spacing) {
            Text("RULES").font(.caption.weight(.bold)).tracking(2).foregroundStyle(Theme.pencil)
            rule("1", "Your spot is where you press start.")
            rule("2", "Unlock your phone there and it buzzes every 15 s. The study timer freezes.")
            rule("3", "Stop stays locked until you walk about 50 m away. Away, your phone is free.")
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.paper, in: RoundedRectangle(cornerRadius: 10))
    }

    private func rule(_ number: String, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(number).font(Theme.hand(18)).foregroundStyle(Theme.pen)
            Text(text).font(.subheadline).foregroundStyle(Theme.ink)
        }
    }

    private var startButton: some View {
        VStack(spacing: Theme.spacing) {
            if let error {
                Text(error).font(.footnote.weight(.semibold)).foregroundStyle(Theme.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if model.isFindingSpot {
                FindingSpot()
            } else {
                Button(action: start) {
                    Label("Drop anchor here", systemImage: "mappin.and.ellipse")
                }
                .buttonStyle(InkButtonStyle())
            }
        }
    }

    private func prefill() {
        guard let config = model.lastConfig else { return }
        course = config.courseName
        minutes = String(config.studyMinutes)
        tuition = config.tuitionPerYear > 0 ? String(Int(config.tuitionPerYear)) : ""
        grayscale = config.grayscale
    }

    private func start() {
        focused = false
        guard let mins = SetupInput.minutes(minutes) else {
            error = "Minutes: pick 1 to \(SetupInput.maxMinutes)."
            return
        }
        guard let money = SetupInput.tuition(tuition) else {
            error = "Tuition: a yearly amount up to $500,000, or leave it empty."
            return
        }
        error = nil
        model.start(SessionConfig(courseName: SetupInput.course(course), studyMinutes: mins,
                                  tuitionPerYear: money, grayscale: grayscale))
    }
}

/// A printed label with an underlined blank, like "Name ______".
private struct Blank: View {
    let label: String
    @Binding var text: String
    let keyboard: UIKeyboardType
    var placeholder = ""

    var body: some View {
        HStack(alignment: .lastTextBaseline, spacing: 12) {
            Text(label)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.inkSoft)
                .frame(width: 112, alignment: .leading)
            VStack(spacing: 2) {
                TextField(placeholder, text: $text)
                    .font(Theme.hand(24))
                    .foregroundStyle(Theme.ink)
                    .keyboardType(keyboard)
                    .textInputAutocapitalization(.words)
                    .accessibilityLabel(label)
                Rectangle().fill(Theme.ink).frame(height: 1.5)
            }
        }
    }
}

private struct FindingSpot: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: Theme.spacing) {
            HStack(spacing: 10) {
                ProgressView().tint(Theme.ink)
                Text(accuracyText).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ink)
            }
            Button("Cancel") { model.cancelFindingSpot() }
                .buttonStyle(InkButtonStyle(outline: true))
        }
    }

    private var accuracyText: String {
        guard let fix = model.fix, fix.horizontalAccuracy >= 0 else { return "Finding your spot…" }
        return "Finding your spot… GPS is within \(Format.meters(fix.horizontalAccuracy)). Step near a window if this sticks."
    }
}
