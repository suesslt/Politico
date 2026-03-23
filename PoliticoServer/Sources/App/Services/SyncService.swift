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

        // Pre-load lookup caches to avoid N+1 queries
        var councilCache: [String: Int] = [:]
        for c in try await Council.query(on: db).all() { councilCache[c.name] = c.id }
        var partyCache: [String: Int] = [:]
        for p in try await Party.query(on: db).all() { partyCache[p.abbreviation] = p.id }
        var factionCache: [String: Int] = [:]
        for f in try await Faction.query(on: db).all() { factionCache[f.abbreviation] = f.id }
        var cantonCache: [String: Int] = [:]
        for c in try await Canton.query(on: db).all() { cantonCache[c.abbreviation] = c.id }

        for (index, dto) in members.enumerated() {
            try await upsertMemberCouncil(dto, councilCache: &councilCache, partyCache: &partyCache, factionCache: &factionCache, cantonCache: &cantonCache, on: db)
            if (index + 1) % 500 == 0 {
                logger.info("Member councils progress: \(index + 1)/\(members.count)")
            }
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

        // 5. Sync Subjects + SubjectBusinesses per Meeting (incremental: skip meetings that already have subjects)
        try await updateSyncStatus(entity: "subjects", sessionID: sessionID, status: "syncing", on: db)
        let meetingIDs = meetings.compactMap { $0.idInt }
        let existingSubjectMeetingIDs = Set(
            try await Subject.query(on: db)
                .filter(\.$meeting.$id ~~ meetingIDs)
                .all()
                .compactMap { $0.$meeting.id }
        )
        let newMeetings = meetings.filter { !existingSubjectMeetingIDs.contains($0.idInt ?? 0) }
        let totalMeetings = newMeetings.count
        logger.info("Subjects: \(existingSubjectMeetingIDs.count) meetings already synced, \(totalMeetings) new")
        var subjectCount = 0
        var subjectErrors = 0
        for (mIdx, meeting) in newMeetings.enumerated() {
            do {
                let subjects = try await parlament.fetchSubjectsForMeeting(meetingID: meeting.ID)
                for subDTO in subjects {
                    try await upsertSubject(subDTO, on: db)
                    subjectCount += 1

                    do {
                        let subjectBusinesses = try await parlament.fetchSubjectBusinesses(subjectID: subDTO.ID)
                        for sbDTO in subjectBusinesses {
                            try await upsertSubjectBusiness(sbDTO, on: db)
                        }
                    } catch {
                        logger.warning("Failed to fetch subject businesses for subject \(subDTO.ID): \(String(reflecting: error))")
                    }
                }
            } catch {
                subjectErrors += 1
                logger.warning("Failed to fetch subjects for meeting \(meeting.ID): \(String(reflecting: error))")
            }
            if (mIdx + 1) % 5 == 0 {
                logger.info("Subjects progress: \(mIdx + 1)/\(totalMeetings) meetings (\(subjectCount) subjects)")
            }
        }
        try await updateSyncStatus(entity: "subjects", sessionID: sessionID, status: "completed", items: subjectCount, on: db)
        logger.info("Synced \(subjectCount) new subjects (\(subjectErrors) errors)")

        // 6. Sync Transcripts (incremental: only subjects that have no transcripts yet, scoped to session)
        try await updateSyncStatus(entity: "transcripts", sessionID: sessionID, status: "syncing", on: db)
        let sessionSubjectIDs = try await Subject.query(on: db)
            .filter(\.$meeting.$id ~~ meetingIDs)
            .all()
            .compactMap { $0.id }
        let subjectsWithTranscripts = Set(
            try await Transcript.query(on: db)
                .filter(\.$subject.$id ~~ sessionSubjectIDs)
                .all()
                .compactMap { $0.$subject.id }
        )
        let newSubjectIDs = sessionSubjectIDs.filter { !subjectsWithTranscripts.contains($0) }
        logger.info("Transcripts: \(subjectsWithTranscripts.count) subjects already synced, \(newSubjectIDs.count) new")
        var transcriptCount = 0
        var transcriptErrors = 0
        let totalSubjects = newSubjectIDs.count
        for (sIdx, idSubject) in newSubjectIDs.enumerated() {
            do {
                let transcripts = try await parlament.fetchTranscriptsForSubject(idSubject: String(idSubject))
                for dto in transcripts {
                    try await upsertTranscript(dto, idSubject: idSubject, on: db)
                    transcriptCount += 1
                }
            } catch {
                transcriptErrors += 1
                logger.warning("Failed to fetch transcripts for subject \(idSubject): \(String(reflecting: error))")
            }
            if (sIdx + 1) % 25 == 0 {
                logger.info("Transcripts progress: \(sIdx + 1)/\(totalSubjects) subjects (\(transcriptCount) transcripts)")
            }
        }
        try await updateSyncStatus(entity: "transcripts", sessionID: sessionID, status: "completed", items: transcriptCount, on: db)
        logger.info("Synced \(transcriptCount) transcripts (\(transcriptErrors) errors)")

        // 7. Sync Votes (incremental: only insert new votes)
        try await updateSyncStatus(entity: "votes", sessionID: sessionID, status: "syncing", on: db)
        let allVoteDTOs = try await parlament.fetchVotes(sessionID: sessionID)
        let existingVoteIDs = Set(
            try await Vote.query(on: db)
                .filter(\.$session.$id == sessionID)
                .all()
                .compactMap { $0.id }
        )
        let newVoteDTOs = allVoteDTOs.filter { !existingVoteIDs.contains($0.ID) }
        for dto in newVoteDTOs {
            try await upsertVote(dto, sessionID: sessionID, on: db)
        }
        try await updateSyncStatus(entity: "votes", sessionID: sessionID, status: "completed", items: allVoteDTOs.count, on: db)
        logger.info("Votes: \(existingVoteIDs.count) already synced, \(newVoteDTOs.count) new")

        // 8. Sync Votings (incremental: only for new votes)
        try await updateSyncStatus(entity: "votings", sessionID: sessionID, status: "syncing", on: db)
        let totalNewVotes = newVoteDTOs.count
        var votingCount = 0
        var votingErrors = 0
        for (index, voteDTO) in newVoteDTOs.enumerated() {
            do {
                let votings = try await parlament.fetchVotings(voteID: voteDTO.ID)
                for dto in votings {
                    try await upsertVoting(dto, on: db)
                    votingCount += 1
                }
            } catch {
                votingErrors += 1
                logger.warning("Failed to sync votings for vote \(voteDTO.ID): \(String(reflecting: error))")
            }
            if (index + 1) % 25 == 0 {
                logger.info("Votings progress: \(index + 1)/\(totalNewVotes) votes processed (\(votingCount) votings)")
            }
        }
        try await updateSyncStatus(entity: "votings", sessionID: sessionID, status: "completed", items: votingCount, on: db)
        logger.info("Synced \(votingCount) votings from \(totalNewVotes) new votes (\(votingErrors) errors)")

        // 9. Sync PersonInterests + PersonOccupations
        try await updateSyncStatus(entity: "person_data", sessionID: sessionID, status: "syncing", on: db)
        let allMembers = try await MemberCouncil.query(on: db).filter(\.$active == true).all()
        let totalMembers = allMembers.count
        var interestCount = 0
        var occupationCount = 0
        var errorCount = 0
        for (index, member) in allMembers.enumerated() {
            do {
                let personID = member.id!
                // Sync interests (full replace, now on person)
                let interests = try await parlament.fetchPersonInterests(personNumber: personID)
                try await PersonInterest.query(on: db).filter(\.$person.$id == personID).delete()
                for dto in interests {
                    try await insertPersonInterest(dto, personID: personID, on: db)
                    interestCount += 1
                }

                // Sync occupation (store first result on member_council)
                let occupations = try await parlament.fetchPersonOccupations(personNumber: personID)
                if let occ = occupations.first {
                    member.occupationName = occ.OccupationName
                    member.employer = occ.Employer
                    member.jobTitle = occ.JobTitle
                    try await member.update(on: db)
                    occupationCount += 1
                }
            } catch {
                errorCount += 1
                try? await member.$person.load(on: db)
                logger.warning("Failed to sync person data for \(member.person.firstName) \(member.person.lastName) (\(member.id ?? 0)): \(String(reflecting: error))")
            }

            if (index + 1) % 10 == 0 {
                logger.info("Person data progress: \(index + 1)/\(totalMembers)")
            }
        }
        try await updateSyncStatus(entity: "person_data", sessionID: sessionID, status: "completed", items: interestCount + occupationCount, on: db)
        logger.info("Synced \(interestCount) interests, \(occupationCount) occupations (\(errorCount) errors)")

        // 10. Sync Committees + MemberCommittees
        try await updateSyncStatus(entity: "committees", sessionID: sessionID, status: "syncing", on: db)
        let committees = try await parlament.fetchCommittees()
        for dto in committees {
            try await upsertCommittee(dto, on: db)
        }
        logger.info("Synced \(committees.count) committees")

        var memberCommitteeCount = 0
        for committee in committees {
            do {
                let members = try await parlament.fetchMemberCommittees(committeeNumber: committee.ID)
                // Full replace for this committee
                if let committeeModel = try await Committee.find(committee.ID, on: db) {
                    try await MemberCommittee.query(on: db)
                        .filter(\.$committee.$id == committeeModel.id!)
                        .delete()
                }
                for dto in members {
                    guard let personNumber = dto.PersonNumber, let committeeNumber = dto.CommitteeNumber else { continue }
                    // PersonNumber == member_council.id
                    guard try await MemberCouncil.find(personNumber, on: db) != nil else { continue }
                    let mc = MemberCommittee(
                        memberCouncilID: personNumber,
                        committeeID: committeeNumber,
                        function: dto.CommitteeFunctionName
                    )
                    mc.modified = dto.modifiedParsed
                    try await mc.create(on: db)
                    memberCommitteeCount += 1
                }
            } catch {
                logger.warning("Failed to sync members for committee \(committee.ID): \(String(reflecting: error))")
            }
        }
        try await updateSyncStatus(entity: "committees", sessionID: sessionID, status: "completed", items: memberCommitteeCount, on: db)
        logger.info("Synced \(memberCommitteeCount) committee memberships")

        // 11. Final status
        try await updateSyncStatus(entity: "full_sync", sessionID: sessionID, status: "completed", items: 0, on: db)
    }

    // MARK: - Upsert Helpers

    private func upsertCommittee(_ dto: CommitteeDTO, on db: Database) async throws {
        // Derive council
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

        if let existing = try await Committee.find(dto.ID, on: db) {
            existing.name = dto.CommitteeName ?? existing.name
            existing.abbreviation = dto.Abbreviation1 ?? existing.abbreviation
            existing.committeeType = dto.CommitteeTypeName ?? existing.committeeType
            existing.$council.id = councilID
            existing.$mainCommittee.id = dto.MainCommitteeNumber
            existing.modified = dto.modifiedParsed ?? existing.modified
            try await existing.update(on: db)
        } else {
            let committee = Committee(
                id: dto.ID,
                name: dto.CommitteeName ?? "Committee \(dto.ID)",
                abbreviation: dto.Abbreviation1
            )
            committee.committeeType = dto.CommitteeTypeName
            committee.$council.id = councilID
            committee.$mainCommittee.id = dto.MainCommitteeNumber
            committee.modified = dto.modifiedParsed
            try await committee.create(on: db)
        }
    }


    private func upsertSession(_ dto: SessionDTO, on db: Database) async throws {
        if let existing = try await Session.find(dto.ID, on: db) {
            existing.name = dto.SessionName ?? existing.name
            existing.abbreviation = dto.Abbreviation ?? existing.abbreviation
            existing.startDate = dto.startDateParsed ?? existing.startDate
            existing.endDate = dto.endDateParsed ?? existing.endDate
            existing.modified = dto.modifiedParsed ?? existing.modified
            try await existing.update(on: db)
        } else {
            let session = Session(
                id: dto.ID,
                name: dto.SessionName ?? dto.Title ?? "Session \(dto.ID)",
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

        // Derive SubmissionCouncil
        var submissionCouncilID: Int?
        if let councilName = dto.SubmissionCouncilName, !councilName.isEmpty {
            if let existing = try await Council.query(on: db).filter(\.$name == councilName).first() {
                submissionCouncilID = existing.id
            } else {
                let council = Council(name: councilName)
                try await council.create(on: db)
                submissionCouncilID = council.id
            }
        }

        // Derive ResponsibleDepartment
        var responsibleDepartmentID: Int?
        if let deptName = dto.ResponsibleDepartmentName, !deptName.isEmpty {
            if let existing = try await Department.query(on: db).filter(\.$name == deptName).first() {
                responsibleDepartmentID = existing.id
            } else {
                let dept = Department(name: deptName, abbreviation: dto.ResponsibleDepartmentAbbreviation)
                try await dept.create(on: db)
                responsibleDepartmentID = dept.id
            }
        }

        // Resolve SubmittedBy → MemberCouncil via Person (format: "LastName FirstName")
        var submittedByCouncilID: Int?
        if let submittedBy = dto.SubmittedBy, !submittedBy.isEmpty {
            let parts = submittedBy.split(separator: " ", maxSplits: 1)
            if parts.count == 2 {
                let lastName = String(parts[0])
                let firstName = String(parts[1])
                if let person = try await Person.query(on: db)
                    .filter(\.$lastName == lastName)
                    .filter(\.$firstName == firstName)
                    .first(),
                   let mc = try await MemberCouncil.query(on: db)
                    .filter(\.$person.$id == person.id!)
                    .first() {
                    submittedByCouncilID = mc.id
                }
            }
        }

        if let existing = try await Business.find(dto.ID, on: db) {
            existing.number = dto.BusinessShortNumber ?? existing.number
            existing.title = dto.Title ?? existing.title
            existing.status = dto.BusinessStatusText ?? existing.status
            existing.statusDate = dto.businessStatusDateParsed ?? existing.statusDate
            existing.submissionDate = dto.submissionDateParsed ?? existing.submissionDate
            existing.submittedBy = dto.SubmittedBy ?? existing.submittedBy
            existing.description = dto.Description ?? existing.description
            existing.submittedText = dto.SubmittedText ?? existing.submittedText
            existing.reasonText = dto.ReasonText ?? existing.reasonText
            existing.federalCouncilResponse = dto.FederalCouncilResponseText ?? existing.federalCouncilResponse
            existing.federalCouncilProposal = dto.FederalCouncilProposalText ?? existing.federalCouncilProposal
            existing.tagNames = dto.TagNames ?? existing.tagNames
            existing.modified = dto.modifiedParsed ?? existing.modified
            existing.$businessType.id = businessTypeID
            existing.$submissionCouncil.id = submissionCouncilID
            existing.$responsibleDepartment.id = responsibleDepartmentID
            existing.$submittedByCouncil.id = submittedByCouncilID
            try await existing.update(on: db)
        } else {
            let business = Business(id: dto.ID, title: dto.Title ?? "Business \(dto.ID)", sessionID: sessionID)
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
            try await business.create(on: db)
        }
    }

    private func upsertMemberCouncil(_ dto: ParlamentarierDTO, councilCache: inout [String: Int], partyCache: inout [String: Int], factionCache: inout [String: Int], cantonCache: inout [String: Int], on db: Database) async throws {
        // Derive Council (cached)
        var councilID: Int?
        if let councilName = dto.CouncilName, !councilName.isEmpty {
            if let cached = councilCache[councilName] {
                councilID = cached
            } else {
                let council = Council(name: councilName, abbreviation: dto.CouncilAbbreviation)
                try await council.create(on: db)
                councilID = council.id
                councilCache[councilName] = council.id
            }
        }

        // Derive Party (cached)
        var partyID: Int?
        if let partyAbbr = dto.PartyAbbreviation {
            if let cached = partyCache[partyAbbr] {
                partyID = cached
            } else {
                let party = Party(abbreviation: partyAbbr, name: dto.PartyName)
                try await party.create(on: db)
                partyID = party.id
                partyCache[partyAbbr] = party.id
            }
        }

        // Derive Faction (cached)
        var factionID: Int?
        if let factionAbbr = dto.ParlGroupAbbreviation {
            if let cached = factionCache[factionAbbr] {
                factionID = cached
            } else {
                let faction = Faction(abbreviation: factionAbbr, name: dto.ParlGroupName)
                try await faction.create(on: db)
                factionID = faction.id
                factionCache[factionAbbr] = faction.id
            }
        }

        // Derive Canton (cached)
        var cantonID: Int?
        if let cantonAbbr = dto.CantonAbbreviation {
            if let cached = cantonCache[cantonAbbr] {
                cantonID = cached
            } else {
                let canton = Canton(abbreviation: cantonAbbr, name: dto.CantonName)
                try await canton.create(on: db)
                cantonID = canton.id
                cantonCache[cantonAbbr] = canton.id
            }
        }

        // Upsert Person first
        if let existingPerson = try await Person.find(dto.ID, on: db) {
            existingPerson.firstName = dto.FirstName ?? existingPerson.firstName
            existingPerson.lastName = dto.LastName ?? existingPerson.lastName
            existingPerson.officialName = dto.OfficialName ?? existingPerson.officialName
            existingPerson.gender = dto.GenderAsString ?? existingPerson.gender
            existingPerson.dateOfBirth = dto.dateOfBirthParsed ?? existingPerson.dateOfBirth
            existingPerson.maritalStatus = dto.MaritalStatusText ?? existingPerson.maritalStatus
            existingPerson.numberOfChildren = dto.NumberOfChildren ?? existingPerson.numberOfChildren
            existingPerson.birthPlaceCity = dto.BirthPlace_City ?? existingPerson.birthPlaceCity
            existingPerson.birthPlaceCanton = dto.BirthPlace_Canton ?? existingPerson.birthPlaceCanton
            existingPerson.citizenship = dto.Citizenship ?? existingPerson.citizenship
            existingPerson.militaryRank = dto.MilitaryRankText ?? existingPerson.militaryRank
            existingPerson.nationality = dto.Nationality ?? existingPerson.nationality
            existingPerson.modified = dto.modifiedParsed ?? existingPerson.modified
            try await existingPerson.update(on: db)
        } else {
            let person = Person(id: dto.ID, firstName: dto.FirstName ?? "", lastName: dto.LastName ?? "")
            person.officialName = dto.OfficialName
            person.gender = dto.GenderAsString
            person.dateOfBirth = dto.dateOfBirthParsed
            person.maritalStatus = dto.MaritalStatusText
            person.numberOfChildren = dto.NumberOfChildren
            person.birthPlaceCity = dto.BirthPlace_City
            person.birthPlaceCanton = dto.BirthPlace_Canton
            person.citizenship = dto.Citizenship
            person.militaryRank = dto.MilitaryRankText
            person.nationality = dto.Nationality
            person.modified = dto.modifiedParsed
            try await person.create(on: db)
        }

        // Upsert MemberCouncil
        if let existing = try await MemberCouncil.find(dto.ID, on: db) {
            existing.active = dto.Active ?? existing.active
            existing.dateJoining = dto.dateJoiningParsed ?? existing.dateJoining
            existing.dateLeaving = dto.dateLeavingParsed ?? existing.dateLeaving
            existing.dateElection = dto.dateElectionParsed ?? existing.dateElection
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
                personID: dto.ID,
                active: dto.Active ?? true
            )
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
            existing.$council.id = councilID
            existing.date = dto.dateParsed ?? existing.date
            existing.begin = dto.Begin ?? existing.begin
            existing.sortOrder = dto.SortOrder ?? existing.sortOrder
            existing.sortOrderText = dto.MeetingOrderText ?? existing.sortOrderText
            try await existing.update(on: db)
        } else {
            let meeting = Meeting(id: meetingID, sessionID: sessionID)
            meeting.$council.id = councilID
            meeting.date = dto.dateParsed
            meeting.begin = dto.Begin
            meeting.sortOrder = dto.SortOrder
            meeting.sortOrderText = dto.MeetingOrderText
            try await meeting.create(on: db)
        }
    }

    private func upsertSubject(_ dto: SubjectDTO, on db: Database) async throws {
        guard let subjectID = dto.idInt else { return }
        // Validate FK: meeting must exist
        if let meetingID = dto.idMeetingInt, try await Meeting.find(meetingID, on: db) == nil { return }
        if try await Subject.find(subjectID, on: db) == nil {
            let subject = Subject(id: subjectID, meetingID: dto.idMeetingInt)
            subject.sortOrder = dto.SortOrder
            try await subject.create(on: db)
        }
    }

    private func upsertSubjectBusiness(_ dto: SubjectBusinessDTO, on db: Database) async throws {
        let subjectID = dto.IdSubject?.intValue
        let businessID = dto.BusinessNumber

        // Validate FK references exist before inserting
        if let sid = subjectID, try await Subject.find(sid, on: db) == nil { return }
        if let bid = businessID, try await Business.find(bid, on: db) == nil { return }

        let existing = try await SubjectBusiness.query(on: db)
            .filter(\.$subjectID == subjectID)
            .filter(\.$businessID == businessID)
            .first()
        if existing == nil {
            let sb = SubjectBusiness(subjectID: subjectID, businessID: businessID)
            sb.sortOrder = dto.SortOrder
            try await sb.create(on: db)
        }
    }

    private func upsertTranscript(_ dto: TranscriptDTO, idSubject: Int, on db: Database) async throws {
        guard let transcriptID = dto.idInt else { return }
        // Validate FK: subject must exist
        guard try await Subject.find(idSubject, on: db) != nil else { return }

        // Resolve member_council_id (PersonNumber == member_council.id)
        var memberCouncilID: Int?
        if let personNumber = dto.PersonNumber {
            if try await MemberCouncil.find(personNumber, on: db) != nil {
                memberCouncilID = personNumber
            }
        }

        // Resolve council_id from council_name
        var councilID: Int?
        if let councilName = dto.CouncilName, !councilName.isEmpty {
            if let existing = try await Council.query(on: db).filter(\.$name == councilName).first() {
                councilID = existing.id
            } else {
                let council = Council(name: councilName)
                try await council.create(on: db)
                councilID = council.id
            }
        }

        if let existing = try await Transcript.find(transcriptID, on: db) {
            existing.$memberCouncil.id = memberCouncilID
            existing.text = dto.Text ?? existing.text
            try await existing.update(on: db)
        } else {
            let transcript = Transcript(id: transcriptID)
            transcript.$memberCouncil.id = memberCouncilID
            transcript.speakerFunction = dto.SpeakerFunction
            transcript.text = dto.Text
            transcript.meetingDate = dto.meetingDateParsed
            transcript.startTime = dto.startParsed
            transcript.endTime = dto.endParsed
            transcript.$council.id = councilID
            transcript.sortOrder = dto.SortOrder
            transcript.type = dto.TranscriptType
            transcript.$subject.id = idSubject
            try await transcript.create(on: db)
        }
    }

    private func upsertVote(_ dto: VoteDTO, sessionID: Int, on db: Database) async throws {
        // Resolve business_id from BusinessNumber
        var businessID: Int?
        if let bizNum = dto.BusinessNumber {
            if try await Business.find(bizNum, on: db) != nil {
                businessID = bizNum
            }
        }

        if let existing = try await Vote.find(dto.ID, on: db) {
            existing.$business.id = businessID ?? existing.$business.id
            existing.billTitle = dto.BillTitle ?? existing.billTitle
            existing.subject = dto.Subject ?? existing.subject
            existing.meaningYes = dto.MeaningYes ?? existing.meaningYes
            existing.meaningNo = dto.MeaningNo ?? existing.meaningNo
            existing.voteEnd = dto.voteEndParsed ?? existing.voteEnd
            try await existing.update(on: db)
        } else {
            let vote = Vote(id: dto.ID, sessionID: sessionID)
            vote.$business.id = businessID
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
            // Validate FK: vote must exist
            guard try await Vote.find(voteID, on: db) != nil else { return }
            // PersonNumber == member_council.id
            let mcID = try await MemberCouncil.find(personNumber, on: db) != nil ? personNumber : nil
            let voting = Voting(id: dto.ID, voteID: voteID, memberCouncilID: mcID, decision: decision)
            voting.decisionText = dto.DecisionText
            try await voting.create(on: db)
        }
    }

    private func insertPersonInterest(_ dto: PersonInterestDTO, personID: Int, on db: Database) async throws {
        let interest = PersonInterest(personID: personID)
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
            if status == "completed" { existing.errorMessage = nil }
            try await existing.update(on: db)
        } else {
            let syncStatus = SyncStatus(entityName: entity, sessionID: sessionID, status: status, itemsSynced: items)
            syncStatus.lastSyncAt = Date()
            try await syncStatus.create(on: db)
        }
    }
}
