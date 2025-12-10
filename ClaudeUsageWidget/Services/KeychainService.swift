import Foundation

enum KeychainError: LocalizedError {
    case itemNotFound

    var errorDescription: String? {
        switch self {
        case .itemNotFound:
            return "API key not found"
        }
    }
}

struct KeychainService {
    private static let apiKeyKey = "anthropic-admin-api-key"

    // MARK: - Save API Key
    static func saveAPIKey(_ apiKey: String) throws {
        UserDefaults.standard.set(apiKey, forKey: apiKeyKey)
    }

    // MARK: - Load API Key
    static func loadAPIKey() throws -> String {
        guard let apiKey = UserDefaults.standard.string(forKey: apiKeyKey), !apiKey.isEmpty else {
            throw KeychainError.itemNotFound
        }
        return apiKey
    }

    // MARK: - Delete API Key
    static func deleteAPIKey() throws {
        UserDefaults.standard.removeObject(forKey: apiKeyKey)
    }

    // MARK: - Check if API Key exists
    static func hasAPIKey() -> Bool {
        guard let key = UserDefaults.standard.string(forKey: apiKeyKey) else { return false }
        return !key.isEmpty
    }
}
