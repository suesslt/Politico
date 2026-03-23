import Vapor
import Fluent
import FluentPostgresDriver
import Leaf

func configure(_ app: Application) async throws {
    // MARK: - Database
    let dbHost = Environment.get("DB_HOST") ?? "192.168.1.144"
    let dbPort = Environment.get("DB_PORT").flatMap(Int.init) ?? 5432
    let dbUser = Environment.get("DB_USER") ?? "politscore"
    let dbPass = Environment.get("DB_PASSWORD") ?? "politscore"
    let dbName = Environment.get("DB_NAME") ?? "politscore"

    let dbConfig = SQLPostgresConfiguration(
        hostname: dbHost,
        port: dbPort,
        username: dbUser,
        password: dbPass,
        database: dbName,
        tls: .disable
    )
    app.databases.use(.postgres(configuration: dbConfig, connectionPoolTimeout: .seconds(30)), as: .psql)
    app.databases.default(to: .psql)

    // MARK: - Middleware
    app.middleware.use(FileMiddleware(publicDirectory: app.directory.publicDirectory))
    app.sessions.use(.fluent)
    app.middleware.use(app.sessions.middleware)

    // MARK: - Leaf
    app.views.use(.leaf)

    // MARK: - Migrations
    app.migrations.add(SessionRecord.migration)
    app.migrations.add(CreateInitialSchema())
    app.migrations.add(CreateUsersTable())
    app.migrations.add(AddSessionName())
    app.migrations.add(RefactorMemberCouncil())
    app.migrations.add(AddMemberCouncilDetails())
    app.migrations.add(MoveOccupationToMember())
    app.migrations.add(FixPersonInterestPaid())
    app.migrations.add(RenameTablesToSingular())
    app.migrations.add(AddPartyColor())
    app.migrations.add(ExtractBusinessType())
    app.migrations.add(RefactorMeetingCouncil())
    app.migrations.add(BackfillTranscriptDates())
    app.migrations.add(RefactorBusinessRelations())
    app.migrations.add(DropMeetingSessionName())
    app.migrations.add(DropSubjectVerbalixOid())
    app.migrations.add(RefactorSubjectBusiness())
    app.migrations.add(RefactorTranscript())
    app.migrations.add(AddSubjectBusinessFKs())
    app.migrations.add(RenameSubjectMeetingId())
    app.migrations.add(RefactorVotingMemberCouncil())
    app.migrations.add(RefactorVoteBusiness())
    app.migrations.add(RenameBusinessColumns())
    app.migrations.add(RefactorMeetingColumns())
    app.migrations.add(RefactorPersonInterest())
    app.migrations.add(RefactorSessionName())
    app.migrations.add(ChangeTimestampsToDate())
    app.migrations.add(RenamePersonInterestFK())
    app.migrations.add(DropMemberCouncilPersonNumber())
    app.migrations.add(AddSubjectTranscriptFKs())
    app.migrations.add(ChangeIDsToIdentity())
    app.migrations.add(CreateCommitteeTables())
    app.migrations.add(AddSubmittedByCouncil())
    app.migrations.add(AddBusinessTexts())
    app.migrations.add(CreatePropositions())
    app.migrations.add(CreateTranscriptEmbeddings())
    app.migrations.add(SeparatePersonFromMemberCouncil())

    try await app.autoMigrate()

    // MARK: - Services
    app.parlamentService = ParlamentService(client: app.client, logger: app.logger)

    // MARK: - Routes
    try routes(app)
}
