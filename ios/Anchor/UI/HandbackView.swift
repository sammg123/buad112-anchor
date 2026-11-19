import SwiftUI

/// The cover handed back with a red grade on it.
struct HandbackView: View {
    @Environment(AppModel.self) private var model
    let session: Session

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.spacing * 3) {
                VStack(alignment: .leading, spacing: Theme.spacing) {
                    Text(session.isComplete ? "TIME. PENS DOWN." : "STOPPED EARLY")
                        .font(.caption.weight(.bold)).tracking(2).foregroundStyle(Theme.inkSoft)
                    Text(session.config.courseName).font(Theme.lettering(56)).foregroundStyle(Theme.ink)
                }
                gradeBox
                VStack(spacing: 12) {
                    stat("Studied", Format.clock(session.studiedSeconds), red: false)
                    stat("On your phone", Format.clock(session.phoneSeconds), red: true)
                    stat("Tuition scrolled away", Format.money(session.costDollars), red: true)
                    stat("Pickups", "\(session.pickups)", red: true)
                    stat("Away from your spot", Format.clock(session.awaySeconds), red: false)
                }
                .padding(16)
                .background(Theme.paper, in: RoundedRectangle(cornerRadius: 10))
                Button("New session") { model.startOver() }
                    .buttonStyle(InkButtonStyle())
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 32)
        }
        .background(Theme.cover.ignoresSafeArea())
    }

    private var gradeBox: some View {
        let grade = Grade.letter(studied: session.studiedSeconds, phone: session.phoneSeconds)
        return HStack(spacing: 20) {
            Text(grade)
                .font(Theme.hand(72, relativeTo: .largeTitle))
                .foregroundStyle(Theme.pen)
                .frame(width: 120, height: 120)
                .background(Theme.paper)
                .overlay(Rectangle().stroke(Theme.ink, lineWidth: 2))
                .accessibilityLabel("Grade \(grade)")
            Text(comment(grade)).font(Theme.hand(22)).foregroundStyle(Theme.pen)
        }
    }

    private func comment(_ grade: String) -> String {
        switch grade {
        case "A+": "Didn't touch it. Impressive."
        case "A": "Barely looked. Nice."
        case "B": "Good, but you peeked."
        case "C": "The phone got a lot of this."
        case "D": "Your phone studied more than you."
        case "F": "See me after class."
        default: "Nothing to grade yet."
        }
    }

    private func stat(_ label: String, _ value: String, red: Bool) -> some View {
        HStack {
            Text(label).font(.subheadline).foregroundStyle(Theme.pencil)
            Spacer()
            Text(value).font(red ? Theme.hand(20) : Theme.timer(20)).foregroundStyle(red ? Theme.pen : Theme.ink)
        }
        .accessibilityElement(children: .combine)
    }
}
