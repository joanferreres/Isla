/// Model IDs used by Isla's AI features. Change them here, in one place.
enum AIModels {
    /// Auto-EQ must stay on the cheapest Claude tier (Haiku). Never Sonnet/Opus — token burn for a JSON EQ tip.
    static let claudeEQ = "claude-haiku-4-5-20251001"
    /// Fallback when there is no Anthropic API key — also the cheap OpenAI tier.
    static let openAIEQ = "gpt-4o-mini"
}
