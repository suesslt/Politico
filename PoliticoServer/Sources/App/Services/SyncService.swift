import Vapor
import Fluent

struct SyncService: Sendable {
    let app: Application
    let logger: Logger

    init(app: Application) {
        self.app = app
        self.logger = app.logger
    }

    /// Full sync for a session: fetches all entities from parlament.ch and upserts into database
    func syncSession(sessionID: Int, on db: Database) async throws {
        let parlament = app.parlamentService

        // 1. Sync Sessions
        try await updateSyncStatus(entity: "sessions", sessionID: sessionID, status: "syncing", on: db)
        let sessions = try await parlament.fetchSessions()
        for dto in sessions {
            try await upsertSession(dto, on: db)
        }
        try await updateSyncStatus(entity: "sessions", sessionID: sessionID, status: "completed", items: sessions.count, on: db)
        logger.info("Synced \(sessions.count) sessions")

        // 2. Sync Businesses
        try await updateSyncStatus(entity: "businesses", sessionID: sessionID, status: "syncing", on: db)
        let lastBusinessSync = try await getLastSyncDate(entity: "businesses", sessionID: sessionID, on: db)
        let businesses: [GeschaeftDTO]
        if let since = lastBusinessSync {
            businesses = try await parlament.fetchBusinessesModifiedSince(sessionID: sessionID, since: since)
        } else {
            businesses = try await parlament.fetchBusinesses(sessionID: sessionID)
        }
        for dto in businesses {
            try await upsertBusiness(dto, sessionID: sessionID, on: db)
        }
        try await updateSyncStatus(entity: "businesses", sessionID: sessionID, status: "completed", items: businesses.count, on: db)
        logger.info("Synced \(businesses.count) businesses for session \(sessionID)")

        // 3. Sync MemberCouncils + derive Council/Party/Faction
        try await updateSyncStatus(entity: "member_councils", sessionID: sessionID, status: "syncing", on: db)
        let members = try await parlament.fetchAllMemberCouncils()
        for dto in members {
            try await upsertMemberCouncil(dto, on: db)
        }
        try await updateSyncStatus(entity: "member_councils", sessionID: sessionID, status: "completed", items: members.count, on: db)
        logger.info("Synced \(members.count) member councils")

        // 4. Sync Meetings
        try await updateSyncStatus(entity: "meetings", sessionID: sessionID, status: "syncing", on: db)
        let meetings = try await parlament.fetchMeetings(sessionID: sessionID)
        for dto in meetings {
            try await upsertMeeting(dto, sessionID: sessionID, on: db)
        }
        try await updateSyncStatus(entity: "meetings", sessionID: sessionID, status: "completed", items: meetings.count, on: db)
        logger.info("Synced \(meetings.count) meetings for session \(sessionID)")

        // 5. Sync Subjects + SubjectBusinesses per Meeting
        try await updateSyncStatus(entity: "subjects", sessionID: sessionID, status: "syncing", on: db)
        var subjectCount = 0
        for meeting in meetings {
            let subjects = try await parlament.fetchSubjectsForMeeting(meetingID: meeting.ID)
            for subDTO in subjects {
                try await upsertSubject(subDTO, on: db)
                subjectCount += 1

                let subjectBusinesses = try await parlament.fetchSubjectBusinesses(subjectID: subDTO.ID)
                for sbDTO in subjectBusinesses {
                    try await upsertSubjectBusiness(sbDTO, on: db)
                }
            }
        }
        try await updateSyncStatus(entity: "subjects", sessionID: sessionID, status: "completed", items: subjectCount, on: db)
        logger.info("Synced \(subjectCount) subjects for session \(sessionID)")

        // 6. Sync Transcripts via SubjectBusinesses
        try await updateSyncStatus(entity: "transcripts", sessionID: sessionID, status: "syncing", on: db)
        let allSubjectBusinesses = try await SubjectBusiness.query(on: db).all()
        var transcriptCount = 0
        let processedSubjects = Set(allSubjectBusinesses.compactMap { $0.idSubject })
        for idSubject in processedSubjects {
            let transcripts = try await parlament.fetchTranscriptsForSubject(idSubject: String(idSubject))
            for dto in transcripts {
                try await upsertTranscript(dto, idSubject: idSubject, on: db)
                transcriptCount += 1
            }
        }
        try await updateSyncStatus(entity: "transcripts", sessionID: sessionID, status: "completed", items: transcriptCount, on: db)
        logger.info("Synced \(transcriptCount) transcripts for session \(sessionID)")

        // 7. Sync Votes
        try await updateSyncStatus(entity: "votes", sessionID: sessionID, status: "syncing", on: db)
        let votes = try await parlament.fetchVotes(sessionID: sessionID)
        for dto in votes {
            try await upsertVote(dto, sessionID: sessionID, on: db)
        }
        try await updateSyncStatus(entity: "votes", sessionID: sessionID, status: "completed", items: votes.count, on: db)
        logger.info("Synced \(votes.count) votes for session \(sessionID)")

        // 8. Sync Votings per Vote
        try await updateSyncStatus(entity: "votings", sessionID: sessionID, status: "syncing", on: db)
        let totalVotes = votes.count
        var votingCount = 0
        var votingErrors = 0
        for (index, voteDTO) in votes.enumerated() {
            do {
                let votings = try await parlament.fetchVotings(voteID: voteDTO.ID)
                for dto in votings {
                    try await upsertVoting(dto, on: db)
                    votingCount += 1
                }
            } catch {
                votingErrors += 1
                logger.warning("Failed to sync votings for vote \(voteDTO.ID): \(error)")
            }
            if (index + 1) % 25 == 0 {
                logger.info("Votings progress: \(index + 1)/\(totalVotes) votes processed (\(votingCount) votings)")
            }
        }
        try await updateSyncStatus(entity: "votings", sessionID: sessionID, status: "completed", items: votingCount, on: db)
        logger.info("Synced \(votingCount) votings (\(votingErrors) errors)")

        // 9. Sync PersonInterests + PersonOccupations
        try await updateSyncStatus(entity: "person_data", sessionID: sessionID, status: "syncing", on: db)
        let allMembers = try await MemberCouncil.query(on: db).all()
        let totalMembers = allMembers.count
        var interestCount = 0
        var occupationCount = 0
        var errorCount = 0
        for (index, member) in allMembers.enumerated() {
            do {
                // Sync interests (full replace)
                let interests = try await parlament.fetchPersonInterests(personNumber: member.personNumber)
                try await PersonInterest.query(on: db).filter(\.$personNumber == member.personNumber).delete()
                for dto in interests {
                    try await insertPersonInterest(dto, on: db)
                    interestCount += 1
                }

                // Sync occupation (store first result on member_council)
                let occupations = try await parlament.fetchPersonOccupations(personNumber: member.personNumber)
                if let occ = occupations.first {
                    member.occupationName = occ.OccupationName
                    member.employer = occ.Employer
                    member.jobTitle = occ.JobTitle
                    try await member.update(on: db)
                    occupationCount += 1
                }
            } catch {
                errorCount += 1
                logger.warning("Failed to sync person data for \(member.firstName) \(member.lastName) (\(member.personNumber)): \(error)")
            }

            if (index + 1) % 10 == 0 {
                logger.info("Person data progress: \(index + 1)/\(totalMembers)")
            }
        }
        try await updateSyncStatus(entity: "person_data", sessionID: sessionID, status: "completed", items: interestCount + occupationCount, on: db)
        logger.info("Synced \(interestCount) interests, \(occupationCount) occupations (\(errorCount) errors)")

        // 10. Final status
        try await updateSyncStatus(entity: "full_sync", sessionID: sessionID, status: "completed", items: 0, on: db)
    }

