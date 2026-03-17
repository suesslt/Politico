import Vapor
import Fluent

struct MemberController: RouteCollection {
    func boot(routes: RoutesBuilder) throws {
        routes.get("members", ":memberID", use: show)
    }

    @Sendable
    func show(req: Request) async throws -> View {
        guard let memberID = req.parameters.get("memberID", as: Int.self) else {
            throw Abort(.badRequest, reason: "Invalid member ID")
        }
        guard let member = try await MemberCouncil.query(on: req.db)
            .with(\.$party)
            .with(\.$faction)
            .with(\.$canton)
            .with(\.$council)
            .filter(\.$id == memberID)
            .first() else {
            throw Abort(.notFound)
        }

        // Committees
        let memberCommittees = try await MemberCommittee.query(on: req.db)
            .with(\.$committee) { c in c.with(\.$council) }
            .filter(\.$memberCouncil.$id == memberID)
            .all()

        let committeeContexts = memberCommittees.map { mc in
            MemberCommitteeContext(
                name: mc.committee.name,
                abbreviation: mc.committee.abbreviation ?? "",
                council: mc.committee.council?.abbreviation ?? "",
                function: mc.function ?? "Mitglied",
                type: mc.committee.committeeType ?? ""
            )
        }

        // Votings with vote details
        let votings = try await Voting.query(on: req.db)
            .with(\.$vote) { v in v.with(\.$business) }
            .filter(\.$memberCouncil.$id == memberID)
            .sort(\.$id, .descending)
            .range(..<100)
            .all()

        let votingContexts = votings.map { v in
            MemberVotingContext(
                billTitle: v.vote.billTitle ?? v.vote.business?.title ?? "-",
                businessNumber: v.vote.business?.number ?? "",
                decision: v.decisionText ?? decisionLabel(v.decision),
                decisionClass: decisionClass(v.decision)
            )
        }

        // Person interests
        let interests = try await PersonInterest.query(on: req.db)
            .filter(\.$memberCouncil.$id == memberID)
            .all()

        let interestContexts = interests.map { i in
            MemberInterestContext(
                name: i.interestName ?? "-",
                type: i.interestTypeText ?? "",
                function: i.functionInAgencyText ?? "",
                paid: i.paid ?? false
            )
        }

        // Transcripts
        let transcripts = try await Transcript.query(on: req.db)
            .filter(\.$memberCouncil.$id == memberID)
            .sort(\.$meetingDate, .descending)
            .sort(\.$sortOrder)
            .all()

        // Resolve subject → business for each transcript
        let transcriptSubjectIDs = Set(transcripts.compactMap { $0.$subject.id })
        let tSBs = transcriptSubjectIDs.isEmpty ? [SubjectBusiness]() :
            try await SubjectBusiness.query(on: req.db)
                .filter(\.$subjectID ~~ transcriptSubjectIDs)
                .all()
        let tBizIDs = Set(tSBs.compactMap { $0.businessID })
        let tBusinesses = tBizIDs.isEmpty ? [Business]() :
            try await Business.query(on: req.db)
                .filter(\.$id ~~ tBizIDs)
                .all()
        let tBizByID = Dictionary(uniqueKeysWithValues: tBusinesses.compactMap { b -> (Int, Business)? in
            guard let id = b.id else { return nil }
            return (id, b)
        })
        var tSubjectToBiz: [Int: Business] = [:]
        for sb in tSBs {
            guard let sid = sb.subjectID, tSubjectToBiz[sid] == nil,
                  let bizID = sb.businessID, let biz = tBizByID[bizID] else { continue }
            tSubjectToBiz[sid] = biz
        }

        let transcriptContexts = transcripts.map { t in
            let biz = t.$subject.id.flatMap { tSubjectToBiz[$0] }
            return MemberTranscriptContext(
                id: t.id ?? 0,
                meetingDate: t.meetingDate.map { formatDate($0) } ?? "",
                businessID: biz?.id,
                businessNumber: biz?.number ?? "",
                businessTitle: biz?.title ?? "",
                textPreview: String((t.text ?? "").prefix(300))
                    .replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
                    .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                    .trimmingCharacters(in: .whitespaces),
                searchText: (t.text ?? "")
                    .replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
                    .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                    .trimmingCharacters(in: .whitespaces)
            )
        }

        // Scores
        let scores = MemberScoresContext(
            leftRight: member.scoreLeftRight,
            conservativeLiberal: member.scoreConservativeLiberal,
            liberalEconomy: member.scoreLiberalEconomy,
            innovativeLocation: member.scoreInnovativeLocation,
            independentEnergy: member.scoreIndependentEnergy,
            strengthResilience: member.scoreStrengthResilience,
            leanGovernment: member.scoreLeanGovernment,
            hasScores: member.scoreLeftRight != nil
        )

        let referer = req.url.query.flatMap { URLComponents(string: "?\($0)")?.queryItems?.first(where: { $0.name == "from" })?.value } ?? "/sessions"

        let context = MemberDetailContext(
            id: member.id ?? 0,
            firstName: member.firstName,
            lastName: member.lastName,
            officialName: member.officialName ?? "",
            gender: member.gender == "m" ? "Männlich" : member.gender == "f" ? "Weiblich" : "",
            active: member.active,
            party: member.party?.abbreviation ?? "-",
            partyName: member.party?.name ?? "",
            partyColor: member.party?.color ?? "#6c757d",
            faction: member.faction?.abbreviation ?? "-",
            canton: member.canton?.abbreviation ?? "-",
            cantonName: member.canton?.name ?? "",
            council: member.council?.abbreviation ?? "-",
            councilName: member.council?.name ?? "",
            dateOfBirth: member.dateOfBirth.map { formatDate($0) } ?? "",
            dateJoining: member.dateJoining.map { formatDate($0) } ?? "",
            dateElection: member.dateElection.map { formatDate($0) } ?? "",
            maritalStatus: member.maritalStatus ?? "",
            numberOfChildren: member.numberOfChildren,
            birthPlace: [member.birthPlaceCity, member.birthPlaceCanton].compactMap { $0 }.joined(separator: ", "),
            citizenship: member.citizenship ?? "",
            nationality: member.nationality ?? "",
            militaryRank: member.militaryRank ?? "",
            occupation: member.occupationName ?? "",
            employer: member.employer ?? "",
            jobTitle: member.jobTitle ?? "",
            mandates: member.mandates ?? "",
            additionalMandate: member.additionalMandate ?? "",
            additionalActivity: member.additionalActivity ?? "",
            committees: committeeContexts,
            votings: votingContexts,
            interests: interestContexts,
            transcripts: transcriptContexts,
            scores: scores,
            backURL: referer
        )

        return try await req.view.render("member-detail", context)
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "dd.MM.yyyy"
        return formatter.string(from: date)
    }

