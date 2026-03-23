import Fluent
import SQLKit

struct SeparatePersonFromMemberCouncil: AsyncMigration {
    func prepare(on database: Database) async throws {
        let sql = database as! SQLDatabase

        // 1. Create person table
        try await sql.raw("""
            CREATE TABLE "person" (
                "id"                 INTEGER PRIMARY KEY,
                "first_name"         TEXT NOT NULL,
                "last_name"          TEXT NOT NULL,
                "official_name"      TEXT,
                "gender"             TEXT,
                "date_of_birth"      DATE,
                "date_of_death"      DATE,
                "marital_status"     TEXT,
                "number_of_children" INTEGER,
                "birth_place_city"   TEXT,
                "birth_place_canton" TEXT,
                "citizenship"        TEXT,
                "military_rank"      TEXT,
                "nationality"        TEXT,
                "native_language"    TEXT,
                "modified"           TIMESTAMP WITH TIME ZONE
            )
        """).run()

        // 2. Migrate person data from member_council
        try await sql.raw("""
            INSERT INTO "person" ("id", "first_name", "last_name", "official_name", "gender",
                "date_of_birth", "marital_status", "number_of_children",
                "birth_place_city", "birth_place_canton", "citizenship", "military_rank",
                "nationality", "modified")
            SELECT "id", "first_name", "last_name", "official_name", "gender",
                "date_of_birth", "marital_status", "number_of_children",
                "birth_place_city", "birth_place_canton", "citizenship", "military_rank",
                "nationality", "modified"
            FROM "member_council"
        """).run()

        // 3. Add person_id FK to member_council
        try await sql.raw("""
            ALTER TABLE "member_council"
            ADD COLUMN "person_id" INTEGER REFERENCES "person"("id")
        """).run()

        try await sql.raw("""
            UPDATE "member_council" SET "person_id" = "id"
        """).run()

        try await sql.raw("""
            ALTER TABLE "member_council"
            ALTER COLUMN "person_id" SET NOT NULL
        """).run()

        // 4. Drop person columns from member_council
        let dropColumns = [
            "first_name", "last_name", "official_name", "gender",
            "date_of_birth", "marital_status", "number_of_children",
            "birth_place_city", "birth_place_canton", "citizenship",
            "military_rank", "nationality"
        ]
        for col in dropColumns {
            try await sql.raw("""
                ALTER TABLE "member_council" DROP COLUMN IF EXISTS "\(unsafeRaw: col)"
            """).run()
        }

        // 5. Move person_interest FK from member_council_id to person_id
        try await sql.raw("""
            ALTER TABLE "person_interest"
            ADD COLUMN "person_id" INTEGER REFERENCES "person"("id")
        """).run()

        try await sql.raw("""
            UPDATE "person_interest" SET "person_id" = "member_council_id"
        """).run()

        try await sql.raw("""
            ALTER TABLE "person_interest" DROP COLUMN IF EXISTS "member_council_id"
        """).run()

        // 6. Create member_council_history table
        try await sql.raw("""
            CREATE TABLE "member_council_history" (
                "id"           TEXT PRIMARY KEY,
                "person_id"    INTEGER NOT NULL REFERENCES "person"("id"),
                "council_id"   INTEGER REFERENCES "council"("id"),
                "date_joining"  DATE,
                "date_leaving"  TIMESTAMP WITH TIME ZONE
            )
        """).run()
    }

    func revert(on database: Database) async throws {
        let sql = database as! SQLDatabase

        // Drop history table
        try await sql.raw("""
            DROP TABLE IF EXISTS "member_council_history"
        """).run()

        // Restore person_interest FK
        try await sql.raw("""
            ALTER TABLE "person_interest"
            ADD COLUMN "member_council_id" INTEGER REFERENCES "member_council"("id")
        """).run()
        try await sql.raw("""
            UPDATE "person_interest" SET "member_council_id" = "person_id"
        """).run()
        try await sql.raw("""
            ALTER TABLE "person_interest" DROP COLUMN IF EXISTS "person_id"
        """).run()

        // Restore columns on member_council from person
        let addColumns = [
            ("first_name", "TEXT NOT NULL DEFAULT ''"),
            ("last_name", "TEXT NOT NULL DEFAULT ''"),
            ("official_name", "TEXT"),
            ("gender", "TEXT"),
            ("date_of_birth", "DATE"),
            ("marital_status", "TEXT"),
            ("number_of_children", "INTEGER"),
            ("birth_place_city", "TEXT"),
            ("birth_place_canton", "TEXT"),
            ("citizenship", "TEXT"),
            ("military_rank", "TEXT"),
            ("nationality", "TEXT")
        ]
        for (col, typ) in addColumns {
            try await sql.raw("""
                ALTER TABLE "member_council" ADD COLUMN IF NOT EXISTS "\(unsafeRaw: col)" \(unsafeRaw: typ)
            """).run()
        }

        // Copy data back
        try await sql.raw("""
            UPDATE "member_council" mc SET
                "first_name" = p."first_name",
                "last_name" = p."last_name",
                "official_name" = p."official_name",
                "gender" = p."gender",
                "date_of_birth" = p."date_of_birth",
                "marital_status" = p."marital_status",
                "number_of_children" = p."number_of_children",
                "birth_place_city" = p."birth_place_city",
                "birth_place_canton" = p."birth_place_canton",
                "citizenship" = p."citizenship",
                "military_rank" = p."military_rank",
                "nationality" = p."nationality"
            FROM "person" p WHERE mc."person_id" = p."id"
        """).run()

        // Drop person_id from member_council
        try await sql.raw("""
            ALTER TABLE "member_council" DROP COLUMN IF EXISTS "person_id"
        """).run()

        // Drop person table
        try await sql.raw("""
            DROP TABLE IF EXISTS "person"
        """).run()
    }
}