    // MARK: - Upsert Helpers

    private func upsertSession(_ dto: SessionDTO, on db: Database) async throws {
        if let existing = try await Session.find(dto.ID, on: db) {
            existing.sessionName = dto.SessionName ?? existing.sessionName
            existing.title = dto.Title ?? existing.title
            existing.abbreviation = dto.Abbreviation ?? existing.abbreviation
            existing.startDate = dto.startDateParsed ?? existing.startDate
            existing.endDate = dto.endDateParsed ?? existing.endDate
            existing.modified = dto.modifiedParsed ?? existing.modified
            try await existing.update(on: db)
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
            try await session.create(on: db)
        }
    }

    private func upsertBusiness(_ dto: GeschaeftDTO, sessionID: Int, on db: Database) async throws {
        // Derive BusinessType
        var businessTypeID: Int?
        if let typeName = dto.BusinessTypeName, !typeName.isEmpty {
            if let existing = try await BusinessType.query(on: db).filter(\.$name == typeName).first() {
                businessTypeID = existing.id
            } else {
                let bt = BusinessType(name: typeName, abbreviation: dto.BusinessTypeAbbreviation)
                try await bt.create(on: db)
                businessTypeID = bt.id
            }
        }

        if let existing = try await Business.find(dto.ID, on: db) {
            existing.businessShortNumber = dto.BusinessShortNumber ?? existing.businessShortNumber
            existing.title = dto.Title ?? existing.title
            existing.businessStatusText = dto.BusinessStatusText ?? existing.businessStatusText
            existing.businessStatusDate = dto.businessStatusDateParsed ?? existing.businessStatusDate
            existing.submissionDate = dto.submissionDateParsed ?? existing.submissionDate
            existing.submittedBy = dto.SubmittedBy ?? existing.submittedBy
            existing.description = dto.Description ?? existing.description
            existing.submissionCouncilName = dto.SubmissionCouncilName ?? existing.submissionCouncilName
            existing.responsibleDepartmentName = dto.ResponsibleDepartmentName ?? existing.responsibleDepartmentName
            existing.responsibleDepartmentAbbreviation = dto.ResponsibleDepartmentAbbreviation ?? existing.responsibleDepartmentAbbreviation
            existing.tagNames = dto.TagNames ?? existing.tagNames
            existing.modified = dto.modifiedParsed ?? existing.modified
            existing.$businessType.id = businessTypeID
            try await existing.update(on: db)
        } else {
            let business = Business(id: dto.ID, title: dto.Title ?? "Business \(dto.ID)", sessionID: sessionID)
            business.businessShortNumber = dto.BusinessShortNumber
            business.businessStatusText = dto.BusinessStatusText
            business.businessStatusDate = dto.businessStatusDateParsed
            business.submissionDate = dto.submissionDateParsed
            business.submittedBy = dto.SubmittedBy
            business.description = dto.Description
            business.submissionCouncilName = dto.SubmissionCouncilName
            business.responsibleDepartmentName = dto.ResponsibleDepartmentName
            business.responsibleDepartmentAbbreviation = dto.ResponsibleDepartmentAbbreviation
            business.tagNames = dto.TagNames
            business.modified = dto.modifiedParsed
            business.$businessType.id = businessTypeID
            try await business.create(on: db)
        }
    }

