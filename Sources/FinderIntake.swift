import Foundation

enum FinderIntakeMode: String, CaseIterable, Identifiable {
    case unmanaged
    case binding

    var id: String { rawValue }

    var title: String {
        switch self {
        case .unmanaged: return "Unmanaged"
        case .binding: return "Binding"
        }
    }
}

struct FinderIntake: Identifiable {
    let id = UUID()
    let urls: [URL]
    var mode: FinderIntakeMode
}
