import Vapor
import Fluent

struct BusinessController: RouteCollection {
    func boot(routes: RoutesBuilder) throws {
        routes.get("businesses", ":businessID", use: show)
    }

    @Sendable
    func show(req: Request) async throws -> View {
        guard let businessID = req.parameters.get("businessID", as: Int.self) else {
            throw Abort(.badRequest, reason: "Invalid business ID")
        }
        let business = try await Business.query(on: req.db)
            .with(\.$session)
            .with(\.$businessType)
            .with(\.$submissionCouncil)
            .with(\.$responsibleDepartment)
            .with(\.$submittedByCouncil) { $0.with(\.$party); $0.with(\.$person) }
            .filter(\.$id == businessID)
            .first()
        guard let business else { throw Abort(.notFound) }

        // Transcripts via SubjectBusiness → Subject → Transcript
        let subjectBusinesses = try await SubjectBusiness.query(on: req.db)
            .filter(\.$businessID == businessID)
            .all()
        let subjectIDs = subjectBusinesses.compactMap { $0.subjectID }

        let transcripts: [Transcript]
        if subjectIDs.isEmpty {
            transcripts = []
        } else {
            transcripts = try await Transcript.query(on: req.db)
                .with(\.$memberCouncil) { mc in mc.with(\.$party); mc.with(\.$person) }
                .filter(\.$subject.$id ~~ subjectIDs)
                .sort(\.$meetingDate, .descending)
                .sort(\.$sortOrder)
                .all()
        }

        // Load proposition counts
        let bizTranscriptIDs = transcripts.compactMap { $0.id }
        let bizProps = bizTranscriptIDs.isEmpty ? [Proposition]() :
            try await Proposition.query(on: req.db)
                .filter(\.$transcript.$id ~~ bizTranscriptIDs)
                .all()
        let bizPropCounts = Dictionary(grouping: bizProps, by: { $0.$transcript.id })
            .mapValues { $0.count }

        let transcriptContexts = transcripts.map { t in
            let mc = t.memberCouncil
            let party = mc?.party
            return BusinessTranscriptContext(
                id: t.id ?? 0,
                meetingDate: t.meetingDate.map { formatDate($0) } ?? "",
                speakerID: mc?.id,
                speakerFullName: mc.map { "\($0.person.firstName) \($0.person.lastName)" } ?? "-",
                speakerFunction: t.speakerFunction ?? "",
                partyAbbreviation: party?.abbreviation ?? "-",
                partyColor: party?.color ?? "#6c757d",
                searchText: (t.text ?? "").replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression).replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression).trimmingCharacters(in: .whitespaces),
                propositionCount: bizPropCounts[t.id ?? 0] ?? 0
            )
        }

        let sbc = business.submittedByCouncil
        let queryItems = req.url.query.flatMap { URLComponents(string: "?\($0)")?.queryItems } ?? []
        let referer = queryItems.first(where: { $0.name == "from" })?.value ?? "/sessions"
        let memberID = queryItems.first(where: { $0.name == "memberID" })?.value ?? ""

        let context = BusinessDetailContext(
            id: business.id ?? 0,
            number: business.number ?? "",
            title: business.title,
            description: business.description ?? "",
            status: business.status ?? "",
            statusDate: business.statusDate.map { formatDate($0) } ?? "",
            submissionDate: business.submissionDate.map { formatDate($0) } ?? "",
            submittedBy: business.submittedBy ?? "",
            submittedByID: sbc?.id,
            submittedByName: sbc.map { "\($0.person.firstName) \($0.person.lastName)" },
            submittedByPartyColor: sbc?.party?.color,
            sessionName: business.session.name,
            businessType: business.businessType?.name ?? "",
            businessTypeAbbreviation: business.businessType?.abbreviation ?? "",
            submissionCouncil: business.submissionCouncil?.name ?? "",
            responsibleDepartment: business.responsibleDepartment?.name ?? "",
            responsibleDepartmentAbbreviation: business.responsibleDepartment?.abbreviation ?? "",
            submittedText: business.submittedText ?? "",
            reasonText: business.reasonText ?? "",
            federalCouncilResponse: business.federalCouncilResponse ?? "",
            federalCouncilProposal: business.federalCouncilProposal ?? "",
            tagNames: business.tagNames ?? "",
            transcripts: transcriptContexts,
            backURL: referer,
            backMemberID: memberID
        )

        return try await req.view.render("business-detail", context)
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "dd.MM.yyyy"
        return formatter.string(from: date)
    }
}

// MARK: - Contexts

struct BusinessDetailContext: Encodable {
    let id: Int
    let number: String
    let title: String
    let description: String
    let status: String
    let statusDate: String
    let submissionDate: String
    let submittedBy: String
    let submittedByID: Int?
    let submittedByName: String?
    let submittedByPartyColor: String?
    let sessionName: String
    let businessType: String
    let businessTypeAbbreviation: String
    let submissionCouncil: String
    let responsibleDepartment: String
    let responsibleDepartmentAbbreviation: String
    let submittedText: String
    let reasonText: String
    let federalCouncilResponse: String
    let federalCouncilProposal: String
    let tagNames: String
    let transcripts: [BusinessTranscriptContext]
    let backURL: String
    let backMemberID: String
}

struct BusinessTranscriptContext: Encodable {
    let id: Int
    let meetingDate: String
    let speakerID: Int?
    let speakerFullName: String
    let speakerFunction: String
    let partyAbbreviation: String
    let partyColor: String
    let searchText: String
    let propositionCount: Int
}
