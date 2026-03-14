import Foundation
import Vapor

struct ParlamentService: Sendable {
    private let baseURL = "https://ws.parlament.ch/odata.svc"
    let client: Client
    let logger: Logger

    init(client: Client, logger: Logger) {
        self.client = client
        self.logger = logger
    }

    // MARK: - Fetch Sessions

    func fetchSessions() async throws -> [SessionDTO] {
        let urlString = "\(baseURL)/Session?$filter=Language%20eq%20'DE'&$orderby=StartDate%20desc&$top=20&$format=json"
        let data = try await fetchData(from: urlString)
        let response = try JSONDecoder().decode(ODataResponse<SessionDTO>.self, from: data)
        return response.items
    }

    // MARK: - Fetch Geschaefte for a Session

    func fetchGeschaefte(sessionID: Int) async throws -> [GeschaeftDTO] {
        let urlString = "\(baseURL)/Session(ID=\(sessionID),Language='DE')/Businesses?$format=json&$select=ID,BusinessShortNumber,Title,BusinessTypeName,BusinessTypeAbbreviation,BusinessStatusText,BusinessStatusDate,SubmissionDate,SubmittedBy,Description,SubmissionCouncilName,ResponsibleDepartmentName,ResponsibleDepartmentAbbreviation,TagNames,Modified"
        return try await fetchAllPages(from: urlString)
    }

    func fetchGeschaefteModifiedSince(sessionID: Int, since: Date) async throws -> [GeschaeftDTO] {
        let dateString = ODataDateFormatter.format(since)
        let urlString = "\(baseURL)/Session(ID=\(sessionID),Language='DE')/Businesses?$format=json&$filter=Modified%20gt%20datetime'\(dateString)'&$select=ID,BusinessShortNumber,Title,BusinessTypeName,BusinessTypeAbbreviation,BusinessStatusText,BusinessStatusDate,SubmissionDate,SubmittedBy,Description,SubmissionCouncilName,ResponsibleDepartmentName,ResponsibleDepartmentAbbreviation,TagNames,Modified"
        return try await fetchAllPages(from: urlString)
    }

    // MARK: - Fetch Transcripts for a Geschaeft

    func fetchTranscripts(businessID: Int) async throws -> [TranscriptDTO] {
        let subjectURL = "\(baseURL)/SubjectBusiness?$filter=Language%20eq%20'DE'%20and%20BusinessNumber%20eq%20\(businessID)&$format=json&$select=IdSubject"
        let subjects: [SubjectBusinessDTO] = try await fetchAllPages(from: subjectURL)

        var allTranscripts: [TranscriptDTO] = []
        for subject in subjects {
            guard let idSubject = subject.IdSubject else { continue }
            let transcripts = try await fetchTranscriptsForSubject(idSubject: idSubject)
            allTranscripts.append(contentsOf: transcripts)
        }
        return allTranscripts
    }

    // MARK: - Decomposed Transcript Fetching (for sync)

    func fetchSubjectBusinesses(businessID: Int) async throws -> [SubjectBusinessDTO] {
        let urlString = "\(baseURL)/SubjectBusiness?$filter=Language%20eq%20'DE'%20and%20BusinessNumber%20eq%20\(businessID)&$format=json&$select=IdSubject"
        return try await fetchAllPages(from: urlString)
    }

    func fetchTranscriptsForSubject(idSubject: String) async throws -> [TranscriptDTO] {
        let urlString = "\(baseURL)/Transcript?$filter=Language%20eq%20'DE'%20and%20IdSubject%20eq%20\(idSubject)L&$format=json&$select=ID,PersonNumber,SpeakerFullName,SpeakerFunction,Text,MeetingDate,Start,End,CouncilName,ParlGroupAbbreviation,CantonAbbreviation,SortOrder,Type&$orderby=MeetingDate,SortOrder"
        return try await fetchAllPages(from: urlString)
    }

    // MARK: - Fetch BusinessRoles (Urheber) for a Geschaeft

    func fetchUrheber(businessID: Int) async throws -> BusinessRoleDTO? {
        let urlString = "\(baseURL)/Business(ID=\(businessID),Language='DE')/BusinessRoles?$format=json&$filter=Role%20eq%207&$select=ID,Role,RoleName,MemberCouncilNumber,BusinessNumber"
        let dtos: [BusinessRoleDTO] = try await fetchAllPages(from: urlString)
        return dtos.first { $0.MemberCouncilNumber != nil }
    }

    // MARK: - Fetch all active MemberCouncil

    func fetchAllParlamentarier() async throws -> [ParlamentarierDTO] {
        let urlString = "\(baseURL)/MemberCouncil?$filter=Language%20eq%20'DE'%20and%20Active%20eq%20true&$format=json&$select=ID,PersonNumber,FirstName,LastName,PartyAbbreviation,ParlGroupAbbreviation,CantonAbbreviation,CouncilName,CouncilAbbreviation,Active&$orderby=LastName,FirstName"
        return try await fetchAllPages(from: urlString)
    }

    func fetchParlamentarier(personNumber: Int) async throws -> ParlamentarierDTO? {
        let urlString = "\(baseURL)/MemberCouncil(ID=\(personNumber),Language='DE')?$format=json&$select=ID,PersonNumber,FirstName,LastName,PartyAbbreviation,ParlGroupAbbreviation,CantonAbbreviation,CouncilName,CouncilAbbreviation,Active"
        let data = try await fetchData(from: urlString)
        let response = try JSONDecoder().decode(ODataSingleResponse<ParlamentarierDTO>.self, from: data)
        return response.d
    }

