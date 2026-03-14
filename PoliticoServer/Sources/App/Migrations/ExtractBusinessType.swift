import Fluent
import SQLKit

struct ExtractBusinessType: AsyncMigration {
    func prepare(on database: Database) async throws {
        // Create business_type table
        try await database.schema("business_type")
            .field("id", .int, .identifier(auto: true))
            .field("name", .string, .required)
            .field("abbreviation", .string)
            .unique(on: "name")
            .create()

        guard let sql = database as? SQLDatabase else { return }

        // Populate from existing data
        try await sql.raw("""
            INSERT INTO "business_type" ("name", "abbreviation")
            SELECT DISTINCT "business_type_name", "business_type_abbreviation"
            FROM "business"
            WHERE "business_type_name" IS NOT NULL
            ON CONFLICT ("name") DO NOTHING
            """).run()

        // Add FK column
        try await database.schema("business")
            .field("business_type_id", .int, .references("business_type", "id"))
            .update()

        // Backfill FK
        try await sql.raw("""
            UPDATE "business" b
            SET "business_type_id" = bt."id"
            FROM "business_type" bt
            WHERE b."business_type_name" = bt."name"
            """).run()

        // Drop old columns
        try await database.schema("business")
            .deleteField("business_type_name")
            .deleteField("business_type_abbreviation")
            .update()
    }

    func revert(on database: Database) async throws {
        guard let sql = database as? SQLDatabase else { return }

        try await database.schema("business")
            .field("business_type_name", .string)
            .field("business_type_abbreviation", .string)
            .update()

        try await sql.raw("""
            UPDATE "business" b
            SET "business_type_name" = bt."name",
                "business_type_abbreviation" = bt."abbreviation"
            FROM "business_type" bt
            WHERE b."business_type_id" = bt."id"
            """).run()

        try await database.schema("business")
            .deleteField("business_type_id")
            .update()

        try await database.schema("business_type").delete()
    }
}
