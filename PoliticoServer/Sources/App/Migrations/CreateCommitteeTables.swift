import Fluent

struct CreateCommitteeTables: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema("committee")
            .field("id", .int, .identifier(auto: false))
            .field("name", .string, .required)
            .field("abbreviation", .string)
            .field("committee_type", .string)
            .field("council_id", .int, .references("council", "id"))
            .field("main_committee_id", .int, .references("committee", "id"))
            .field("modified", .datetime)
            .create()

        try await database.schema("member_committee")
            .field("id", .int, .identifier(auto: true))
            .field("member_council_id", .int, .required, .references("member_council", "id"))
            .field("committee_id", .int, .required, .references("committee", "id"))
            .field("function", .string)
            .field("modified", .datetime)
            .create()
    }

    func revert(on database: Database) async throws {
        try await database.schema("member_committee").delete()
        try await database.schema("committee").delete()
    }
}
