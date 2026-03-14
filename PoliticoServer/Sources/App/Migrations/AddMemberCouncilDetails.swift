import Fluent

struct AddMemberCouncilDetails: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema("member_councils")
            .field("official_name", .string)
            .field("gender", .string)
            .field("date_election", .datetime)
            .field("marital_status", .string)
            .field("number_of_children", .int)
            .field("birth_place_city", .string)
            .field("birth_place_canton", .string)
            .field("citizenship", .string)
            .field("military_rank", .string)
            .field("mandates", .sql(raw: "TEXT"))
            .field("additional_mandate", .sql(raw: "TEXT"))
            .field("additional_activity", .sql(raw: "TEXT"))
            .field("modified", .datetime)
            .update()
    }

    func revert(on database: Database) async throws {
        try await database.schema("member_councils")
            .deleteField("official_name")
            .deleteField("gender")
            .deleteField("date_election")
            .deleteField("marital_status")
            .deleteField("number_of_children")
            .deleteField("birth_place_city")
            .deleteField("birth_place_canton")
            .deleteField("citizenship")
            .deleteField("military_rank")
            .deleteField("mandates")
            .deleteField("additional_mandate")
            .deleteField("additional_activity")
            .deleteField("modified")
            .update()
    }
}
