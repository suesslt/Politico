import Fluent

struct MoveOccupationToMember: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema("member_councils")
            .field("occupation_name", .sql(raw: "TEXT"))
            .field("employer", .sql(raw: "TEXT"))
            .field("job_title", .sql(raw: "TEXT"))
            .update()

        try await database.schema("person_occupations").delete()
    }

    func revert(on database: Database) async throws {
        try await database.schema("person_occupations")
            .field("id", .int, .identifier(auto: true))
            .field("person_number", .int, .required)
            .field("occupation_name", .string)
            .field("employer", .string)
            .field("job_title", .string)
            .create()

        try await database.schema("member_councils")
            .deleteField("occupation_name")
            .deleteField("employer")
            .deleteField("job_title")
            .update()
    }
}
