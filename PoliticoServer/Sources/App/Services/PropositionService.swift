import Vapor
import Fluent
import Foundation

/// Thread-safe cancellation flag for proposition extraction
final class PropositionCancellation: @unchecked Sendable {
    static let shared = PropositionCancellation()
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

struct PropositionService: Sendable {
    let app: Application
    let logger: Logger
    private let ollamaURL = "http://192.168.1.144:11434/api/chat"
    private let maxConcurrency = 1

    init(app: Application) {
        self.app = app
        self.logger = app.logger
    }

    func extractAll(on db: Database) async throws {
        // Reset cancellation flag
        PropositionCancellation.shared.reset()

        // Update status to extracting
        try await updateStatus(status: "extracting", propositions: 0, transcripts: 0, total: 0, on: db)

        // Load subject lookup
        let subjects = try await PropositionSubject.query(on: db).all()
        let subjectMap = Dictionary(uniqueKeysWithValues: subjects.compactMap { s -> (String, Int)? in
            guard let id = s.id else { return nil }
            return (s.name, id)
        })

        // Get IDs of transcripts that need processing (lightweight query)
        let transcriptIDs = try await Transcript.query(on: db)
            .filter(\.$propositionsExtracted == false)
            .all()
            .compactMap { t -> Int? in
                guard let id = t.id,
                      let text = t.text,
                      text.trimmingCharacters(in: .whitespacesAndNewlines).count > 20 else { return nil }
                return id
            }

        let total = transcriptIDs.count
        if total == 0 {
            try await updateStatus(status: "completed", propositions: 0, transcripts: 0, total: 0, on: db)
            logger.info("No transcripts to process for propositions")
            return
        }

        logger.info("Starting proposition extraction for \(total) transcripts")

        var totalPropositions = 0
        var processedTranscripts = 0

        // Process in chunks of maxConcurrency, loading each transcript individually
        for chunkStart in stride(from: 0, to: total, by: maxConcurrency) {
            // Check for cancellation before each batch
            if PropositionCancellation.shared.isCancelled {
                logger.info("Proposition extraction cancelled at \(processedTranscripts)/\(total)")
                try? await updateStatus(status: "stopped", propositions: totalPropositions, transcripts: processedTranscripts, total: total, on: db)
                return
            }

            let chunkEnd = min(chunkStart + maxConcurrency, total)
            let chunkIDs = Array(transcriptIDs[chunkStart..<chunkEnd])

            await withTaskGroup(of: Int.self) { group in
                for transcriptID in chunkIDs {
                    group.addTask {
                        guard !PropositionCancellation.shared.isCancelled else { return 0 }
                        do {
                            guard let transcript = try await Transcript.find(transcriptID, on: db) else { return 0 }
                            let count = try await self.processTranscript(transcript, subjectMap: subjectMap, on: db)
                            return count
                        } catch {
                            self.logger.warning("Failed to extract propositions for transcript \(transcriptID): \(String(reflecting: error))")
                            return 0
                        }
                    }
                }

                for await count in group {
                    totalPropositions += count
                    processedTranscripts += 1
                }
            }

            // Pause between batches to free DB connections
            try? await Task.sleep(nanoseconds: 500_000_000)

            // Update status after each batch
            try? await updateStatus(status: "extracting", propositions: totalPropositions, transcripts: processedTranscripts, total: total, on: db)
            logger.info("Propositions progress: \(processedTranscripts)/\(total) transcripts (\(totalPropositions) propositions)")
        }

        try await updateStatus(status: "completed", propositions: totalPropositions, transcripts: processedTranscripts, total: total, on: db)
        logger.info("Proposition extraction completed: \(totalPropositions) propositions from \(processedTranscripts)/\(total) transcripts")
    }

