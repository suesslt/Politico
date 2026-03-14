import Vapor
import Fluent

struct SessionController: RouteCollection {
    func boot(routes: RoutesBuilder) throws {
        routes.get("sessions", use: index)
        routes.post("sessions", "refresh", use: refresh)
        routes.get("sessions", ":sessionID", use: show)
    }

    @Sendable
    func index(req: Request) async throws -> View {
        // Sessions
        let sessions = try await Session.query(on: req.db)
            .sort(\.$startDate, .descending)
            .all()

        let syncStatuses = try await SyncStatus.query(on: req.db)
            .filter(\.$entityName == "full_sync")
            .all()

        let statusMap = Dictionary(uniqueKeysWithValues: syncStatuses.compactMap { status -> (Int, String)? in
            guard let sessionID = status.sessionID else { return nil }
            return (sessionID, status.status)
        })

        let sessionContexts = sessions.map { session in
            SessionContext(
                id: session.id ?? 0,
                sessionName: session.sessionName ?? session.title,
                title: session.title,
                abbreviation: session.abbreviation ?? "",
                startDate: session.startDate.map { formatDate($0) } ?? "",
                endDate: session.endDate.map { formatDate($0) } ?? "",
                syncStatus: statusMap[session.id ?? 0] ?? "not_synced"
            )
        }

        // Members with eager-loaded relationships
        let members = try await MemberCouncil.query(on: req.db)
            .with(\.$party)
            .with(\.$faction)
            .with(\.$canton)
            .with(\.$council)
            .filter(\.$active == true)
            .sort(\.$lastName)
            .sort(\.$firstName)
            .all()

        let memberContexts = members.map { m in
            MemberContext(
                id: m.id ?? 0,
                firstName: m.firstName,
                lastName: m.lastName,
                party: m.party?.abbreviation ?? "-",
                partyColor: m.party?.color ?? "#6c757d",
                faction: m.faction?.abbreviation ?? "-",
                canton: m.canton?.abbreviation ?? "-",
                council: m.council?.abbreviation ?? "-",
                occupation: m.occupationName ?? ""
            )
        }

        // Businesses
        let businesses = try await Business.query(on: req.db)
            .with(\.$businessType)
            .sort(\.$submissionDate, .descending)
            .range(..<200)
            .all()

        let businessContexts = businesses.map { b in
            BusinessContext(
                id: b.id ?? 0,
                shortNumber: b.businessShortNumber ?? "",
                title: b.title,
                typeName: b.businessType?.name ?? "",
                statusText: b.businessStatusText ?? ""
            )
        }

        // Transcripts
        let transcripts = try await Transcript.query(on: req.db)
            .sort(\.$meetingDate, .descending)
            .sort(\.$sortOrder)
            .range(..<500)
            .all()

        let transcriptContexts = transcripts.map { t in
            TranscriptContext(
                id: t.id ?? 0,
                speakerFullName: t.speakerFullName ?? "-",
                speakerFunction: t.speakerFunction ?? "",
                meetingDate: t.meetingDate.map { formatDate($0) } ?? "",
                councilName: t.councilName ?? "",
                faction: t.parlGroupAbbreviation ?? "",
                canton: t.cantonAbbreviation ?? "",
                textPreview: String((t.text ?? "").prefix(200)).replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            )
        }

        // Meetings grouped by Session → Council → Date
        let meetingSessions = try await Session.query(on: req.db)
            .sort(\.$startDate, .descending)
            .all()

        var meetingSessionGroups: [MeetingSessionGroup] = []
        for sess in meetingSessions {
            let sessID = sess.id ?? 0
            let meetings = try await Meeting.query(on: req.db)
                .with(\.$council)
                .filter(\.$session.$id == sessID)
                .sort(\.$date, .descending)
                .all()

            if meetings.isEmpty { continue }

            // Load subject_business for all meetings in this session
            let meetingIDs = meetings.compactMap { $0.id }
            let subjects = try await Subject.query(on: req.db)
                .filter(\.$idMeeting ~~ meetingIDs)
                .all()
            let subjectIDs = subjects.compactMap { $0.id }
            let subjectBusinesses = subjectIDs.isEmpty ? [SubjectBusiness]() :
                try await SubjectBusiness.query(on: req.db)
                    .filter(\.$idSubject ~~ subjectIDs)
                    .all()

            // Build lookup: meetingID → [business titles]
            let subjectByMeeting = Dictionary(grouping: subjects, by: { $0.idMeeting })
            var meetingBusinessMap: [Int: [String]] = [:]
            for (meetingID, meetingSubjects) in subjectByMeeting {
                guard let meetingID = meetingID else { continue }
                let sIDs = Set(meetingSubjects.compactMap { $0.id })
                let titles = subjectBusinesses
                    .filter { sb in sb.idSubject.map { sIDs.contains($0) } ?? false }
                    .compactMap { $0.title }
                // Deduplicate
                meetingBusinessMap[meetingID] = Array(Set(titles)).sorted()
            }

            // Group by council (NR first, then SR, then others)
            let councilOrder = ["NR", "SR"]
            let grouped = Dictionary(grouping: meetings) { $0.council?.abbreviation ?? "-" }
            let sortedKeys = grouped.keys.sorted { a, b in
                let ai = councilOrder.firstIndex(of: a) ?? 99
                let bi = councilOrder.firstIndex(of: b) ?? 99
                return ai < bi
            }

            var councilGroups: [MeetingCouncilGroup] = []
            for key in sortedKeys {
                guard let councilMeetings = grouped[key] else { continue }
                let councilName = councilMeetings.first?.council?.name ?? key

                // Group by date within council
                let byDate = Dictionary(grouping: councilMeetings) { m in
                    m.date.map { formatDate($0) } ?? ""
                }
                let sortedDates = byDate.keys.sorted { $0 > $1 }

                var dateGroups: [MeetingDateGroup] = []
                for (idx, dateStr) in sortedDates.enumerated() {
                    guard let dateMeetings = byDate[dateStr] else { continue }
                    let businessTitles = dateMeetings.flatMap { m in
                        meetingBusinessMap[m.id ?? 0] ?? []
                    }
                    let uniqueTitles = Array(Set(businessTitles)).sorted()
                    let collapseID = "collapse-\(sessID)-\(key)-\(idx)"
                    dateGroups.append(MeetingDateGroup(
                        id: collapseID,
                        date: dateStr,
                        businessCount: uniqueTitles.count,
                        businesses: uniqueTitles
                    ))
                }

                councilGroups.append(MeetingCouncilGroup(
                    councilAbbreviation: key,
                    councilName: councilName,
                    dates: dateGroups
                ))
            }

            meetingSessionGroups.append(MeetingSessionGroup(
                sessionName: sess.sessionName ?? sess.title,
                sessionDates: "\(sess.startDate.map { formatDate($0) } ?? "") - \(sess.endDate.map { formatDate($0) } ?? "")",
                councils: councilGroups
            ))
        }

        let context = DashboardContext(
            sessions: sessionContexts,
            members: memberContexts,
            businesses: businessContexts,
            transcripts: transcriptContexts,
            meetingGroups: meetingSessionGroups
        )

        return try await req.view.render("sessions", context)
    }

