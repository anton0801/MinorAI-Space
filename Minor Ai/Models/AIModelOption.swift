//
//  AIModelOption.swift
//  Minor Ai
//

import Foundation

enum AIProviderKind {
    case anthropic
    case openai
}

// Model class, from the lightest to the strongest.
enum ModelTier: Int, Comparable {
    case lite, standard, advanced, frontier

    static func < (lhs: ModelTier, rhs: ModelTier) -> Bool { lhs.rawValue < rhs.rawValue }
}

struct AIModelOption: Identifiable, Hashable {
    let id: String          // display name, also used as the menu key
    let displayName: String
    let provider: AIProviderKind
    let apiModelID: String  // the exact string sent to the provider's API
    let tier: ModelTier
    // How much of the monthly AI allowance a typical message uses, relative to the lightest model.
    let usage: Int

    init(displayName: String, provider: AIProviderKind, apiModelID: String, tier: ModelTier, usage: Int) {
        self.id = displayName
        self.displayName = displayName
        self.provider = provider
        self.apiModelID = apiModelID
        self.tier = tier
        self.usage = usage
    }
}

// The chat model catalog, the same ids and prices as the server (supabase/functions/_shared/models.ts).
// Every plan may chat with every model: stronger models simply use the monthly AI allowance faster.
enum AIModelCatalog {
    static let all: [AIModelOption] = [
        AIModelOption(displayName: "GPT-6 Luna", provider: .openai, apiModelID: "gpt-6-luna", tier: .lite, usage: 1),
        AIModelOption(displayName: "Claude Haiku 4.5", provider: .anthropic, apiModelID: "claude-haiku-4-5-20251001", tier: .lite, usage: 10),
        AIModelOption(displayName: "GPT-6.1 Sol", provider: .openai, apiModelID: "gpt-6.1-sol", tier: .standard, usage: 20),
        AIModelOption(displayName: "Claude Sonnet 5.5", provider: .anthropic, apiModelID: "claude-sonnet-5-5", tier: .standard, usage: 25),
        AIModelOption(displayName: "Claude Opus 5.5", provider: .anthropic, apiModelID: "claude-opus-5-5", tier: .advanced, usage: 50),
        AIModelOption(displayName: "GPT-6 Astra", provider: .openai, apiModelID: "gpt-6-astra", tier: .frontier, usage: 100),
        AIModelOption(displayName: "Claude Fable 5.1", provider: .anthropic, apiModelID: "claude-fable-5-1", tier: .frontier, usage: 130),
    ]

    // The lightest model: lets free plans chat the longest.
    static let `default` = all.first(where: { $0.apiModelID == "gpt-6-luna" }) ?? all[0]

    static func option(apiID: String?) -> AIModelOption? {
        all.first { $0.apiModelID == apiID }
    }
}

extension AIModelOption {
    // Plan needed to build maps with this model: standard models for everyone, Claude Opus with
    // Plus, the frontier models with PRO. Lite models aren't used for maps.
    var mapPlan: AccountStore.Plan {
        switch tier {
        case .lite, .standard: return .free
        case .advanced: return .plus
        case .frontier: return .pro
        }
    }
}

extension AIModelCatalog {
    static var mapModels: [AIModelOption] { all.filter { $0.tier >= .standard } }

    // Default map model: the standard one the server prefers.
    static let defaultMap = all.first(where: { $0.apiModelID == "gpt-6.1-sol" }) ?? all[0]
}