    private func upsertMemberCouncil(_ dto: ParlamentarierDTO, on db: Database) async throws {
        // Derive Council (nil for e.g. Bundeskanzler who has no council)
        var councilID: Int?
        if let councilName = dto.CouncilName, !councilName.isEmpty {
            if let existing = try await Council.query(on: db).filter(\.$name == councilName).first() {
                councilID = existing.id
            } else {
                let council = Council(name: councilName, abbreviation: dto.CouncilAbbreviation)
                try await council.create(on: db)
                councilID = council.id
            }
        }

        // Derive Party
        var partyID: Int?
        if let partyAbbr = dto.PartyAbbreviation {
            if let existing = try await Party.query(on: db).filter(\.$abbreviation == partyAbbr).first() {
                partyID = existing.id
            } else {
                let party = Party(abbreviation: partyAbbr, name: dto.PartyName)
                try await party.create(on: db)
                partyID = party.id
            }
        }

        // Derive Faction
        var factionID: Int?
        if let factionAbbr = dto.ParlGroupAbbreviation {
            if let existing = try await Faction.query(on: db).filter(\.$abbreviation == factionAbbr).first() {
                factionID = existing.id
            } else {
                let faction = Faction(abbreviation: factionAbbr, name: dto.ParlGroupName)
                try await faction.create(on: db)
                factionID = faction.id
            }
        }

        // Derive Canton
        var cantonID: Int?
        if let cantonAbbr = dto.CantonAbbreviation {
            if let existing = try await Canton.query(on: db).filter(\.$abbreviation == cantonAbbr).first() {
                cantonID = existing.id
            } else {
                let canton = Canton(abbreviation: cantonAbbr, name: dto.CantonName)
                try await canton.create(on: db)
                cantonID = canton.id
            }
        }

        if let existing = try await MemberCouncil.find(dto.ID, on: db) {
            existing.personNumber = dto.PersonNumber ?? existing.personNumber
            existing.firstName = dto.FirstName ?? existing.firstName
            existing.lastName = dto.LastName ?? existing.lastName
            existing.officialName = dto.OfficialName ?? existing.officialName
            existing.gender = dto.GenderAsString ?? existing.gender
            existing.active = dto.Active ?? existing.active
            existing.dateOfBirth = dto.dateOfBirthParsed ?? existing.dateOfBirth
            existing.dateJoining = dto.dateJoiningParsed ?? existing.dateJoining
            existing.dateLeaving = dto.dateLeavingParsed ?? existing.dateLeaving
            existing.dateElection = dto.dateElectionParsed ?? existing.dateElection
            existing.maritalStatus = dto.MaritalStatusText ?? existing.maritalStatus
            existing.numberOfChildren = dto.NumberOfChildren ?? existing.numberOfChildren
            existing.birthPlaceCity = dto.BirthPlace_City ?? existing.birthPlaceCity
            existing.birthPlaceCanton = dto.BirthPlace_Canton ?? existing.birthPlaceCanton
            existing.citizenship = dto.Citizenship ?? existing.citizenship
            existing.militaryRank = dto.MilitaryRankText ?? existing.militaryRank
            existing.nationality = dto.Nationality ?? existing.nationality
            existing.mandates = dto.Mandates ?? existing.mandates
            existing.additionalMandate = dto.AdditionalMandate ?? existing.additionalMandate
            existing.additionalActivity = dto.AdditionalActivity ?? existing.additionalActivity
            existing.modified = dto.modifiedParsed ?? existing.modified
            existing.$council.id = councilID
            existing.$party.id = partyID
            existing.$faction.id = factionID
            existing.$canton.id = cantonID
            try await existing.update(on: db)
        } else {
            let member = MemberCouncil(
                id: dto.ID,
                personNumber: dto.PersonNumber ?? dto.ID,
                firstName: dto.FirstName ?? "",
                lastName: dto.LastName ?? "",
                active: dto.Active ?? true
            )
            member.officialName = dto.OfficialName
            member.gender = dto.GenderAsString
            member.dateOfBirth = dto.dateOfBirthParsed
            member.dateJoining = dto.dateJoiningParsed
            member.dateLeaving = dto.dateLeavingParsed
            member.dateElection = dto.dateElectionParsed
            member.maritalStatus = dto.MaritalStatusText
            member.numberOfChildren = dto.NumberOfChildren
            member.birthPlaceCity = dto.BirthPlace_City
            member.birthPlaceCanton = dto.BirthPlace_Canton
            member.citizenship = dto.Citizenship
            member.militaryRank = dto.MilitaryRankText
            member.nationality = dto.Nationality
            member.mandates = dto.Mandates
            member.additionalMandate = dto.AdditionalMandate
            member.additionalActivity = dto.AdditionalActivity
            member.modified = dto.modifiedParsed
            member.$council.id = councilID
            member.$party.id = partyID
            member.$faction.id = factionID
            member.$canton.id = cantonID
            try await member.create(on: db)
        }
    }

