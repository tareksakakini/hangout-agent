import Foundation

// MARK: - Helper to load API Key from Secrets.plist
func loadAPIKey() -> String? {
    guard let url = Bundle.main.url(forResource: "Secrets", withExtension: "plist"),
          let data = try? Data(contentsOf: url),
          let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
          let key = plist["OPENAI_API_KEY"] as? String else {
        return nil
    }
    return key
}

// MARK: - Main OpenAI API Call
func generateOpenAIResponse(prompt: String) async throws -> String {
    guard let apiKey = loadAPIKey() else {
        throw NSError(domain: "OpenAIError", code: 1, userInfo: [NSLocalizedDescriptionKey: "API key not found"])
    }

    guard let url = URL(string: "https://api.openai.com/v1/chat/completions") else {
        throw URLError(.badURL)
    }

    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

    struct Message: Codable {
        let role: String
        let content: String
    }

    struct RequestBody: Codable {
        let model: String
        let messages: [Message]
        let temperature: Double
    }

    let requestBody = RequestBody(
        model: "gpt-4o",  // or "gpt-4" or "gpt-3.5-turbo"
        messages: [Message(role: "user", content: prompt)],
        temperature: 1.0
    )

    request.httpBody = try JSONEncoder().encode(requestBody)

    let (data, response) = try await URLSession.shared.data(for: request)

    guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
        let responseText = String(data: data, encoding: .utf8) ?? "No response text"
        throw NSError(domain: "OpenAIError", code: 2, userInfo: [NSLocalizedDescriptionKey: "Invalid response: \(responseText)"])
    }

    struct OpenAIChoice: Codable {
        let message: Message
    }

    struct OpenAIResponse: Codable {
        let choices: [OpenAIChoice]
    }

    let decodedResponse = try JSONDecoder().decode(OpenAIResponse.self, from: data)
    return decodedResponse.choices.first?.message.content.trimmingCharacters(in: .whitespacesAndNewlines) ?? "No content returned"
}
