import Vapor
import Fluent
import SQLKit
import Foundation

struct ChatService: Sendable {
    let app: Application
    let logger: Logger
    private let ollamaURL = "http://192.168.1.144:11434/api/chat"
    private let chatModel = "qwen3.5:latest"

    init(app: Application) {
        self.app = app
        self.logger = app.logger
    }

    struct ChatSource: Codable {
        let transcriptID: Int
        let speaker: String
        let date: String
        let similarity: Double
        let excerpt: String
    }

    /// Perform RAG: embed question, find relevant chunks, stream answer
    func streamAnswer(
        question: String,
        history: [[String: String]],
        on db: Database,
        writer: @escaping (String) async throws -> Void,
        sourcesCallback: @escaping ([ChatSource]) async throws -> Void
    ) async throws {
        guard let sql = db as? SQLDatabase else {
            throw Abort(.internalServerError, reason: "SQL database required")
        }

        // 1. Embed the question
        let embeddingService = EmbeddingService(app: app)
        let queryEmbedding = try await embeddingService.embed(text: question)
        let vecStr = "[" + queryEmbedding.map { String($0) }.joined(separator: ",") + "]"

        // 2. Find top-10 similar chunks via pgvector
        let rows = try await sql.raw("""
            SELECT te."chunk_text", te."transcript_id",
                   mc."first_name", mc."last_name",
                   t."meeting_date",
                   1 - (te."embedding" <=> '\(unsafeRaw: vecStr)'::vector) AS similarity
            FROM "transcript_embedding" te
            JOIN "transcript" t ON te."transcript_id" = t."id"
            LEFT JOIN "member_council" mc ON t."member_council_id" = mc."id"
            ORDER BY te."embedding" <=> '\(unsafeRaw: vecStr)'::vector
            LIMIT 10
        """).all()

        // 3. Build context from chunks
        var contextParts: [String] = []
        var sources: [ChatSource] = []
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "dd.MM.yyyy"

        for row in rows {
            let chunkText = (try? row.decode(column: "chunk_text", as: String.self)) ?? ""
            let transcriptID = (try? row.decode(column: "transcript_id", as: Int.self)) ?? 0
            let firstName = (try? row.decode(column: "first_name", as: String.self)) ?? ""
            let lastName = (try? row.decode(column: "last_name", as: String.self)) ?? ""
            let meetingDate = try? row.decode(column: "meeting_date", as: Date.self)
            let similarity = (try? row.decode(column: "similarity", as: Double.self)) ?? 0

            let dateStr = meetingDate.map { dateFormatter.string(from: $0) } ?? ""
            let speaker = lastName.isEmpty ? "Unbekannt" : "\(firstName) \(lastName)"

            contextParts.append("[\(speaker), \(dateStr)]: \(chunkText)")
            sources.append(ChatSource(
                transcriptID: transcriptID,
                speaker: speaker,
                date: dateStr,
                similarity: similarity,
                excerpt: String(chunkText.prefix(150))
            ))
        }

        // Send sources to client before streaming
        try await sourcesCallback(sources)

        let context = contextParts.joined(separator: "\n\n---\n\n")

        // 4. Build messages for Ollama
        var messages: [[String: String]] = [
            [
                "role": "system",
                "content": """
                Du bist ein Experte für die Schweizer Parlamentspolitik. \
                Beantworte Fragen basierend auf den folgenden Wortmeldungen aus dem Parlament. \
                Nenne immer die Quelle (Name des Parlamentariers, Datum). \
                Wenn die Informationen nicht ausreichen, sage das ehrlich. \
                Antworte auf Deutsch.

                ### KONTEXT (Wortmeldungen aus dem Parlament)
                \(context)
                """
            ]
        ]

        // Add chat history
        for msg in history.suffix(10) {
            if let role = msg["role"], let content = msg["content"] {
                messages.append(["role": role, "content": content])
            }
        }

        // Add current question
        messages.append(["role": "user", "content": question])

        // 5. Stream response from Ollama
        let body: [String: Any] = [
            "model": chatModel,
            "stream": true,
            "options": [
                "temperature": 0.3,
                "think": false,
                "num_predict": 4096,
                "num_ctx": 32768
            ] as [String: Any],
            "messages": messages
        ]

        let bodyData = try JSONSerialization.data(withJSONObject: body)

        guard let url = URL(string: ollamaURL) else {
            throw Abort(.internalServerError, reason: "Invalid Ollama URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = bodyData
        request.timeoutInterval = 300

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 300
        config.timeoutIntervalForResource = 600
        let session = URLSession(configuration: config)

        let (bytes, response) = try await session.bytes(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw Abort(.internalServerError, reason: "Ollama chat request failed")
        }

        for try await line in bytes.lines {
            guard !line.isEmpty,
                  let lineData = line.data(using: .utf8),
                  let chunk = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                  let message = chunk["message"] as? [String: Any],
                  let token = message["content"] as? String else { continue }
            if !token.isEmpty {
                try await writer(token)
            }
            if chunk["done"] as? Bool == true { break }
        }
    }
}
