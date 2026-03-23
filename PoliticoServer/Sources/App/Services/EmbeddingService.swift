import Vapor
import Fluent
import SQLKit
import Foundation

/// Cancellation flag for embedding generation
final class EmbeddingCancellation: @unchecked Sendable {
    static let shared = EmbeddingCancellation()
    private var _cancelled = false
    private let lock = NSLock()

    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _cancelled
    }

    func cancel() { lock.lock(); _cancelled = true; lock.unlock() }
    func reset() { lock.lock(); _cancelled = false; lock.unlock() }
}

struct EmbeddingService: Sendable {
    let app: Application
    let logger: Logger
    private let ollamaURL = "http://192.168.1.144:11434/api/embed"
    private let model = "nomic-embed-text"
    private let batchSize = 5  // transcripts per batch (kept small to avoid exhausting DB pool)
    private let chunkWordLimit = 400
    private let chunkOverlap = 50

    init(app: Application) {
        self.app = app
        self.logger = app.logger
    }

    // MARK: - Single query embedding

    func embed(text: String) async throws -> [Float] {
        let body: [String: Any] = [
            "model": model,
            "input": [text]
        ]
        let bodyData = try JSONSerialization.data(withJSONObject: body)

        guard let url = URL(string: ollamaURL) else {
            throw Abort(.internalServerError, reason: "Invalid Ollama URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = bodyData
        request.timeoutInterval = 30

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw Abort(.internalServerError, reason: "Ollama embed request failed")
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let embeddings = json["embeddings"] as? [[Double]],
              let first = embeddings.first else {
            throw Abort(.internalServerError, reason: "Invalid embedding response")
        }

        return first.map { Float($0) }
    }

    // MARK: - Batch embedding for multiple texts

    private func embedBatch(texts: [String]) async throws -> [[Float]] {
        let body: [String: Any] = [
            "model": model,
            "input": texts
        ]
        let bodyData = try JSONSerialization.data(withJSONObject: body)

        guard let url = URL(string: ollamaURL) else {
            throw Abort(.internalServerError, reason: "Invalid Ollama URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = bodyData
        request.timeoutInterval = 120

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw Abort(.internalServerError, reason: "Ollama embed batch request failed")
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let embeddings = json["embeddings"] as? [[Double]] else {
            throw Abort(.internalServerError, reason: "Invalid embedding response")
        }

        return embeddings.map { $0.map { Float($0) } }
    }

    // MARK: - Chunking

    func chunkText(_ text: String) -> [String] {
        let plainText = text
            .replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let words = plainText.split(separator: " ").map(String.init)
        if words.count <= chunkWordLimit {
            return plainText.isEmpty ? [] : [plainText]
        }

        var chunks: [String] = []
        var start = 0
        while start < words.count {
            let end = min(start + chunkWordLimit, words.count)
            let chunk = words[start..<end].joined(separator: " ")
            chunks.append(chunk)
            start = end - chunkOverlap
            if start >= words.count - chunkOverlap { break }
        }
        // Catch any remaining words
        if start < words.count {
            let remaining = words[start...].joined(separator: " ")
            if !remaining.isEmpty { chunks.append(remaining) }
        }

        return chunks
    }

    // MARK: - Batch generation (background task)

    func generateAll(on db: Database) async throws {
        EmbeddingCancellation.shared.reset()
        guard let sql = db as? SQLDatabase else { return }

        try await updateStatus(status: "embedding", embedded: 0, total: 0, on: db)

        // Find transcripts that don't have embeddings yet and have text
        let transcriptIDs = try await Transcript.query(on: db)
            .all()
            .compactMap { t -> Int? in
                guard let id = t.id,
                      let text = t.text,
                      text.trimmingCharacters(in: .whitespacesAndNewlines).count > 20 else { return nil }
                return id
            }

        // Filter out already embedded
        let existingIDs = try await sql.raw("""
            SELECT DISTINCT "transcript_id" FROM "transcript_embedding"
        """).all().compactMap { row -> Int? in
            try? row.decode(column: "transcript_id", as: Int.self)
        }
        let existingSet = Set(existingIDs)
        let toProcess = transcriptIDs.filter { !existingSet.contains($0) }

        let total = toProcess.count
        if total == 0 {
            try await updateStatus(status: "completed", embedded: existingIDs.count, total: existingIDs.count, on: db)
            logger.info("All transcripts already embedded (\(existingIDs.count))")
            return
        }

        logger.info("Starting embedding generation for \(total) transcripts (\(existingIDs.count) already done)")

        var processed = 0

        for batchStart in stride(from: 0, to: total, by: batchSize) {
            if EmbeddingCancellation.shared.isCancelled {
                logger.info("Embedding generation cancelled at \(processed)/\(total)")
                try? await updateStatus(status: "stopped", embedded: existingIDs.count + processed, total: existingIDs.count + total, on: db)
                return
            }

            let batchEnd = min(batchStart + batchSize, total)
            let batchIDs = Array(toProcess[batchStart..<batchEnd])

            // Load transcripts for this batch
            var allChunks: [(transcriptID: Int, chunkIndex: Int, chunkText: String)] = []
            for tid in batchIDs {
                guard let transcript = try await Transcript.find(tid, on: db),
                      let text = transcript.text else { continue }
                let chunks = chunkText(text)
                for (idx, chunk) in chunks.enumerated() {
                    allChunks.append((transcriptID: tid, chunkIndex: idx, chunkText: chunk))
                }
            }

            if allChunks.isEmpty {
                processed += batchIDs.count
                continue
            }

            // Embed all chunks in one call
            do {
                let texts = allChunks.map { $0.chunkText }
                let embeddings = try await embedBatch(texts: texts)

                // Insert into DB via raw SQL
                for (i, chunk) in allChunks.enumerated() {
                    guard i < embeddings.count else { break }
                    let vecStr = "[" + embeddings[i].map { String($0) }.joined(separator: ",") + "]"
                    try await sql.raw("""
                        INSERT INTO "transcript_embedding" ("transcript_id", "chunk_index", "chunk_text", "embedding")
                        VALUES (\(unsafeRaw: String(chunk.transcriptID)), \(unsafeRaw: String(chunk.chunkIndex)), \(bind: chunk.chunkText), \(unsafeRaw: "'\(vecStr)'")::vector)
                        ON CONFLICT ("transcript_id", "chunk_index") DO NOTHING
                    """).run()
                }
            } catch {
                logger.warning("Failed to embed batch at \(batchStart): \(String(reflecting: error))")
            }

            processed += batchIDs.count

            // Pause between batches to free DB connections for other requests
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5s

            try? await updateStatus(status: "embedding", embedded: existingIDs.count + processed, total: existingIDs.count + total, on: db)
            if processed % 50 == 0 || batchEnd == total {
                logger.info("Embedding progress: \(processed)/\(total) transcripts")
            }
        }

        try await updateStatus(status: "completed", embedded: existingIDs.count + processed, total: existingIDs.count + total, on: db)
        logger.info("Embedding generation completed: \(processed) new transcripts embedded")
    }

    // MARK: - Status

    private func updateStatus(status: String, embedded: Int, total: Int, on db: Database) async throws {
        let entity = "embeddings"
        if let existing = try await SyncStatus.query(on: db)
            .filter(\.$entityName == entity)
            .first() {
            existing.status = status
            existing.lastSyncAt = Date()
            existing.itemsSynced = embedded
            existing.errorMessage = "Embedded \(embedded)/\(total) Transcripts"
            try await existing.update(on: db)
        } else {
            let syncStatus = SyncStatus(entityName: entity, sessionID: 0, status: status, itemsSynced: embedded)
            syncStatus.lastSyncAt = Date()
            syncStatus.errorMessage = "Embedded \(embedded)/\(total) Transcripts"
            try await syncStatus.create(on: db)
        }
    }
}