    func fetchParlamentarierDetail(personNumber: Int) async throws -> ParlamentarierDTO? {
        let urlString = "\(baseURL)/MemberCouncil(ID=\(personNumber),Language='DE')?$format=json&$select=ID,PersonNumber,FirstName,LastName,PartyAbbreviation,ParlGroupAbbreviation,CantonAbbreviation,CouncilName,CouncilAbbreviation,Active,DateOfBirth,MaritalStatusText,NumberOfChildren,BirthPlace_City,BirthPlace_Canton,Citizenship,DateJoining,DateLeaving,DateElection,MilitaryRankText,PartyName,ParlGroupName,CantonName,Nationality"
        let data = try await fetchData(from: urlString)
        let response = try JSONDecoder().decode(ODataSingleResponse<ParlamentarierDTO>.self, from: data)
        return response.d
    }

    func fetchBusiness(id: Int) async throws -> GeschaeftDTO? {
        let urlString = "\(baseURL)/Business(ID=\(id),Language='DE')?$format=json&$select=ID,BusinessShortNumber,Title,BusinessTypeName,BusinessTypeAbbreviation,BusinessStatusText,BusinessStatusDate,SubmissionDate,SubmittedBy,Description,SubmissionCouncilName,ResponsibleDepartmentName,ResponsibleDepartmentAbbreviation,TagNames"
        let data = try await fetchData(from: urlString)
        let response = try JSONDecoder().decode(ODataSingleResponse<GeschaeftDTO>.self, from: data)
        return response.d
    }

    // MARK: - Fetch Meetings for a Session

    func fetchMeetings(sessionID: Int) async throws -> [MeetingDTO] {
        let urlString = "\(baseURL)/Meeting?$filter=Language%20eq%20'DE'%20and%20IdSession%20eq%20\(sessionID)&$format=json&$select=ID,MeetingNumber,IdSession,Council,CouncilName,CouncilAbbreviation,Date,Begin,MeetingOrderText,SortOrder,SessionName&$orderby=Date,SortOrder"
        return try await fetchAllPages(from: urlString)
    }

    func fetchSubjectsForMeeting(meetingID: String) async throws -> [SubjectDTO] {
        let urlString = "\(baseURL)/Meeting(ID=\(meetingID)L,Language='DE')/Subjects?$format=json&$select=ID,IdMeeting,SortOrder,VerbalixOid&$orderby=SortOrder"
        return try await fetchAllPages(from: urlString)
    }

    func fetchSubjectBusinessesForSubject(subjectID: String) async throws -> [SubjectBusinessDTO] {
        let urlString = "\(baseURL)/Subject(ID=\(subjectID)L,Language='DE')/SubjectsBusiness?$format=json&$select=IdSubject,BusinessNumber,BusinessShortNumber,Title,SortOrder"
        return try await fetchAllPages(from: urlString)
    }

    // MARK: - Fetch Votes

    func fetchVotes(sessionID: Int) async throws -> [VoteDTO] {
        let urlString = "\(baseURL)/Vote?$filter=Language%20eq%20'DE'%20and%20IdSession%20eq%20\(sessionID)&$format=json&$select=ID,BusinessNumber,BusinessShortNumber,BillTitle,IdSession,Subject,MeaningYes,MeaningNo,VoteEnd"
        return try await fetchAllPages(from: urlString)
    }

    func fetchVotesModifiedSince(sessionID: Int, since: Date) async throws -> [VoteDTO] {
        // Vote entity does not have a Modified field, fetch all votes for the session
        return try await fetchVotes(sessionID: sessionID)
    }

    func fetchVotings(voteID: Int) async throws -> [VotingDTO] {
        let urlString = "\(baseURL)/Voting?$filter=Language%20eq%20'DE'%20and%20IdVote%20eq%20\(voteID)&$format=json&$select=ID,IdVote,PersonNumber,Decision,DecisionText"
        return try await fetchAllPages(from: urlString)
    }

    // MARK: - Fetch PersonInterests

    func fetchPersonInterests(personNumber: Int) async throws -> [PersonInterestDTO] {
        let urlString = "\(baseURL)/PersonInterest?$filter=Language%20eq%20'DE'%20and%20PersonNumber%20eq%20\(personNumber)&$format=json&$select=PersonNumber,InterestName,InterestTypeText,FunctionInAgencyText,Paid,OrganizationTypeText"
        return try await fetchAllPages(from: urlString)
    }

    func fetchPersonOccupations(personNumber: Int) async throws -> [PersonOccupationDTO] {
        let urlString = "\(baseURL)/PersonOccupation?$filter=Language%20eq%20'DE'%20and%20PersonNumber%20eq%20\(personNumber)&$format=json&$select=PersonNumber,OccupationName,Employer,JobTitle"
        return try await fetchAllPages(from: urlString)
    }

    // MARK: - Paging

    private func fetchAllPages<T: Decodable>(from urlString: String) async throws -> [T] {
        var allResults: [T] = []
        var nextURL: String? = urlString

        while let currentURL = nextURL {
            let data = try await fetchData(from: currentURL)
            let response = try JSONDecoder().decode(ODataResponse<T>.self, from: data)
            allResults.append(contentsOf: response.items)
            nextURL = response.next
        }
        return allResults
    }

    // MARK: - Networking

    private func fetchData(from urlString: String) async throws -> Data {
        guard let url = URL(string: urlString) else {
            throw ParlamentError.invalidURL
        }
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw ParlamentError.networkError
        }
        return data
    }
}

// MARK: - Application Storage Key

private struct ParlamentServiceKey: StorageKey {
    typealias Value = ParlamentService
}

extension Application {
    var parlamentService: ParlamentService {
        get { self.storage[ParlamentServiceKey.self]! }
        set { self.storage[ParlamentServiceKey.self] = newValue }
    }
}

extension Request {
    var parlamentService: ParlamentService {
        self.application.parlamentService
    }
}
