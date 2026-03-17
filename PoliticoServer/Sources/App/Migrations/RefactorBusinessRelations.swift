import Fluent
import SQLKit

struct RefactorBusinessRelations: AsyncMigration {
    func prepare(on database: Database) async throws {
        guard let sql = database as? SQLDatabase else { return }

        // 1. Create department table
        try await database.schema("department")
            .field("id", .int, .identifier(auto: true))
            .field("name", .string, .required)
            .field("abbreviation", .string)
            .unique(on: "name")
            .create()

        // Populate from existing data
        try await sql.raw("""
            INSERT INTO "department" ("name", "abbreviation")
            SELECT DISTINCT "responsible_department_name", "responsible_department_abbreviation"
            FROM "business"
            WHERE "responsible_department_name" IS NOT NULL
            ON CONFLICT ("name") DO NOTHING
            """).run()

        // 2. Add FK columns
        try await database.schema("business")
            .field("submission_council_id", .int, .references("council", "id"))
            .field("responsible_department_id", .int, .references("department", "id"))
            .update()

        // 3. Backfill submission_council_id from council table
        try await sql.raw("""
            UPDATE "business" b
            SET "submission_council_id" = c."id"
            FROM "council" c
            WHERE b."submission_council_name" = c."name"
            """).run()

        // 4. Backfill responsible_department_id
        try await sql.raw("""
            UPDATE "business" b
            SET "responsible_department_id" = d."id"
            FROM "department" d
            WHERE b."responsible_department_name" = d."name"
            """).run()

        // 5. Drop old columns
        try await database.schema("business")
            .deleteField("submission_council_name")
            .deleteField("responsible_department_name")
            .deleteField("responsible_department_abbreviation")
            .update()
    }

    func revert(on database: Database) async throws {
        guard let sql = database as? SQLDatabase else { return }

        try await database.schema("business")
            .field("submission_council_name", .string)
            .field("responsible_department_name", .string)
            .field("responsible_department_abbreviation", .string)
            .update()

        try await sql.raw("""
            UPDATE "business" b
            SET "submission_council_name" = c."name"
            FROM "council" c
            WHERE b."submission_council_id" = c."id"
            """).run()

        try await sql.raw("""
            UPDATE "business" b
            SET "responsible_department_name" = d."name",
                "responsible_department_abbreviation" = d."abbreviation"
            FROM "department" d
            WHERE b."responsible_department_id" = d."id"
            """).run()

        try await database.schema("business")
            .deleteField("submission_council_id")
            .deleteField("responsible_department_id")
            .update()

        try await database.schema("department").delete()
    }
}
