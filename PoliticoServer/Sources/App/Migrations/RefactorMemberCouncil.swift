import Fluent

struct RefactorMemberCouncil: AsyncMigration {
    func prepare(on database: Database) async throws {
        // Create cantons table
        try await database.schema("cantons")
            .field("id", .int, .identifier(auto: true))
            .field("name", .string)
            .field("abbreviation", .string, .required)
            .unique(on: "abbreviation")
            .create()

        // Add canton_id FK, remove redundant columns
        try await database.schema("member_councils")
            .field("canton_id", .int, .references("cantons", "id"))
            .deleteField("council_name")
            .deleteField("council_abbreviation")
            .deleteField("party_abbreviation")
            .deleteField("party_name")
            .deleteField("parl_group_abbreviation")
            .deleteField("parl_group_name")
            .deleteField("canton_abbreviation")
            .deleteField("canton_name")
            .update()
    }

    func revert(on database: Database) async throws {
        try await database.schema("member_councils")
            .deleteField("canton_id")
            .field("council_name", .string)
            .field("council_abbreviation", .string)
            .field("party_abbreviation", .string)
            .field("party_name", .string)
            .field("parl_group_abbreviation", .string)
            .field("parl_group_name", .string)
            .field("canton_abbreviation", .string)
            .field("canton_name", .string)
            .update()

        try await database.schema("cantons").delete()
    }
}