    private func upsertMeeting(_ dto: MeetingDTO, sessionID: Int, on db: Database) async throws {
        guard let meetingID = dto.idInt else { return }

        // Derive Council
        var councilID: Int?
        if let councilName = dto.CouncilName, !councilName.isEmpty {
            if let existing = try await Council.query(on: db).filter(\.$name == councilName).first() {
                councilID = existing.id
            } else {
                let council = Council(name: councilName, abbreviation: dto.CouncilAbbreviation)
                try await council.create(on: db)
                councilID = council.id
            }
        }

        if let existing = try await Meeting.find(meetingID, on: db) {
            existing.meetingNumber = dto.MeetingNumber ?? existing.meetingNumber
            existing.$council.id = councilID
            existing.date = dto.dateParsed ?? existing.date
            existing.begin = dto.Begin ?? existing.begin
            existing.meetingOrderText = dto.MeetingOrderText ?? existing.meetingOrderText
            existing.sortOrder = dto.SortOrder ?? existing.sortOrder
            existing.sessionName = dto.SessionName ?? existing.sessionName
            try await existing.update(on: db)
        } else {
            let meeting = Meeting(id: meetingID, sessionID: sessionID)
            meeting.meetingNumber = dto.MeetingNumber
            meeting.$council.id = councilID
            meeting.date = dto.dateParsed
            meeting.begin = dto.Begin
            meeting.meetingOrderText = dto.MeetingOrderText
            meeting.sortOrder = dto.SortOrder
            meeting.sessionName = dto.SessionName
            try await meeting.create(on: db)
        }
    }

