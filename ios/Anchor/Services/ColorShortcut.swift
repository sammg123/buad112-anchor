import Foundation

/// iOS gives apps no way to turn the screen black and white. Two one-step shortcuts the student makes once
/// ("Set Color Filters" on / off) do it, and Anchor runs them through the Shortcuts URL scheme.
enum ColorShortcut: Sendable {
    case gray
    case color

    var name: String {
        switch self {
        case .gray: "Anchor Gray"
        case .color: "Anchor Color"
        }
    }

    /// Shortcuts opens, runs it, and comes straight back to Anchor.
    var url: URL? {
        var parts = URLComponents()
        parts.scheme = "shortcuts"
        parts.host = "x-callback-url"
        parts.path = "/run-shortcut"
        parts.queryItems = [
            URLQueryItem(name: "name", value: name),
            URLQueryItem(name: "x-success", value: "anchorstudy://back"),
            URLQueryItem(name: "x-error", value: "anchorstudy://back"),
            URLQueryItem(name: "x-cancel", value: "anchorstudy://back")
        ]
        return parts.url
    }

    /// While the trip to Shortcuts and back is under way, leaving Anchor is not "going on your phone".
    static let graceSeconds = 10.0
}
