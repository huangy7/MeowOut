import Foundation
import MemosKit

enum MemosCollectionMode: Equatable, Sendable {
    case normal
    case archived

    var title: String {
        switch self {
        case .normal:
            return "Memos"
        case .archived:
            return I18n.localized("memos_action_archive")
        }
    }

    var sectionTitle: String {
        switch self {
        case .normal:
            return I18n.localized("memos_category_recent")
        case .archived:
            return I18n.localized("memos_category_archived")
        }
    }

    var emptyTitle: String {
        switch self {
        case .normal:
            return I18n.localized("memos_empty_state_normal")
        case .archived:
            return I18n.localized("memos_empty_state_archived")
        }
    }

    var memoState: MemoState {
        switch self {
        case .normal:
            return .normal
        case .archived:
            return .archived
        }
    }

    var showsCreateButton: Bool {
        self == .normal
    }

    var allowsEditing: Bool {
        self == .normal
    }

    var allowsArchiving: Bool {
        self == .normal
    }

    var allowsRestoring: Bool {
        self == .archived
    }
}
