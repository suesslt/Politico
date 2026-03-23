import Vapor
import Fluent
import SQLKit

struct SessionController: RouteCollection {
    func boot(routes: RoutesBuilder) throws {
        routes.get("sessions", use: index)
        routes.post("sessions", "refresh", use: refresh)
        routes.get("sessions", ":sessionID", use: show)
        routes.get("transcripts", ":transcriptID", use: showTranscript)

        // JSON API endpoints for lazy tab loading
        let api = routes.grouped("api")
        api.get("members", use: apiMembers)
        api.get("businesses", use: apiBusinesses)
        api.get("transcripts", use: apiTranscripts)
        api.get("meetings", use: apiMeetings)
        api.get("committees", use: apiCommittees)
        api.get("scores", use: apiScores)

        // Proposition CRUD
        api.put("propositions", ":propositionID", use: updateProposition)
        api.delete("propositions", ":propositionID", use: deleteProposition)
    }

    @Sendable
    func index(req: Request) async throws -> View {
        // Only load Sessions — other tabs are lazy-loaded via /api/* endpoints
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
                sessionName: session.name,
                abbreviation: session.abbreviation ?? "",
                startDate: session.startDate.map { formatDate($0) } ?? "",
                endDate: session.endDate.map { formatDate($0) } ?? "",
                syncStatus: statusMap[session.id ?? 0] ?? "not_synced"
            )
        }

        let context = DashboardContext(
            sessions: sessionContexts
        )

        return try await req.view.render("sessions", context)
    }

    @Sendable
    func refresh(req: Request) async throws -> Response {
        let dtos = try await req.application.parlamentService.fetchSessions()
        for dto in dtos {
            if let existing = try await Session.find(dto.ID, on: req.db) {
                existing.name = dto.SessionName ?? existing.name
                existing.abbreviation = dto.Abbreviation ?? existing.abbreviation
                existing.startDate = dto.startDateParsed ?? existing.startDate
                existing.endDate = dto.endDateParsed ?? existing.endDate
                existing.modified = dto.modifiedParsed ?? existing.modified
                try await existing.update(on: req.db)
            } else {
                let session = Session(
                    id: dto.ID,
                    name: dto.SessionName ?? dto.Title ?? "Session \(dto.ID)",
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
            .with(\.$submittedByCouncil) { mc in mc.with(\.$party); mc.with(\.$person) }
            .filter(\.$session.$id == sessionID)
            .sort(\.$submissionDate, .descending)
            .all()

        let votes = try await Vote.query(on: req.db)
            .filter(\.$session.$id == sessionID)
            .all()

        let context = SessionDetailContext(
            id: session.id ?? 0,
            title: session.name,
            abbreviation: session.abbreviation ?? "",
            startDate: session.startDate.map { formatDate($0) } ?? "",
            endDate: session.endDate.map { formatDate($0) } ?? "",
            businessCount: businesses.count,
            voteCount: votes.count,
            businesses: businesses.map { b in
                let sbc = b.submittedByCouncil
                return BusinessContext(
                    id: b.id ?? 0,
                    shortNumber: b.number ?? "",
                    title: b.title,
                    typeName: b.businessType?.name ?? "",
                    statusText: b.status ?? "",
                    submittedBy: b.submittedBy ?? "",
                    submittedByID: sbc?.id,
                    submittedByName: sbc.map { "\($0.person.firstName) \($0.person.lastName)" },
                    submittedByPartyColor: sbc?.party?.color
                )
            }
        )

        return try await req.view.render("session-detail", context)
    }

    // MARK: - Transcript Detail

    @Sendable
    func showTranscript(req: Request) async throws -> View {
        guard let transcriptID = req.parameters.get("transcriptID", as: Int.self) else {
            throw Abort(.badRequest, reason: "Invalid transcript ID")
        }
        guard let transcript = try await Transcript.find(transcriptID, on: req.db) else {
            throw Abort(.notFound)
        }

        // Load speaker
        try await transcript.$memberCouncil.load(on: req.db)
        if let mc = transcript.memberCouncil {
            try await mc.$party.load(on: req.db)
            try await mc.$person.load(on: req.db)
        }

        // Load propositions with subjects
        let propositions = try await Proposition.query(on: req.db)
            .filter(\.$transcript.$id == transcriptID)
            .with(\.$propositionSubject)
            .sort(\.$id)
            .all()

        // Load all subjects for the dropdown
        let subjects = try await PropositionSubject.query(on: req.db)
            .sort(\.$name)
            .all()

        let backURL = req.url.query.flatMap {
            URLComponents(string: "?\($0)")?.queryItems?.first(where: { $0.name == "from" })?.value
        } ?? "wortmeldungen"

        let mc = transcript.memberCouncil
        let context = TranscriptDetailContext(
            id: transcriptID,
            speakerFullName: mc.map { "\($0.person.firstName) \($0.person.lastName)" } ?? "Unbekannt",
            speakerID: mc?.id,
            party: mc?.party?.abbreviation ?? "-",
            partyColor: mc?.party?.color ?? "#6c757d",
            meetingDate: transcript.meetingDate.map { formatDate($0) } ?? "",
            htmlText: transcript.text ?? "",
            backURL: backURL,
            propositions: propositions.map { p in
                PropositionDetailContext(
                    id: p.id ?? 0,
                    text: p.text,
                    subjectName: p.propositionSubject?.name ?? "",
                    subjectID: p.$propositionSubject.id,
                    source: p.source ?? "",
                    dateText: p.dateText ?? ""
                )
            },
            subjects: subjects.map { s in
                SubjectOption(id: s.id ?? 0, name: s.name)
            }
        )

        return try await req.view.render("transcript-detail", context)
    }

    // MARK: - Proposition CRUD

    struct PropositionUpdateRequest: Content {
        let text: String
        let subjectID: Int?
        let source: String?
        let dateText: String?
    }

    @Sendable
    func updateProposition(req: Request) async throws -> HTTPStatus {
        guard let propID = req.parameters.get("propositionID", as: Int.self) else {
            throw Abort(.badRequest)
        }
        guard let proposition = try await Proposition.find(propID, on: req.db) else {
            throw Abort(.notFound)
        }
        let update = try req.content.decode(PropositionUpdateRequest.self)
        proposition.text = update.text
        proposition.$propositionSubject.id = update.subjectID
        proposition.source = update.source
        proposition.dateText = update.dateText
        try await proposition.update(on: req.db)
        return .ok
    }

    @Sendable
    func deleteProposition(req: Request) async throws -> HTTPStatus {
        guard let propID = req.parameters.get("propositionID", as: Int.self) else {
            throw Abort(.badRequest)
        }
        guard let proposition = try await Proposition.find(propID, on: req.db) else {
            throw Abort(.notFound)
        }
        try await proposition.delete(on: req.db)
        return .ok
    }

    // MARK: - JSON API endpoints for lazy tab loading

    @Sendable
    func apiMembers(req: Request) async throws -> [MemberContext] {
        let members = try await MemberCouncil.query(on: req.db)
            .with(\.$person)
            .with(\.$party)
            .with(\.$faction)
            .with(\.$canton)
            .with(\.$council)
            .sort(\.$active, .descending)
            .all()
            .sorted { a, b in
                if a.active != b.active { return a.active && !b.active }
                if a.person.lastName != b.person.lastName { return a.person.lastName < b.person.lastName }
                return a.person.firstName < b.person.firstName
            }

        return members.map { m in
            MemberContext(
                id: m.id ?? 0,
                firstName: m.person.firstName,
                lastName: m.person.lastName,
                party: m.party?.abbreviation ?? "-",
                partyColor: m.party?.color ?? "#6c757d",
                faction: m.faction?.abbreviation ?? "-",
                canton: m.canton?.abbreviation ?? "-",
                council: m.council?.abbreviation ?? "-",
                occupation: m.occupationName ?? "",
                active: m.active
            )
        }
    }

    @Sendable
    func apiBusinesses(req: Request) async throws -> [BusinessContext] {
        let businesses = try await Business.query(on: req.db)
            .with(\.$businessType)
            .with(\.$submittedByCouncil) { mc in mc.with(\.$party); mc.with(\.$person) }
            .sort(\.$submissionDate, .descending)
            .all()

        return businesses.map { b in
            let sbc = b.submittedByCouncil
            return BusinessContext(
                id: b.id ?? 0,
                shortNumber: b.number ?? "",
                title: b.title,
                typeName: b.businessType?.name ?? "",
                statusText: b.status ?? "",
                submittedBy: b.submittedBy ?? "",
                submittedByID: sbc?.id,
                submittedByName: sbc.map { "\($0.person.firstName) \($0.person.lastName)" },
                submittedByPartyColor: sbc?.party?.color
            )
        }
    }

    @Sendable
    func apiTranscripts(req: Request) async throws -> [TranscriptContext] {
        let transcripts = try await Transcript.query(on: req.db)
            .with(\.$memberCouncil) { mc in
                mc.with(\.$party)
                mc.with(\.$person)
            }
            .sort(\.$meetingDate, .descending)
            .sort(\.$sortOrder)
            .all()

        let transcriptSubjectIDs = Set(transcripts.compactMap { $0.$subject.id })
        let transcriptSBs = transcriptSubjectIDs.isEmpty ? [SubjectBusiness]() :
            try await SubjectBusiness.query(on: req.db)
                .filter(\.$subjectID ~~ transcriptSubjectIDs)
                .all()
        let transcriptBizIDs = Set(transcriptSBs.compactMap { $0.businessID })
        let transcriptBusinesses = transcriptBizIDs.isEmpty ? [Business]() :
            try await Business.query(on: req.db)
                .filter(\.$id ~~ transcriptBizIDs)
                .all()
        let bizByID = Dictionary(uniqueKeysWithValues: transcriptBusinesses.compactMap { b -> (Int, Business)? in
            guard let id = b.id else { return nil }
            return (id, b)
        })
        var subjectToBusiness: [Int: Business] = [:]
        for sb in transcriptSBs {
            guard let sid = sb.subjectID, subjectToBusiness[sid] == nil,
                  let bizID = sb.businessID, let biz = bizByID[bizID] else { continue }
            subjectToBusiness[sid] = biz
        }

        // Load proposition counts per transcript
        let transcriptIDs = transcripts.compactMap { $0.id }
        let propositions = try await Proposition.query(on: req.db)
            .filter(\.$transcript.$id ~~ transcriptIDs)
            .all()
        let propCountByTranscript = Dictionary(grouping: propositions, by: { $0.$transcript.id })
            .mapValues { $0.count }

        return transcripts.map { t in
            let mc = t.memberCouncil
            let party = mc?.party
            let biz = t.$subject.id.flatMap { subjectToBusiness[$0] }
            return TranscriptContext(
                id: t.id ?? 0,
                speakerID: mc?.id,
                meetingDate: t.meetingDate.map { formatDate($0) } ?? "",
                speakerFullName: mc.map { "\($0.person.firstName) \($0.person.lastName)" } ?? "-",
                partyAbbreviation: party?.abbreviation ?? "-",
                partyColor: party?.color ?? "#6c757d",
                businessShortNumber: biz?.number ?? "",
                businessTitle: biz?.title ?? "",
                searchText: (t.text ?? "").replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression).replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression).trimmingCharacters(in: .whitespaces),
                propositionCount: propCountByTranscript[t.id ?? 0] ?? 0
            )
        }
    }

    @Sendable
    func apiMeetings(req: Request) async throws -> [MeetingSessionGroup] {
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

            let meetingIDs = meetings.compactMap { $0.id }
            let subjects = try await Subject.query(on: req.db)
                .filter(\.$meeting.$id ~~ meetingIDs)
                .all()
            let subjectIDs = subjects.compactMap { $0.id }
            let subjectBusinesses = subjectIDs.isEmpty ? [SubjectBusiness]() :
                try await SubjectBusiness.query(on: req.db)
                    .filter(\.$subjectID ~~ subjectIDs)
                    .all()

            let allBusinessIDs = Set(subjectBusinesses.compactMap { $0.businessID })
            let existingBusinesses = allBusinessIDs.isEmpty ? [Business]() :
                try await Business.query(on: req.db)
                    .with(\.$businessType)
                    .filter(\.$id ~~ allBusinessIDs)
                    .all()
            let businessLookup = Dictionary(uniqueKeysWithValues: existingBusinesses.compactMap { b -> (Int, Business)? in
                guard let id = b.id else { return nil }
                return (id, b)
            })

            let subjectByMeeting = Dictionary(grouping: subjects, by: { $0.$meeting.id })
            var meetingBusinessMap: [Int: [MeetingBusinessItem]] = [:]
            for (meetingID, meetingSubjects) in subjectByMeeting {
                guard let meetingID = meetingID else { continue }
                let sIDs = Set(meetingSubjects.compactMap { $0.id })
                let relevantSBs = subjectBusinesses
                    .filter { sb in sb.subjectID.map { sIDs.contains($0) } ?? false }
                var items: [MeetingBusinessItem] = []
                var seenIDs = Set<Int>()
                for sb in relevantSBs {
                    guard let bizID = sb.businessID, !seenIDs.contains(bizID) else { continue }
                    seenIDs.insert(bizID)
                    if let biz = businessLookup[bizID] {
                        items.append(MeetingBusinessItem(
                            id: bizID,
                            shortNumber: biz.number ?? "",
                            title: biz.title,
                            typeName: biz.businessType?.name ?? ""
                        ))
                    } else {
                        items.append(MeetingBusinessItem(
                            id: bizID,
                            shortNumber: "",
                            title: "Geschäft \(bizID)",
                            typeName: ""
                        ))
                    }
                }
                meetingBusinessMap[meetingID] = items.sorted { $0.shortNumber < $1.shortNumber }
            }

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

                let byDate = Dictionary(grouping: councilMeetings) { m in
                    m.date.map { formatDate($0) } ?? ""
                }
                let sortedDates = byDate.keys.sorted { $0 > $1 }

                var dateGroups: [MeetingDateGroup] = []
                for (idx, dateStr) in sortedDates.enumerated() {
                    guard let dateMeetings = byDate[dateStr] else { continue }
                    let allItems = dateMeetings.flatMap { m in
                        meetingBusinessMap[m.id ?? 0] ?? []
                    }
                    var seen = Set<String>()
                    let uniqueItems = allItems.filter { item in
                        let key = item.shortNumber.isEmpty ? item.title : item.shortNumber
                        return seen.insert(key).inserted
                    }
                    let collapseID = "collapse-\(sessID)-\(key)-\(idx)"
                    dateGroups.append(MeetingDateGroup(
                        id: collapseID,
                        date: dateStr,
                        businessCount: uniqueItems.count,
                        businesses: uniqueItems
                    ))
                }

                councilGroups.append(MeetingCouncilGroup(
                    id: "council-\(sessID)-\(key)",
                    councilAbbreviation: key,
                    councilName: councilName,
                    dates: dateGroups
                ))
            }

            meetingSessionGroups.append(MeetingSessionGroup(
                id: "session-\(sessID)",
                sessionName: sess.name,
                sessionDates: "\(sess.startDate.map { formatDate($0) } ?? "") - \(sess.endDate.map { formatDate($0) } ?? "")",
                councils: councilGroups
            ))
        }

        return meetingSessionGroups
    }

    @Sendable
    func apiCommittees(req: Request) async throws -> [CommitteeListContext] {
        let committees = try await Committee.query(on: req.db)
            .with(\.$council)
            .with(\.$mainCommittee)
            .sort(\.$name)
            .all()

        let memberCommittees = try await MemberCommittee.query(on: req.db)
            .with(\.$memberCouncil) { mc in
                mc.with(\.$party)
                mc.with(\.$canton)
                mc.with(\.$person)
            }
            .with(\.$committee)
            .all()

        let membersByCommittee = Dictionary(grouping: memberCommittees, by: { $0.$committee.id })

        return committees.compactMap { c -> CommitteeListContext? in
            guard let cid = c.id else { return nil }
            let cms = membersByCommittee[cid] ?? []
            let memberItems = cms.map { mc in
                CommitteeMemberItem(
                    id: mc.$memberCouncil.id,
                    firstName: mc.memberCouncil.person.firstName,
                    lastName: mc.memberCouncil.person.lastName,
                    party: mc.memberCouncil.party?.abbreviation ?? "-",
                    partyColor: mc.memberCouncil.party?.color ?? "#6c757d",
                    canton: mc.memberCouncil.canton?.abbreviation ?? "-",
                    function: mc.function ?? "Mitglied"
                )
            }.sorted { a, b in
                let order = ["Präsident/in": 0, "Vizepräsident/in": 1, "Mitglied": 2]
                let ao = order[a.function] ?? 3
                let bo = order[b.function] ?? 3
                return ao != bo ? ao < bo : a.lastName < b.lastName
            }
            return CommitteeListContext(
                id: "committee-\(cid)",
                name: c.name,
                abbreviation: c.abbreviation ?? "",
                council: c.council?.abbreviation ?? "",
                committeeType: c.committeeType ?? "",
                parentName: c.mainCommittee?.name,
                memberCount: cms.count,
                members: memberItems
            )
        }
    }

    // MARK: - Scores API

    @Sendable
    func apiScores(req: Request) async throws -> ScoresResponse {
        async let absences = scoreAbsences(on: req.db)
        async let vorstoss = scoreAcceptedVorstoss(on: req.db)
        async let rebels = scoreFactionRebels(on: req.db)
        return try await ScoresResponse(
            rankings: [
                absences,
                vorstoss,
                rebels
            ]
        )
    }

    private func scoreAbsences(on db: Database) async throws -> RankingContext {
        guard let sql = db as? SQLDatabase else { return RankingContext(id: "absences", title: "Die meisten Absenzen von Abstimmungen", description: "", entries: []) }

        // Aggregate absences and totals in a single SQL query
        let rows = try await sql.raw("""
            SELECT mc.id, pe.first_name, pe.last_name,
                   COALESCE(p.abbreviation, '-') AS party,
                   COALESCE(p.color, '#6c757d') AS party_color,
                   COALESCE(c.abbreviation, '-') AS council,
                   COUNT(*) FILTER (WHERE v.decision = 5) AS absence_count,
                   COUNT(*) AS total_count
            FROM voting v
            JOIN member_council mc ON v.member_council_id = mc.id
            JOIN person pe ON mc.person_id = pe.id
            LEFT JOIN party p ON mc.party_id = p.id
            LEFT JOIN council c ON mc.council_id = c.id
            WHERE mc.active = TRUE
            GROUP BY mc.id, pe.first_name, pe.last_name, p.abbreviation, p.color, c.abbreviation
            HAVING COUNT(*) FILTER (WHERE v.decision = 5) > 0
            ORDER BY absence_count DESC
        """).all()

        let entries = rows.map { row -> RankingEntry in
            let mcID = (try? row.decode(column: "id", as: Int.self)) ?? 0
            let firstName = (try? row.decode(column: "first_name", as: String.self)) ?? ""
            let lastName = (try? row.decode(column: "last_name", as: String.self)) ?? ""
            let party = (try? row.decode(column: "party", as: String.self)) ?? "-"
            let partyColor = (try? row.decode(column: "party_color", as: String.self)) ?? "#6c757d"
            let council = (try? row.decode(column: "council", as: String.self)) ?? "-"
            let absences = (try? row.decode(column: "absence_count", as: Int.self)) ?? 0
            let total = (try? row.decode(column: "total_count", as: Int.self)) ?? 1
            let pct = total > 0 ? Double(absences) / Double(total) * 100.0 : 0
            return RankingEntry(
                memberID: mcID, firstName: firstName, lastName: lastName,
                party: party, partyColor: partyColor, council: council,
                value: absences,
                detail: String(format: "%.1f%% von %d Abstimmungen", pct, total)
            )
        }

        return RankingContext(
            id: "absences",
            title: "Die meisten Absenzen von Abstimmungen",
            description: "Anzahl Abstimmungen, bei denen ein Parlamentarier abwesend war (ohne Entschuldigte)",
            entries: entries
        )
    }

    private func scoreAcceptedVorstoss(on db: Database) async throws -> RankingContext {
        guard let sql = db as? SQLDatabase else { return RankingContext(id: "accepted-vorstoss", title: "Die grösste Anzahl angenommener Vorstösse", description: "", entries: []) }

        let rows = try await sql.raw("""
            SELECT mc.id, pe.first_name, pe.last_name,
                   COALESCE(p.abbreviation, '-') AS party,
                   COALESCE(p.color, '#6c757d') AS party_color,
                   COALESCE(c.abbreviation, '-') AS council,
                   COUNT(*) AS accepted_count
            FROM business b
            JOIN member_council mc ON b.submitted_by_council_id = mc.id
            JOIN person pe ON mc.person_id = pe.id
            JOIN business_type bt ON b.business_type_id = bt.id
            LEFT JOIN party p ON mc.party_id = p.id
            LEFT JOIN council c ON mc.council_id = c.id
            WHERE (b.status LIKE '%Angenommen%' OR b.status LIKE '%Erledigt%')
              AND bt.name IN ('Motion', 'Postulat', 'Interpellation', 'Anfrage', 'Parlamentarische Initiative', 'Standesinitiative')
            GROUP BY mc.id, pe.first_name, pe.last_name, p.abbreviation, p.color, c.abbreviation
            ORDER BY accepted_count DESC
        """).all()

        let entries = rows.map { row -> RankingEntry in
            let mcID = (try? row.decode(column: "id", as: Int.self)) ?? 0
            let firstName = (try? row.decode(column: "first_name", as: String.self)) ?? ""
            let lastName = (try? row.decode(column: "last_name", as: String.self)) ?? ""
            let party = (try? row.decode(column: "party", as: String.self)) ?? "-"
            let partyColor = (try? row.decode(column: "party_color", as: String.self)) ?? "#6c757d"
            let council = (try? row.decode(column: "council", as: String.self)) ?? "-"
            let count = (try? row.decode(column: "accepted_count", as: Int.self)) ?? 0
            return RankingEntry(
                memberID: mcID, firstName: firstName, lastName: lastName,
                party: party, partyColor: partyColor, council: council,
                value: count,
                detail: "\(count) angenommene Vorstösse"
            )
        }

        return RankingContext(
            id: "accepted-vorstoss",
            title: "Die grösste Anzahl angenommener Vorstösse",
            description: "Motionen, Postulate, Interpellationen und Anfragen mit Status 'Angenommen' oder 'Erledigt'",
            entries: entries
        )
    }

    private func scoreFactionRebels(on db: Database) async throws -> RankingContext {
        guard let sql = db as? SQLDatabase else { return RankingContext(id: "faction-rebels", title: "Abweichler von der Fraktionsmehrheit", description: "", entries: []) }

        // 1. Determine faction majority per vote (only Ja/Nein votes)
        // 2. Count how often each member voted against their faction's majority
        let rows = try await sql.raw("""
            WITH faction_majority AS (
                SELECT v.vote_id, mc.faction_id,
                       CASE WHEN SUM(CASE WHEN v.decision = 1 THEN 1 ELSE 0 END)
                                >= SUM(CASE WHEN v.decision = 2 THEN 1 ELSE 0 END)
                            THEN 1 ELSE 2 END AS majority_decision
                FROM voting v
                JOIN member_council mc ON v.member_council_id = mc.id
                WHERE v.decision IN (1, 2) AND mc.faction_id IS NOT NULL
                GROUP BY v.vote_id, mc.faction_id
                HAVING COUNT(*) >= 3
            )
            SELECT mc.id, pe.first_name, pe.last_name,
                   COALESCE(p.abbreviation, '-') AS party,
                   COALESCE(p.color, '#6c757d') AS party_color,
                   COALESCE(c.abbreviation, '-') AS council,
                   COALESCE(f.abbreviation, '-') AS faction,
                   COUNT(*) AS rebel_count,
                   (SELECT COUNT(*) FROM voting v2
                    JOIN faction_majority fm2 ON v2.vote_id = fm2.vote_id AND fm2.faction_id = mc.faction_id
                    WHERE v2.member_council_id = mc.id AND v2.decision IN (1, 2)
                   ) AS total_faction_votes
            FROM voting v
            JOIN faction_majority fm ON v.vote_id = fm.vote_id AND fm.faction_id = (
                SELECT faction_id FROM member_council WHERE id = v.member_council_id
            )
            JOIN member_council mc ON v.member_council_id = mc.id
            JOIN person pe ON mc.person_id = pe.id
            LEFT JOIN party p ON mc.party_id = p.id
            LEFT JOIN council c ON mc.council_id = c.id
            LEFT JOIN faction f ON mc.faction_id = f.id
            WHERE v.decision IN (1, 2)
              AND v.decision != fm.majority_decision
              AND mc.active = TRUE
            GROUP BY mc.id, pe.first_name, pe.last_name, p.abbreviation, p.color, c.abbreviation, f.abbreviation
            ORDER BY rebel_count DESC
        """).all()

        let entries = rows.map { row -> RankingEntry in
            let mcID = (try? row.decode(column: "id", as: Int.self)) ?? 0
            let firstName = (try? row.decode(column: "first_name", as: String.self)) ?? ""
            let lastName = (try? row.decode(column: "last_name", as: String.self)) ?? ""
            let party = (try? row.decode(column: "party", as: String.self)) ?? "-"
            let partyColor = (try? row.decode(column: "party_color", as: String.self)) ?? "#6c757d"
            let council = (try? row.decode(column: "council", as: String.self)) ?? "-"
            let faction = (try? row.decode(column: "faction", as: String.self)) ?? "-"
            let rebelCount = (try? row.decode(column: "rebel_count", as: Int.self)) ?? 0
            let totalVotes = (try? row.decode(column: "total_faction_votes", as: Int.self)) ?? 1
            let pct = totalVotes > 0 ? Double(rebelCount) / Double(totalVotes) * 100.0 : 0
            return RankingEntry(
                memberID: mcID, firstName: firstName, lastName: lastName,
                party: party, partyColor: partyColor, council: council,
                value: rebelCount,
                detail: String(format: "%.1f%% von %d Fraktionsabstimmungen (%@)", pct, totalVotes, faction)
            )
        }

        return RankingContext(
            id: "faction-rebels",
            title: "Die grössten Abweichler von der Fraktionsmehrheit",
            description: "Anzahl Ja/Nein-Abstimmungen, bei denen ein Parlamentarier anders als die Mehrheit seiner Fraktion gestimmt hat",
            entries: entries
        )
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
}

