import Foundation
import os

// MARK: - Ollama Error

enum OllamaError: Error, LocalizedError {
    case serverUnreachable
    case modelNotFound(String)
    case generationFailed(String)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .serverUnreachable:
            return "Ollama server is unreachable at localhost:11434"
        case .modelNotFound(let modelName):
            return "Model '\(modelName)' not found on Ollama server"
        case .generationFailed(let reason):
            return "Text generation failed: \(reason)"
        case .invalidResponse:
            return "Received invalid response from Ollama server"
        }
    }
}

// MARK: - Ollama API Models

private struct OllamaGenerateRequest: Codable {
    let model: String
    let system: String
    let prompt: String
    let stream: Bool
    let options: Options

    struct Options: Codable {
        let num_predict: Int
    }
}

private struct OllamaGenerateResponse: Codable {
    let response: String
    let done: Bool
}

private struct OllamaTagsResponse: Codable {
    let models: [OllamaModel]
}

private struct OllamaModel: Codable {
    let name: String
}

// MARK: - OllamaProvider

actor OllamaProvider: LLMProvider {
    // MARK: - Properties

    private let baseURL: URL
    private var currentModelName: String?

    // MARK: - Initialization

    init(baseURL: String = "http://localhost:11434") {
        self.baseURL = URL(string: baseURL)!
        Logger.llm.info("OllamaProvider initialized with base URL: \(baseURL)")
    }

    // MARK: - LLMProvider Protocol

    func loadModel(at path: String) async throws {
        Logger.llm.info("Loading Ollama model: \(path)")

        guard await Self.isOllamaRunning() else {
            Logger.llm.error("Ollama server is not running")
            throw OllamaError.serverUnreachable
        }

        let availableModels = try await fetchAvailableModels()
        guard availableModels.contains(where: { $0.hasPrefix(path) }) else {
            Logger.llm.error("Model '\(path)' not found in available models")
            throw OllamaError.modelNotFound(path)
        }

        currentModelName = path
        Logger.llm.info("Ollama model loaded: \(path)")
    }

    func unloadModel() async {
        Logger.llm.info("Unloading Ollama model")
        currentModelName = nil
    }

    func generate(systemPrompt: String, userPrompt: String, maxTokens: Int) async throws -> String {
        guard let modelName = currentModelName else {
            Logger.llm.error("No model loaded for generation")
            throw OllamaError.generationFailed("No model loaded")
        }

        Logger.llm.info("Generating text with model: \(modelName)")

        let url = baseURL.appendingPathComponent("api/generate")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let requestBody = OllamaGenerateRequest(
            model: modelName,
            system: systemPrompt,
            prompt: userPrompt,
            stream: false,
            options: OllamaGenerateRequest.Options(num_predict: maxTokens)
        )

        do {
            request.httpBody = try JSONEncoder().encode(requestBody)

            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw OllamaError.invalidResponse
            }

            guard httpResponse.statusCode == 200 else {
                let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
                Logger.llm.error("Generation failed with status \(httpResponse.statusCode): \(errorMessage)")
                throw OllamaError.generationFailed("HTTP \(httpResponse.statusCode): \(errorMessage)")
            }

            let generateResponse = try JSONDecoder().decode(OllamaGenerateResponse.self, from: data)

            Logger.llm.info("Generation completed successfully")
            return generateResponse.response

        } catch let error as OllamaError {
            throw error
        } catch {
            Logger.llm.error("Generation failed: \(error.localizedDescription)")
            throw OllamaError.generationFailed(error.localizedDescription)
        }
    }

    var isModelLoaded: Bool {
        currentModelName != nil
    }

    var estimatedMemoryUsage: UInt64 {
        0
    }

    // MARK: - Static Helper

    static func isOllamaRunning() async -> Bool {
        let url = URL(string: "http://localhost:11434/api/tags")!
        var request = URLRequest(url: url)
        request.timeoutInterval = 2.0

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                return false
            }
            return httpResponse.statusCode == 200
        } catch {
            return false
        }
    }

    // MARK: - Private Helpers

    private func fetchAvailableModels() async throws -> [String] {
        let url = baseURL.appendingPathComponent("api/tags")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw OllamaError.invalidResponse
            }

            guard httpResponse.statusCode == 200 else {
                throw OllamaError.serverUnreachable
            }

            let tagsResponse = try JSONDecoder().decode(OllamaTagsResponse.self, from: data)
            return tagsResponse.models.map { $0.name }

        } catch let error as OllamaError {
            throw error
        } catch {
            throw OllamaError.serverUnreachable
        }
    }
}