    private func decisionLabel(_ decision: Int) -> String {
        switch decision {
        case 1: "Ja"
        case 2: "Nein"
        case 3: "Enthaltung"
        case 4: "Abwesend"
        case 5: "Entschuldigt"
        case 6: "Präsident"
        default: "Unbekannt"
        }
    }

    private func decisionClass(_ decision: Int) -> String {
        switch decision {
        case 1: "success"
        case 2: "danger"
        case 3: "warning"
        case 4, 5: "secondary"
        default: "light"
        }
    }
}

// MARK: - Contexts

struct MemberDetailContext: Encodable {
    let id: Int
    let firstName: String
    let lastName: String
    let officialName: String
    let gender: String
    let active: Bool
    let party: String
    let partyName: String
    let partyColor: String
    let faction: String
    let canton: String
    let cantonName: String
    let council: String
    let councilName: String
    let dateOfBirth: String
    let dateJoining: String
    let dateElection: String
    let maritalStatus: String
    let numberOfChildren: Int?
    let birthPlace: String
    let citizenship: String
    let nationality: String
    let militaryRank: String
    let occupation: String
    let employer: String
    let jobTitle: String
    let mandates: String
    let additionalMandate: String
    let additionalActivity: String
    let committees: [MemberCommitteeContext]
    let votings: [MemberVotingContext]
    let interests: [MemberInterestContext]
    let transcripts: [MemberTranscriptContext]
    let scores: MemberScoresContext
    let backURL: String
}

struct MemberTranscriptContext: Encodable {
    let id: Int
    let meetingDate: String
    let businessID: Int?
    let businessNumber: String
    let businessTitle: String
    let textPreview: String
    let searchText: String
}

struct MemberCommitteeContext: Encodable {
    let name: String
    let abbreviation: String
    let council: String
    let function: String
    let type: String
}

struct MemberVotingContext: Encodable {
    let billTitle: String
    let businessNumber: String
    let decision: String
    let decisionClass: String
}

struct MemberInterestContext: Encodable {
    let name: String
    let type: String
    let function: String
    let paid: Bool
}

struct MemberScoresContext: Encodable {
    let leftRight: Double?
    let conservativeLiberal: Double?
    let liberalEconomy: Double?
    let innovativeLocation: Double?
    let independentEnergy: Double?
    let strengthResilience: Double?
    let leanGovernment: Double?
    let hasScores: Bool
}