    private func upsertSubject(_ dto: SubjectDTO, on db: Database) async throws {
        guard let subjectID = dto.idInt else { return }
        if try await Subject.find(subjectID, on: db) == nil {
            let subject = Subject(id: subjectID, idMeeting: dto.idMeetingInt)
            subject.sortOrder = dto.SortOrder
            subject.verbalixOid = dto.VerbalixOid
            try await subject.create(on: db)
        }
    }

    private func upsertSubjectBusiness(_ dto: SubjectBusinessDTO, on db: Database) async throws {
        let idSubject = dto.IdSubject?.intValue
        // Check for existing by idSubject + businessNumber
        let existing = try await SubjectBusiness.query(on: db)
            .filter(\.$idSubject == idSubject)
            .filter(\.$businessNumber == dto.BusinessNumber)
            .first()
        if existing == nil {
            let sb = SubjectBusiness(idSubject: idSubject, businessNumber: dto.BusinessNumber)
            sb.businessShortNumber = dto.BusinessShortNumber
            sb.title = dto.Title
            sb.sortOrder = dto.SortOrder
            try await sb.create(on: db)
        }
    }

    private func upsertTranscript(_ dto: TranscriptDTO, idSubject: Int, on db: Database) async throws {
        guard let transcriptID = dto.idInt else { return }
        if let existing = try await Transcript.find(transcriptID, on: db) {
            existing.personNumber = dto.PersonNumber ?? existing.personNumber
            existing.speakerFullName = dto.SpeakerFullName ?? existing.speakerFullName
            existing.text = dto.Text ?? existing.text
            try await existing.update(on: db)
        } else {
            let transcript = Transcript(id: transcriptID)
            transcript.personNumber = dto.PersonNumber
            transcript.speakerFullName = dto.SpeakerFullName
            transcript.speakerFunction = dto.SpeakerFunction
            transcript.text = dto.Text
            transcript.meetingDate = dto.meetingDateParsed
            transcript.startTime = dto.startParsed
            transcript.endTime = dto.endParsed
            transcript.councilName = dto.CouncilName
            transcript.parlGroupAbbreviation = dto.ParlGroupAbbreviation
            transcript.cantonAbbreviation = dto.CantonAbbreviation
            transcript.sortOrder = dto.SortOrder
            transcript.type = dto.TranscriptType
            transcript.idSubject = idSubject
            try await transcript.create(on: db)
        }
    }

