import Vapor
import Fluent

struct PropositionController: RouteCollection {
    func boot(routes: RoutesBuilder) throws {
        routes.post("propositions", "extract", use: startExtraction)
        routes.post("propositions", "stop", use: stopExtraction)
        routes.get("propositions", "status", use: extractionStatus)
    }

    @Sendable
    func startExtraction(req: Request) async throws -> PropositionStatusResponse {
        // Check if already running (allow restart if stuck for > 10 min)
        if let existing = try await SyncStatus.query(on: req.db)
            .filter(\.$entityName == "propositions")
            .filter(\.$status == "extracting")
            .first() {
            let staleThreshold = Date().addingTimeInterval(-600)
            if let lastUpdate = existing.lastSyncAt, lastUpdate > staleThreshold {
                return PropositionStatusResponse(
                    status: existing.status,
                    message: existing.errorMessage ?? "Already running",
                    propositionCount: existing.itemsSynced,
                    lastUpdated: existing.lastSyncAt
                )
            }
            // Stale — reset and allow restart
            existing.status = "failed"
            existing.errorMessage = "Reset: previous extraction timed out"
            try await existing.update(on: req.db)
        }

        // Start extraction in background
        let app = req.application
        Task {
            let service = PropositionService(app: app)
            do {
                try await service.extractAll(on: app.db)
            } catch {
                app.logger.error("Proposition extraction failed: \(String(reflecting: error))")
                if let status = try? await SyncStatus.query(on: app.db)
                    .filter(\.$entityName == "propositions")
                    .first() {
                    status.status = "failed"
                    status.errorMessage = error.localizedDescription
                    try? await status.update(on: app.db)
                }
            }
        }

        return PropositionStatusResponse(
            status: "started",
            message: "Extraction started",
            propositionCount: 0,
            lastUpdated: Date()
        )
    }

    @Sendable
    func stopExtraction(req: Request) async throws -> PropositionStatusResponse {
        PropositionCancellation.shared.cancel()
        req.logger.info("Proposition extraction stop requested")

        return PropositionStatusResponse(
            status: "stopping",
            message: "Stop requested, waiting for current batch to finish...",
            propositionCount: 0,
            lastUpdated: Date()
        )
    }

    @Sendable
    func extractionStatus(req: Request) async throws -> PropositionStatusResponse {
        let status = try await SyncStatus.query(on: req.db)
            .filter(\.$entityName == "propositions")
            .first()

        return PropositionStatusResponse(
            status: status?.status ?? "idle",
            message: status?.errorMessage ?? "No extraction started yet",
            propositionCount: status?.itemsSynced ?? 0,
            lastUpdated: status?.lastSyncAt
        )
    }
}

struct PropositionStatusResponse: Content {
    let status: String
    let message: String
    let propositionCount: Int
    let lastUpdated: Date?
}
