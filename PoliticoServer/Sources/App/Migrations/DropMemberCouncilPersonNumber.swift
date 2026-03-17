import Fluent

struct DropMemberCouncilPersonNumber: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema("member_council")
            .deleteField("person_number")
            .update()
    }

    func revert(on database: Database) async throws {
        try await database.schema("member_council")
            .field("person_number", .int, .required)
            .update()
    }
}
