//
//  LLMConfiguration.swift
//  Jared
//

import Foundation

struct LLMConfiguration: Decodable {
    let provider: String
    let apiKey: String
    let model: String
    let systemPrompt: String
    let rateLimitSeconds: Double

    init(provider: String = "openai",
         apiKey: String,
         model: String = "gpt-4o",
         systemPrompt: String = "You are a helpful assistant.",
         rateLimitSeconds: Double = 10.0) {
        self.provider = provider
        self.apiKey = apiKey
        self.model = model
        self.systemPrompt = systemPrompt
        self.rateLimitSeconds = rateLimitSeconds
    }
}
