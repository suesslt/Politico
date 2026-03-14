import Vapor
import Fluent

struct SyncController: RouteCollection {
    func boot(routes: RoutesBuilder) throws {
        routes.post("sync", ":sessionID", use: startSync)
        routes.get("sync", "status", ":sessionID", use: syncStatus)
    }

    @Sendable
    func startSync(req: Request) async throws -> Response {
        guard let sessionID = req.parameters.get("sessionID", as: Int.self) else {
            throw Abort(.badRequest, reason: "Invalid session ID")
        }

        // Check if already syncing
        if let existing = try await SyncStatus.query(on: req.db)
            .filter(\.$entityName == "full_sync")
            .filter(\.$sessionID == sessionID)
            .filter(\.$status == "syncing")
            .first() {
            _ = existing
            return req.redirect(to: "/sync/status/\(sessionID)")
        }

        // Start sync in background
        let app = req.application
        Task {
            let syncService = SyncService(app: app)
            do {
                try await syncService.syncSession(sessionID: sessionID, on: app.db)
            } catch {
                app.logger.error("Sync failed for session \(sessionID): \(error)")
                // Update status to failed
                if let status = try? await SyncStatus.query(on: app.db)
                    .filter(\.$entityName == "full_sync")
                    .filter(\.$sessionID == sessionID)
                    .first() {
                    status.status = "failed"
                    status.errorMessage = error.localizedDescription
                    try? await status.update(on: app.db)
                }
            }
        }

        return req.redirect(to: "/sync/status/\(sessionID)")
    }

    @Sendable
    func syncStatus(req: Request) async throws -> View {
        guard let sessionID = req.parameters.get("sessionID", as: Int.self) else {
            throw Abort(.badRequest, reason: "Invalid session ID")
        }

        let statuses = try await SyncStatus.query(on: req.db)
            .filter(\.$sessionID == sessionID)
            .all()

        let statusContexts = statuses.map { status in
            SyncStatusContext(
                entityName: status.entityName,
                status: status.status,
                itemsSynced: status.itemsSynced,
                lastSyncAt: status.lastSyncAt.map { formatDateTime($0) } ?? "-",
                errorMessage: status.errorMessage
            )
        }

        let context = SyncPageContext(
            sessionID: sessionID,
            statuses: statusContexts
        )

        return try await req.view.render("sync-status", context)
    }

    private func formatDateTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "dd.MM.yyyy HH:mm:ss"
        return formatter.string(from: date)
    }
}

struct SyncStatusContext: Encodable {
    let entityName: String
    let status: String
    let itemsSynced: Int
    let lastSyncAt: String
    let errorMessage: String?
}

struct SyncPageContext: Encodable {
    let sessionID: Int
    let statuses: [SyncStatusContext]
}
