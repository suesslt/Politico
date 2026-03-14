import Fluent
import Vapor

struct CreateUsersTable: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema("users")
            .field("id", .int, .identifier(auto: true))
            .field("username", .string, .required)
            .field("password_hash", .string, .required)
            .field("role", .string, .required)
            .field("email", .string)
            .field("created_at", .datetime)
            .unique(on: "username")
            .create()

        // Seed admin user (password: "admin")
        let passwordHash = try Bcrypt.hash("admin")
        let admin = User(username: "admin", passwordHash: passwordHash, role: "admin", email: "admin@politico.ch")
        try await admin.create(on: database)
    }

    func revert(on database: Database) async throws {
        try await database.schema("users").delete()
    }
}
