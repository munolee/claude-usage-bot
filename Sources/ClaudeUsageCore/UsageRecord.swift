import Foundation

/// One assistant message's token usage parsed from a `~/.claude/projects/**/*.jsonl` line.
public struct UsageRecord: Equatable, Sendable {
    public let messageId: String
    public let requestId: String?
    public let sessionId: String?
    public let model: String
    public let timestamp: Date
    public let inputTokens: Int
    public let outputTokens: Int
    public let cacheCreationInputTokens: Int
    public let cacheReadInputTokens: Int

    public init(
        messageId: String,
        requestId: String?,
        sessionId: String?,
        model: String,
        timestamp: Date,
        inputTokens: Int,
        outputTokens: Int,
        cacheCreationInputTokens: Int,
        cacheReadInputTokens: Int
    ) {
        self.messageId = messageId
        self.requestId = requestId
        self.sessionId = sessionId
        self.model = model
        self.timestamp = timestamp
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.cacheCreationInputTokens = cacheCreationInputTokens
        self.cacheReadInputTokens = cacheReadInputTokens
    }

    public var totalTokens: Int {
        inputTokens + outputTokens + cacheCreationInputTokens + cacheReadInputTokens
    }
}
