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

    public static func phasedEscapeQuotes(personality: PetPersonality, language: AppState.AppLanguage, current: Int, target: Int) -> String {
        let typeStr: String
        switch personality {
        case .gentle: typeStr = "gentle"
        case .strict: typeStr = "strict"
        case .tsundere: typeStr = "tsundere"
        }

        if current >= target {
            return I18n.localized("phased_escape_giveup_\(typeStr)", language: language)
        } else {
            // Use variation if available
            let key = "phased_escape_\(typeStr)_\(current)"
            let localized = I18n.localized(key, language: language)
            if localized != key {
                return String(format: localized, Int64(current), Int64(target))
            }
            return I18n.localizedFormat("phased_escape_\(typeStr)", language: language, Int64(current), Int64(target))
        }
    }

    public static func tapHintText(personality: PetPersonality, language: AppState.AppLanguage = .system, targetCount: Int = 3) -> String {
        let typeStr: String
        switch personality {
        case .gentle: typeStr = "gentle"
        case .strict: typeStr = "strict"
        case .tsundere: typeStr = "tsundere"
        }
        let format = I18n.localized("tap_hint_\(typeStr)", language: language)
        return String(format: format, Int64(targetCount))
    }
}