    @Sendable
    func refresh(req: Request) async throws -> Response {
        let dtos = try await req.application.parlamentService.fetchSessions()
        for dto in dtos {
            if let existing = try await Session.find(dto.ID, on: req.db) {
                existing.sessionName = dto.SessionName ?? existing.sessionName
                existing.title = dto.Title ?? existing.title
                existing.abbreviation = dto.Abbreviation ?? existing.abbreviation
                existing.startDate = dto.startDateParsed ?? existing.startDate
                existing.endDate = dto.endDateParsed ?? existing.endDate
                existing.modified = dto.modifiedParsed ?? existing.modified
                try await existing.update(on: req.db)
            } else {
                let session = Session(
                    id: dto.ID,
                    title: dto.Title ?? "Session \(dto.ID)",
                    sessionName: dto.SessionName,
                    abbreviation: dto.Abbreviation,
                    startDate: dto.startDateParsed,
                    endDate: dto.endDateParsed,
                    modified: dto.modifiedParsed
                )
                try await session.create(on: req.db)
            }
        }
        return req.redirect(to: "/sessions")
    }

    @Sendable
    func show(req: Request) async throws -> View {
        guard let sessionID = req.parameters.get("sessionID", as: Int.self) else {
            throw Abort(.badRequest, reason: "Invalid session ID")
        }
        guard let session = try await Session.find(sessionID, on: req.db) else {
            throw Abort(.notFound)
        }

        let businesses = try await Business.query(on: req.db)
            .with(\.$businessType)
            .filter(\.$session.$id == sessionID)
            .sort(\.$submissionDate, .descending)
            .all()

        let votes = try await Vote.query(on: req.db)
            .filter(\.$session.$id == sessionID)
            .all()

        let context = SessionDetailContext(
            id: session.id ?? 0,
            title: session.title,
            abbreviation: session.abbreviation ?? "",
            startDate: session.startDate.map { formatDate($0) } ?? "",
            endDate: session.endDate.map { formatDate($0) } ?? "",
            businessCount: businesses.count,
            voteCount: votes.count,
            businesses: businesses.map { b in
                BusinessContext(
                    id: b.id ?? 0,
                    shortNumber: b.businessShortNumber ?? "",
                    title: b.title,
                    typeName: b.businessType?.name ?? "",
                    statusText: b.businessStatusText ?? ""
                )
            }
        )

        return try await req.view.render("session-detail", context)
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "dd.MM.yyyy"
        return formatter.string(from: date)
    }
}

// MARK: - Contexts

struct DashboardContext: Encodable {
    let sessions: [SessionContext]
    let members: [MemberContext]
    let businesses: [BusinessContext]
    let transcripts: [TranscriptContext]
    let meetingGroups: [MeetingSessionGroup]
}

struct MeetingSessionGroup: Encodable {
    let sessionName: String
    let sessionDates: String
    let councils: [MeetingCouncilGroup]
}

struct MeetingCouncilGroup: Encodable {
    let councilAbbreviation: String
    let councilName: String
    let dates: [MeetingDateGroup]
}

struct MeetingDateGroup: Encodable {
    let id: String
    let date: String
    let businessCount: Int
    let businesses: [String]
}

struct SessionContext: Encodable {
    let id: Int
    let sessionName: String
    let title: String
    let abbreviation: String
    let startDate: String
    let endDate: String
    let syncStatus: String
}

struct MemberContext: Encodable {
    let id: Int
    let firstName: String
    let lastName: String
    let party: String
    let partyColor: String
    let faction: String
    let canton: String
    let council: String
    let occupation: String
}

struct SessionDetailContext: Encodable {
    let id: Int
    let title: String
    let abbreviation: String
    let startDate: String
    let endDate: String
    let businessCount: Int
    let voteCount: Int
    let businesses: [BusinessContext]
}

struct BusinessContext: Encodable {
    let id: Int
    let shortNumber: String
    let title: String
    let typeName: String
    let statusText: String
}

struct TranscriptContext: Encodable {
    let id: Int
    let speakerFullName: String
    let speakerFunction: String
    let meetingDate: String
    let councilName: String
    let faction: String
    let canton: String
    let textPreview: String
}
