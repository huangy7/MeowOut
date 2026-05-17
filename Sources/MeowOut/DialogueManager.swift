// Sources/MeowOut/DialogueManager.swift
import Foundation

struct DialoguePack {
    let alerting: [String]
    let resting: [String]
    let keyboardScold: String
    let trayScold: String
    let tapQuotes: [String]
}

final class DialogueManager {
    static func pack(for personality: PetPersonality, language: AppState.AppLanguage = .system) -> DialoguePack {
        let typeStr: String
        switch personality {
        case .gentle: typeStr = "gentle"
        case .strict: typeStr = "strict"
        case .tsundere: typeStr = "tsundere"
        }

        return DialoguePack(
            alerting: [
                I18n.localized("personality_\(typeStr)_alerting_0", language: language),
                I18n.localized("personality_\(typeStr)_alerting_1", language: language),
                I18n.localized("personality_\(typeStr)_alerting_2", language: language)
            ],
            resting: [
                I18n.localized("personality_\(typeStr)_resting_0", language: language),
                I18n.localized("personality_\(typeStr)_resting_1", language: language),
                I18n.localized("personality_\(typeStr)_resting_2", language: language)
            ],
            keyboardScold: I18n.localized("personality_\(typeStr)_keyboardScold", language: language),
            trayScold: I18n.localized("personality_\(typeStr)_trayScold", language: language),
            tapQuotes: [
                I18n.localized("personality_\(typeStr)_tap_0", language: language),
                I18n.localized("personality_\(typeStr)_tap_1", language: language),
                I18n.localized("personality_\(typeStr)_tap_2", language: language)
            ]
        )
    }
}