    private func upsertVote(_ dto: VoteDTO, sessionID: Int, on db: Database) async throws {
        if let existing = try await Vote.find(dto.ID, on: db) {
            existing.businessNumber = dto.BusinessNumber ?? existing.businessNumber
            existing.businessShortNumber = dto.BusinessShortNumber ?? existing.businessShortNumber
            existing.billTitle = dto.BillTitle ?? existing.billTitle
            existing.subject = dto.Subject ?? existing.subject
            existing.meaningYes = dto.MeaningYes ?? existing.meaningYes
            existing.meaningNo = dto.MeaningNo ?? existing.meaningNo
            existing.voteEnd = dto.voteEndParsed ?? existing.voteEnd
            try await existing.update(on: db)
        } else {
            let vote = Vote(id: dto.ID, sessionID: sessionID)
            vote.businessNumber = dto.BusinessNumber
            vote.businessShortNumber = dto.BusinessShortNumber
            vote.billTitle = dto.BillTitle
            vote.subject = dto.Subject
            vote.meaningYes = dto.MeaningYes
            vote.meaningNo = dto.MeaningNo
            vote.voteEnd = dto.voteEndParsed
            try await vote.create(on: db)
        }
    }

    private func upsertVoting(_ dto: VotingDTO, on db: Database) async throws {
        if try await Voting.find(dto.ID, on: db) == nil {
            guard let voteID = dto.IdVote, let personNumber = dto.PersonNumber, let decision = dto.Decision else { return }
            let voting = Voting(id: dto.ID, voteID: voteID, personNumber: personNumber, decision: decision)
            voting.decisionText = dto.DecisionText
            try await voting.create(on: db)
        }
    }

    private func insertPersonInterest(_ dto: PersonInterestDTO, on db: Database) async throws {
        guard let personNumber = dto.PersonNumber else { return }
        let interest = PersonInterest(personNumber: personNumber)
        interest.interestName = dto.InterestName
        interest.interestTypeText = dto.InterestTypeText
        interest.functionInAgencyText = dto.FunctionInAgencyText
        interest.paid = dto.Paid
        interest.organizationTypeText = dto.OrganizationTypeText
        try await interest.create(on: db)
    }

    // MARK: - Sync Status Helpers

    private func getLastSyncDate(entity: String, sessionID: Int, on db: Database) async throws -> Date? {
        try await SyncStatus.query(on: db)
            .filter(\.$entityName == entity)
            .filter(\.$sessionID == sessionID)
            .filter(\.$status == "completed")
            .first()?
            .lastSyncAt
    }

    private func updateSyncStatus(entity: String, sessionID: Int, status: String, items: Int = 0, on db: Database) async throws {
        if let existing = try await SyncStatus.query(on: db)
            .filter(\.$entityName == entity)
            .filter(\.$sessionID == sessionID)
            .first() {
            existing.status = status
            existing.lastSyncAt = Date()
            existing.itemsSynced = items
            try await existing.update(on: db)
        } else {
            let syncStatus = SyncStatus(entityName: entity, sessionID: sessionID, status: status, itemsSynced: items)
            syncStatus.lastSyncAt = Date()
            try await syncStatus.create(on: db)
        }
    }
}