struct CommitteeListContext: Content {
    let id: String
    let name: String
    let abbreviation: String
    let council: String
    let committeeType: String
    let parentName: String?
    let memberCount: Int
    let members: [CommitteeMemberItem]
}

struct CommitteeMemberItem: Codable {
    let id: Int
    let firstName: String
    let lastName: String
    let party: String
    let partyColor: String
    let canton: String
    let function: String
}

struct MeetingSessionGroup: Content {
    let id: String
    let sessionName: String
    let sessionDates: String
    let councils: [MeetingCouncilGroup]
}

struct MeetingCouncilGroup: Codable {
    let id: String
    let councilAbbreviation: String
    let councilName: String
    let dates: [MeetingDateGroup]
}

struct MeetingDateGroup: Codable {
    let id: String
    let date: String
    let businessCount: Int
    let businesses: [MeetingBusinessItem]
}

struct MeetingBusinessItem: Codable {
    let id: Int
    let shortNumber: String
    let title: String
    let typeName: String
}

struct SessionContext: Encodable {
    let id: Int
    let sessionName: String
    let abbreviation: String
    let startDate: String
    let endDate: String
    let syncStatus: String
}

struct MemberContext: Content {
    let id: Int
    let firstName: String
    let lastName: String
    let party: String
    let partyColor: String
    let faction: String
    let canton: String
    let council: String
    let occupation: String
    let active: Bool
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

struct BusinessContext: Content {
    let id: Int
    let shortNumber: String
    let title: String
    let typeName: String
    let statusText: String
    let submittedBy: String
    let submittedByID: Int?
    let submittedByName: String?
    let submittedByPartyColor: String?
}

struct TranscriptContext: Content {
    let id: Int
    let speakerID: Int?
    let meetingDate: String
    let speakerFullName: String
    let partyAbbreviation: String
    let partyColor: String
    let businessShortNumber: String
    let businessTitle: String
    let searchText: String
    let propositionCount: Int
}

struct ScoresResponse: Content {
    let rankings: [RankingContext]
}

struct RankingContext: Content {
    let id: String
    let title: String
    let description: String
    let entries: [RankingEntry]
}

struct RankingEntry: Content {
    let memberID: Int
    let firstName: String
    let lastName: String
    let party: String
    let partyColor: String
    let council: String
    let value: Int
    let detail: String
}

struct TranscriptDetailContext: Encodable {
    let id: Int
    let speakerFullName: String
    let speakerID: Int?
    let party: String
    let partyColor: String
    let meetingDate: String
    let htmlText: String
    let backURL: String
    let propositions: [PropositionDetailContext]
    let subjects: [SubjectOption]
}

struct PropositionDetailContext: Encodable {
    let id: Int
    let text: String
    let subjectName: String
    let subjectID: Int?
    let source: String
    let dateText: String
}

struct SubjectOption: Encodable {
    let id: Int
    let name: String
}
