import Foundation

func generateOpenAIResponse(prompt: String) async throws -> String {
    // Get API key from configuration
    guard let apiKey = Bundle.main.object(forInfoDictionaryKey: "OPENAI_API_KEY") as? String else {
        throw NSError(domain: "OpenAIError", code: 1, userInfo: [NSLocalizedDescriptionKey: "OpenAI API key not found in configuration"])
    }
    
    guard let url = URL(string: "https://api.openai.com/v1/chat/completions") else {
        throw URLError(.badURL)
    }

    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

    // Safely encode using Swift structs instead of manual JSON
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
//        model: "gpt-4o-2024-08-06",
        model: "o4-mini-2025-04-16",
        messages: [Message(role: "user", content: prompt)],
        temperature: 1
    )

    request.httpBody = try JSONEncoder().encode(requestBody)

    let (data, response) = try await URLSession.shared.data(for: request)

    guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
        let responseText = String(data: data, encoding: .utf8) ?? "No response text"
        throw NSError(domain: "OpenAIError", code: 2, userInfo: [NSLocalizedDescriptionKey: "Invalid response: \(responseText)"])
    }

    // Define a decoding structure to match the API
    struct OpenAIChoice: Codable {
        let message: Message
    }

    struct OpenAIResponse: Codable {
        let choices: [OpenAIChoice]
    }

    let decodedResponse = try JSONDecoder().decode(OpenAIResponse.self, from: data)
    return decodedResponse.choices.first?.message.content.trimmingCharacters(in: .whitespacesAndNewlines) ?? "No content returned"
}
