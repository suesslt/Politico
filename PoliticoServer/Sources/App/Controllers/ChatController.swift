import Vapor
import Fluent
import NIOCore

struct ChatController: RouteCollection {
    func boot(routes: RoutesBuilder) throws {
        routes.post("chat", use: chat)
        routes.post("embeddings", "generate", use: startEmbedding)
        routes.post("embeddings", "stop", use: stopEmbedding)
        routes.get("embeddings", "status", use: embeddingStatus)
    }

    // MARK: - Chat (SSE streaming)

    struct ChatRequest: Content {
        let message: String
        let history: [[String: String]]?
    }

    @Sendable
    func chat(req: Request) async throws -> Response {
        let chatReq = try req.content.decode(ChatRequest.self)
        let app = req.application
        let db = req.db

        let response = Response(status: .ok)
        response.headers.replaceOrAdd(name: "Content-Type", value: "text/event-stream")
        response.headers.replaceOrAdd(name: "Cache-Control", value: "no-cache")
        response.headers.replaceOrAdd(name: "Connection", value: "keep-alive")

        response.body = .init(asyncStream: { writer in
            do {
                let chatService = ChatService(app: app)
                try await chatService.streamAnswer(
                    question: chatReq.message,
                    history: chatReq.history ?? [],
                    on: db,
                    writer: { token in
                        // Escape for SSE: replace newlines
                        let escaped = token.replacingOccurrences(of: "\n", with: "\\n")
                        let sseData = "data: \(escaped)\n\n"
                        try await writer.write(.buffer(ByteBuffer(string: sseData)))
                    },
                    sourcesCallback: { sources in
                        // Send sources as a special SSE event
                        let encoder = JSONEncoder()
                        if let data = try? encoder.encode(sources),
                           let json = String(data: data, encoding: .utf8) {
                            let sseData = "event: sources\ndata: \(json)\n\n"
                            try await writer.write(.buffer(ByteBuffer(string: sseData)))
                        }
                    }
                )
                try await writer.write(.buffer(ByteBuffer(string: "data: [DONE]\n\n")))
            } catch {
                let errorMsg = "data: [ERROR] \(error.localizedDescription)\n\n"
                try? await writer.write(.buffer(ByteBuffer(string: errorMsg)))
            }
            try await writer.write(.end)
        })

        return response
    }

    // MARK: - Embedding generation

    @Sendable
    func startEmbedding(req: Request) async throws -> EmbeddingStatusResponse {
        // Check if already running (with stale detection)
        if let existing = try await SyncStatus.query(on: req.db)
            .filter(\.$entityName == "embeddings")
            .filter(\.$status == "embedding")
            .first() {
            let staleThreshold = Date().addingTimeInterval(-600)
            if let lastUpdate = existing.lastSyncAt, lastUpdate > staleThreshold {
                return EmbeddingStatusResponse(
                    status: existing.status,
                    message: existing.errorMessage ?? "Already running"
                )
            }
            existing.status = "failed"
            existing.errorMessage = "Reset: previous task timed out"
            try await existing.update(on: req.db)
        }

        let app = req.application
        Task {
            let service = EmbeddingService(app: app)
            do {
                try await service.generateAll(on: app.db)
            } catch {
                app.logger.error("Embedding generation failed: \(String(reflecting: error))")
                if let status = try? await SyncStatus.query(on: app.db)
                    .filter(\.$entityName == "embeddings")
                    .first() {
                    status.status = "failed"
                    status.errorMessage = error.localizedDescription
                    try? await status.update(on: app.db)
                }
            }
        }

        return EmbeddingStatusResponse(status: "started", message: "Embedding generation started")
    }

    @Sendable
    func stopEmbedding(req: Request) async throws -> EmbeddingStatusResponse {
        EmbeddingCancellation.shared.cancel()
        return EmbeddingStatusResponse(status: "stopping", message: "Stop requested")
    }

    @Sendable
    func embeddingStatus(req: Request) async throws -> EmbeddingStatusResponse {
        let status = try await SyncStatus.query(on: req.db)
            .filter(\.$entityName == "embeddings")
            .first()

        return EmbeddingStatusResponse(
            status: status?.status ?? "idle",
            message: status?.errorMessage ?? "No embedding generation started yet"
        )
    }
}

struct EmbeddingStatusResponse: Content {
    let status: String
    let message: String
}
