import Foundation

// MARK: - Usage Report Response
struct UsageReportResponse: Codable {
    let data: [UsageBucket]
    let hasMore: Bool
    let nextPage: String?

    enum CodingKeys: String, CodingKey {
        case data
        case hasMore = "has_more"
        case nextPage = "next_page"
    }
}

struct UsageBucket: Codable {
    let startingAt: String
    let endingAt: String
    let results: [UsageResult]

    enum CodingKeys: String, CodingKey {
        case startingAt = "starting_at"
        case endingAt = "ending_at"
        case results
    }
}

struct UsageResult: Codable {
    let inputTokens: Int?
    let outputTokens: Int?
    let cacheCreationInputTokens: Int?
    let cacheReadInputTokens: Int?
    let model: String?
    let workspaceId: String?

    enum CodingKeys: String, CodingKey {
        case inputTokens = "input_tokens"
        case outputTokens = "output_tokens"
        case cacheCreationInputTokens = "cache_creation_input_tokens"
        case cacheReadInputTokens = "cache_read_input_tokens"
        case model
        case workspaceId = "workspace_id"
    }
}

// MARK: - Cost Report Response
struct CostReportResponse: Codable {
    let data: [CostBucket]
    let hasMore: Bool
    let nextPage: String?

    enum CodingKeys: String, CodingKey {
        case data
        case hasMore = "has_more"
        case nextPage = "next_page"
    }
}

struct CostBucket: Codable {
    let startingAt: String
    let endingAt: String
    let results: [CostResult]

    enum CodingKeys: String, CodingKey {
        case startingAt = "starting_at"
        case endingAt = "ending_at"
        case results
    }
}

struct CostResult: Codable {
    let costUsd: Double?
    let model: String?
    let workspaceId: String?

    enum CodingKeys: String, CodingKey {
        case costUsd = "cost_usd"
        case model
        case workspaceId = "workspace_id"
    }
}

// MARK: - Claude Code Usage Response
struct ClaudeCodeUsageResponse: Codable {
    let data: [ClaudeCodeUsage]
    let hasMore: Bool
    let nextPage: String?

    enum CodingKeys: String, CodingKey {
        case data
        case hasMore = "has_more"
        case nextPage = "next_page"
    }
}

struct ClaudeCodeUsage: Codable {
    let date: String?
    let userId: String?
    let userEmail: String?
    let totalInputTokens: Int?
    let totalOutputTokens: Int?
    let totalCostUsd: Double?
    let totalSessions: Int?
    let activeMinutes: Int?

    enum CodingKeys: String, CodingKey {
        case date
        case userId = "user_id"
        case userEmail = "user_email"
        case totalInputTokens = "total_input_tokens"
        case totalOutputTokens = "total_output_tokens"
        case totalCostUsd = "total_cost_usd"
        case totalSessions = "total_sessions"
        case activeMinutes = "active_minutes"
    }
}

// MARK: - Aggregated Usage Summary
struct UsageSummary {
    let inputTokens: Int
    let outputTokens: Int
    let totalCost: Double
    let modelBreakdown: [ModelUsage]
    let lastUpdated: Date

    struct ModelUsage: Identifiable {
        let id = UUID()
        let model: String
        let inputTokens: Int
        let outputTokens: Int
        let cost: Double
    }

    static var empty: UsageSummary {
        UsageSummary(
            inputTokens: 0,
            outputTokens: 0,
            totalCost: 0,
            modelBreakdown: [],
            lastUpdated: Date()
        )
    }
}
