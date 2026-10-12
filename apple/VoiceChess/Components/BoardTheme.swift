import SwiftUI

/// Board colour schemes, matching the Windows app.
enum BoardTheme: String, CaseIterable, Identifiable {
    case brown, blue, green, purple, grey, contrast

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .brown: "Brown"
        case .blue: "Blue"
        case .green: "Green"
        case .purple: "Purple"
        case .grey: "Grey"
        case .contrast: "High contrast"
        }
    }

    var light: Color {
        switch self {
        case .brown: Color(red: 0.941, green: 0.851, blue: 0.710)
        case .blue: Color(red: 0.871, green: 0.890, blue: 0.902)
        case .green: Color(red: 1.0, green: 1.0, blue: 0.867)
        case .purple: Color(red: 0.902, green: 0.863, blue: 0.941)
        case .grey: Color(red: 0.863, green: 0.863, blue: 0.863)
        case .contrast: .white
        }
    }

    var dark: Color {
        switch self {
        case .brown: Color(red: 0.710, green: 0.533, blue: 0.388)
        case .blue: Color(red: 0.549, green: 0.635, blue: 0.678)
        case .green: Color(red: 0.525, green: 0.651, blue: 0.400)
        case .purple: Color(red: 0.612, green: 0.498, blue: 0.722)
        case .grey: Color(red: 0.604, green: 0.604, blue: 0.604)
        case .contrast: Color(red: 0.373, green: 0.420, blue: 0.478)
        }
    }

    var lastMove: Color {
        self == .contrast ? Color(red: 1.0, green: 0.77, blue: 0.0).opacity(0.55) : Color(red: 0.61, green: 0.78, blue: 0.0).opacity(0.42)
    }
}
