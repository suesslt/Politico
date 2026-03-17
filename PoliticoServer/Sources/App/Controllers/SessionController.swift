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
                sessionName: session.name,
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
            .with(\.$submittedByCouncil) { mc in mc.with(\.$party) }
            .sort(\.$submissionDate, .descending)
            .all()

        let businessContexts = businesses.map { b in
            let sbc = b.submittedByCouncil
            return BusinessContext(
                id: b.id ?? 0,
                shortNumber: b.number ?? "",
                title: b.title,
                typeName: b.businessType?.name ?? "",
                statusText: b.status ?? "",
                submittedBy: b.submittedBy ?? "",
                submittedByID: sbc?.id,
                submittedByName: sbc.map { "\($0.firstName) \($0.lastName)" },
                submittedByPartyColor: sbc?.party?.color
            )
        }

        // Transcripts
        // Transcripts with eager-loaded relationships
        let transcripts = try await Transcript.query(on: req.db)
            .with(\.$memberCouncil) { mc in
                mc.with(\.$party)
            }
            .sort(\.$meetingDate, .descending)
            .sort(\.$sortOrder)
            .all()

        // Lookup: subjectID → Business
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

        let transcriptContexts = transcripts.map { t in
            let mc = t.memberCouncil
            let party = mc?.party
            let biz = t.$subject.id.flatMap { subjectToBusiness[$0] }
            return TranscriptContext(
                id: t.id ?? 0,
                speakerID: mc?.id,
                meetingDate: t.meetingDate.map { formatDate($0) } ?? "",
                speakerFullName: mc.map { "\($0.firstName) \($0.lastName)" } ?? "-",
                partyAbbreviation: party?.abbreviation ?? "-",
                partyColor: party?.color ?? "#6c757d",
                businessShortNumber: biz?.number ?? "",
                businessTitle: biz?.title ?? "",
                searchText: (t.text ?? "").replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression).replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression).trimmingCharacters(in: .whitespaces)
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
                .filter(\.$meeting.$id ~~ meetingIDs)
                .all()
            let subjectIDs = subjects.compactMap { $0.id }
            let subjectBusinesses = subjectIDs.isEmpty ? [SubjectBusiness]() :
                try await SubjectBusiness.query(on: req.db)
                    .filter(\.$subjectID ~~ subjectIDs)
                    .all()

            // Collect all referenced business IDs and load from DB
            let allBusinessIDs = Set(subjectBusinesses.compactMap { $0.businessID })
            let existingBusinesses = allBusinessIDs.isEmpty ? [Business]() :
                try await Business.query(on: req.db)
                    .with(\.$businessType)
            .with(\.$submittedByCouncil) { mc in mc.with(\.$party) }
                    .filter(\.$id ~~ allBusinessIDs)
                    .all()
            var businessLookup = Dictionary(uniqueKeysWithValues: existingBusinesses.compactMap { b -> (Int, Business)? in
                guard let id = b.id else { return nil }
                return (id, b)
            })

            // Fetch missing businesses from API and persist
            let missingIDs = allBusinessIDs.subtracting(Set(businessLookup.keys))
            if !missingIDs.isEmpty {
                let parlament = req.application.parlamentService
                for missingID in missingIDs {
                    do {
                        if let dto = try await parlament.fetchBusiness(id: missingID) {
                            // Derive BusinessType
                            var businessTypeID: Int?
                            if let typeName = dto.BusinessTypeName, !typeName.isEmpty {
                                if let existing = try await BusinessType.query(on: req.db).filter(\.$name == typeName).first() {
                                    businessTypeID = existing.id
                                } else {
                                    let bt = BusinessType(name: typeName, abbreviation: dto.BusinessTypeAbbreviation)
                                    try await bt.create(on: req.db)
                                    businessTypeID = bt.id
                                }
                            }
                            // Derive SubmissionCouncil
                            var submissionCouncilID: Int?
                            if let councilName = dto.SubmissionCouncilName, !councilName.isEmpty {
                                if let existing = try await Council.query(on: req.db).filter(\.$name == councilName).first() {
                                    submissionCouncilID = existing.id
                                } else {
                                    let council = Council(name: councilName)
                                    try await council.create(on: req.db)
                                    submissionCouncilID = council.id
                                }
                            }
                            // Derive ResponsibleDepartment
                            var responsibleDepartmentID: Int?
                            if let deptName = dto.ResponsibleDepartmentName, !deptName.isEmpty {
                                if let existing = try await Department.query(on: req.db).filter(\.$name == deptName).first() {
                                    responsibleDepartmentID = existing.id
                                } else {
                                    let dept = Department(name: deptName, abbreviation: dto.ResponsibleDepartmentAbbreviation)
                                    try await dept.create(on: req.db)
                                    responsibleDepartmentID = dept.id
                                }
                            }
                            // Resolve SubmittedBy → MemberCouncil
                            var submittedByCouncilID: Int?
                            if let submittedBy = dto.SubmittedBy, !submittedBy.isEmpty {
                                let parts = submittedBy.split(separator: " ", maxSplits: 1)
                                if parts.count == 2 {
                                    if let mc = try await MemberCouncil.query(on: req.db)
                                        .filter(\.$lastName == String(parts[0]))
                                        .filter(\.$firstName == String(parts[1]))
                                        .first() {
                                        submittedByCouncilID = mc.id
                                    }
                                }
                            }
                            let business = Business(id: dto.ID, title: dto.Title ?? "Business \(dto.ID)", sessionID: sessID)
                            business.number = dto.BusinessShortNumber
                            business.status = dto.BusinessStatusText
                            business.statusDate = dto.businessStatusDateParsed
                            business.submissionDate = dto.submissionDateParsed
                            business.submittedBy = dto.SubmittedBy
                            business.description = dto.Description
                            business.submittedText = dto.SubmittedText
                            business.reasonText = dto.ReasonText
                            business.federalCouncilResponse = dto.FederalCouncilResponseText
                            business.federalCouncilProposal = dto.FederalCouncilProposalText
                            business.tagNames = dto.TagNames
                            business.modified = dto.modifiedParsed
                            business.$businessType.id = businessTypeID
                            business.$submissionCouncil.id = submissionCouncilID
                            business.$responsibleDepartment.id = responsibleDepartmentID
                            business.$submittedByCouncil.id = submittedByCouncilID
                            try await business.create(on: req.db)
                            if let bt = businessTypeID {
                                try await business.$businessType.load(on: req.db)
                            }
                            businessLookup[dto.ID] = business
                        }
                    } catch {
                        req.logger.warning("Failed to fetch business \(missingID): \(error)")
                    }
                }
            }

            // Build lookup: meetingID → [MeetingBusinessItem]
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
                            shortNumber: biz.number ?? "",
                            title: biz.title,
                            typeName: biz.businessType?.name ?? ""
                        ))
                    } else {
                        items.append(MeetingBusinessItem(
                            shortNumber: "",
                            title: "Geschäft \(bizID)",
                            typeName: ""
                        ))
                    }
                }
                meetingBusinessMap[meetingID] = items.sorted { $0.shortNumber < $1.shortNumber }
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
                    let allItems = dateMeetings.flatMap { m in
                        meetingBusinessMap[m.id ?? 0] ?? []
                    }
                    // Deduplicate by shortNumber
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

        // Committees with members
        let committees = try await Committee.query(on: req.db)
            .with(\.$council)
            .with(\.$mainCommittee)
            .sort(\.$name)
            .all()

        let memberCommittees = try await MemberCommittee.query(on: req.db)
            .with(\.$memberCouncil) { mc in
                mc.with(\.$party)
                mc.with(\.$canton)
            }
            .with(\.$committee)
            .all()

        let membersByCommittee = Dictionary(grouping: memberCommittees, by: { $0.$committee.id })

        let committeeContexts = committees.compactMap { c -> CommitteeListContext? in
            guard let cid = c.id else { return nil }
            let cms = membersByCommittee[cid] ?? []
            let memberItems = cms.map { mc in
                CommitteeMemberItem(
                    id: mc.$memberCouncil.id,
                    firstName: mc.memberCouncil.firstName,
                    lastName: mc.memberCouncil.lastName,
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

        let context = DashboardContext(
            sessions: sessionContexts,
            members: memberContexts,
            businesses: businessContexts,
            transcripts: transcriptContexts,
            meetingGroups: meetingSessionGroups,
            committees: committeeContexts
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
            .with(\.$submittedByCouncil) { mc in mc.with(\.$party) }
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
                    submittedByName: sbc.map { "\($0.firstName) \($0.lastName)" },
                    submittedByPartyColor: sbc?.party?.color
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
    let committees: [CommitteeListContext]
}

struct CommitteeListContext: Encodable {
    let id: String
    let name: String
    let abbreviation: String
    let council: String
    let committeeType: String
    let parentName: String?
    let memberCount: Int
    let members: [CommitteeMemberItem]
}

struct CommitteeMemberItem: Encodable {
    let id: Int
    let firstName: String
    let lastName: String
    let party: String
    let partyColor: String
    let canton: String
    let function: String
}

struct MeetingSessionGroup: Encodable {
    let id: String
    let sessionName: String
    let sessionDates: String
    let councils: [MeetingCouncilGroup]
}

struct MeetingCouncilGroup: Encodable {
    let id: String
    let councilAbbreviation: String
    let councilName: String
    let dates: [MeetingDateGroup]
}

struct MeetingDateGroup: Encodable {
    let id: String
    let date: String
    let businessCount: Int
    let businesses: [MeetingBusinessItem]
}

struct MeetingBusinessItem: Encodable {
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
    let submittedBy: String
    let submittedByID: Int?
    let submittedByName: String?
    let submittedByPartyColor: String?
}

struct TranscriptContext: Encodable {
    let id: Int
    let speakerID: Int?
    let meetingDate: String
    let speakerFullName: String
    let partyAbbreviation: String
    let partyColor: String
    let businessShortNumber: String
    let businessTitle: String
    let searchText: String
}
