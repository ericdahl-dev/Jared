//
//  LLMModule.swift
//  Jared
//

import Foundation
import JaredFramework

class LLMModule: RoutingModule {
    var description: String = "Routes unmatched messages to an LLM API and replies with the response."
    var routes: [Route] = []
    var sender: MessageSender

    private let config: LLMConfiguration
    private let session: URLSession
    private var lastRequestTime: [String: Date] = [:]
    private let lock = NSLock()

    required convenience init(sender: MessageSender) {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let configURL = appSupport.appendingPathComponent("Jared/config.json")
        var llmConfig: LLMConfiguration? = nil
        if let data = try? Data(contentsOf: configURL),
           let top = try? JSONDecoder().decode(TopLevelConfig.self, from: data) {
            llmConfig = top.llm
        }
        self.init(sender: sender, config: llmConfig ?? LLMConfiguration(apiKey: ""), session: .shared)
    }

    init(sender: MessageSender, config: LLMConfiguration, session: URLSession) {
        self.sender = sender
        self.config = config
        self.session = session

        let fallback = Route(
            name: "llm-fallback",
            comparisons: [.contains: [""]],
            call: { [weak self] in self?.handle($0) },
            description: "Send unmatched messages to LLM"
        )
        routes = [fallback]
    }

    func handle(_ message: Message) {
        guard let text = message.getTextBody() else { return }
        guard !text.hasPrefix("/") else { return }
        guard !config.apiKey.isEmpty else { return }

        let senderHandle = message.sender.handle

        lock.lock()
        let last = lastRequestTime[senderHandle]
        let now = Date()
        if let last = last, now.timeIntervalSince(last) < config.rateLimitSeconds {
            lock.unlock()
            return
        }
        lastRequestTime[senderHandle] = now
        lock.unlock()

        guard let recipient = message.RespondTo() else { return }

        callLLM(userText: text) { [weak self] reply in
            guard let reply = reply else { return }
            self?.sender.send(reply, to: recipient)
        }
    }

    private func callLLM(userText: String, completion: @escaping (String?) -> Void) {
        guard let url = URL(string: "https://api.openai.com/v1/chat/completions") else {
            completion(nil)
            return
        }

        let body: [String: Any] = [
            "model": config.model,
            "messages": [
                ["role": "system", "content": config.systemPrompt],
                ["role": "user", "content": userText]
            ]
        ]

        guard let bodyData = try? JSONSerialization.data(withJSONObject: body) else {
            completion(nil)
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = bodyData
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")

        session.dataTask(with: request) { data, response, error in
            guard error == nil,
                  let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let choices = json["choices"] as? [[String: Any]],
                  let first = choices.first,
                  let msg = first["message"] as? [String: Any],
                  let content = msg["content"] as? String else {
                completion(nil)
                return
            }
            completion(content)
        }.resume()
    }
}

// Minimal top-level wrapper to decode just the llm key from config.json
private struct TopLevelConfig: Decodable {
    let llm: LLMConfiguration?
}