    private func processTranscript(_ transcript: Transcript, subjectMap: [String: Int], on db: Database) async throws -> Int {
        guard let transcriptID = transcript.id else { return 0 }
        let rawText = transcript.text ?? ""

        // Strip HTML tags
        let plainText = rawText
            .replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !plainText.isEmpty else {
            transcript.propositionsExtracted = true
            try await transcript.update(on: db)
            return 0
        }

        // Build prompt (matching propositions.py)
        let subjectList = Array(subjectMap.keys).sorted().map { "- \($0)" }.joined(separator: "\n")
        let prompt = """
        ### AUFGABE Extraktion von autarken Kernaussagen
        Analysiere den untenstehenden Text vollständig und erstelle eine umfassende Liste aller Kernaussagen. Kriterien:
        - Propositionale Struktur: Klares Subjekt und Prädikat
        - Autarkie: Verständlich ohne Kontext
        - Falsifizierbarkeit: Keine vagen Füllwörter
        - Kausalität: Wo möglich Wirkmechanismus benennen
        - Präzision vor Quantität

        Subjekt aus dieser Liste wählen:
        \(subjectList)

        ### FORMAT
        Gib ein JSON-Array zurück. Jedes Element hat:
        - Kernaussage (Text)
        - Subjekt (Eintrag aus Liste)
        - Zeitpunkt (yyyy-MM-dd, optional)
        - Quelle (Person/Institution, optional)

        Nur das Array. Kein Text davor oder danach. Keine Backticks.

        ### DATEN
        \(plainText)
        """

        // Call Ollama
        let responseContent = try await callOllama(prompt: prompt)

        // Parse JSON response
        let propositions = parsePropositions(responseContent)

        // Deduplicate
        var seen = Set<String>()
        var unique: [[String: Any]] = []
        for p in propositions {
            let text = p["Kernaussage"] as? String ?? ""
            if !text.isEmpty && !seen.contains(text) {
                seen.insert(text)
                unique.append(p)
            }
        }

        // Save to DB
        for p in unique {
            let text = p["Kernaussage"] as? String ?? ""
            let subjektName = p["Subjekt"] as? String
            let zeitpunkt = p["Zeitpunkt"] as? String
            let quelle = p["Quelle"] as? String

            let subjectID = subjektName.flatMap { subjectMap[$0] }

            let proposition = Proposition(
                transcriptID: transcriptID,
                text: text,
                subjectID: subjectID,
                source: quelle,
                dateText: zeitpunkt
            )
            try await proposition.create(on: db)
        }

        // Mark transcript as processed
        transcript.propositionsExtracted = true
        try await transcript.update(on: db)

        return unique.count
    }

    private func callOllama(prompt: String) async throws -> String {
        guard let url = URL(string: ollamaURL) else {
            throw Abort(.internalServerError, reason: "Invalid Ollama URL")
        }

        let body: [String: Any] = [
            "model": "qwen3:14b",
            "stream": true,
            "options": [
                "temperature": 0.1,
                "think": false,
                "num_predict": 16384,
                "num_ctx": 32768,
                "repeat_penalty": 1.3,
                "repeat_last_n": 128
            ] as [String: Any],
            "messages": [
                [
                    "role": "system",
                    "content": "Du bist ein Sprachspezialist. Gib ausschliesslich ein valides JSON-Array zurueck. Keine Erklaerungen, keine Backticks, kein Text vor oder nach dem Array."
                ],
                [
                    "role": "user",
                    "content": prompt
                ]
            ]
        ]

        let bodyData = try JSONSerialization.data(withJSONObject: body)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = bodyData
        request.timeoutInterval = 300 // 5 minutes per request

        // Stream the response with extended timeout
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 300
        config.timeoutIntervalForResource = 600
        let session = URLSession(configuration: config)
        let (bytes, response) = try await session.bytes(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw Abort(.internalServerError, reason: "Ollama returned error")
        }

        var content = ""
        for try await line in bytes.lines {
            guard !line.isEmpty,
                  let lineData = line.data(using: .utf8),
                  let chunk = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                  let message = chunk["message"] as? [String: Any],
                  let token = message["content"] as? String else { continue }
            content += token
            if chunk["done"] as? Bool == true { break }
        }

        return content
    }

    private func parsePropositions(_ content: String) -> [[String: Any]] {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)

        // Try direct parse
        if let data = trimmed.data(using: .utf8),
           let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            return arr
        }

        // Strip markdown backticks
        let cleaned = trimmed
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if let data = cleaned.data(using: .utf8),
           let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            return arr
        }

        // Extract JSON array with regex
        if let range = cleaned.range(of: "(?s)\\[.*\\]", options: .regularExpression),
           let data = String(cleaned[range]).data(using: .utf8),
           let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            return arr
        }

        return []
    }

    // MARK: - Status Tracking

    private func updateStatus(status: String, propositions: Int, transcripts: Int, total: Int, on db: Database) async throws {
        let entity = "propositions"
        if let existing = try await SyncStatus.query(on: db)
            .filter(\.$entityName == entity)
            .first() {
            existing.status = status
            existing.lastSyncAt = Date()
            existing.itemsSynced = propositions
            existing.errorMessage = "Extracted \(propositions) Propositions from \(transcripts)/\(total) Transcripts"
            try await existing.update(on: db)
        } else {
            let syncStatus = SyncStatus(entityName: entity, sessionID: 0, status: status, itemsSynced: propositions)
            syncStatus.lastSyncAt = Date()
            syncStatus.errorMessage = "Extracted \(propositions) Propositions from \(transcripts)/\(total) Transcripts"
            try await syncStatus.create(on: db)
        }
    }
}
