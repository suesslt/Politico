import Fluent
import SQLKit

struct AddPartyColor: AsyncMigration {
    // Source: https://github.com/srfdata/swiss-party-colors (SRF Data)
    private let partyColors: [(abbreviation: String, color: String)] = [
        ("SP", "#F0554D"),
        ("SVP", "#4B8A3E"),
        ("FDP-Liberale", "#3872B5"),
        ("GRÜNE", "#84B547"),
        ("glp", "#C4C43D"),
        ("EVP", "#DEAA28"),
        ("EDU", "#A65E42"),
        ("Lega", "#9070D4"),
        ("M-E", "#D6862B"),
        ("MCG", "#49A5E7"),
        ("Al", "#A83232"),
        ("LDP", "#618DEA"),
    ]

    func prepare(on database: Database) async throws {
        try await database.schema("party")
            .field("color", .string)
            .update()

        guard let sql = database as? SQLDatabase else { return }
        for party in partyColors {
            try await sql.raw("""
                UPDATE "party" SET "color" = \(bind: party.color) WHERE "abbreviation" = \(bind: party.abbreviation)
                """).run()
        }
    }

    func revert(on database: Database) async throws {
        try await database.schema("party")
            .deleteField("color")
            .update()
    }
}
