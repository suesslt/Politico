import Foundation

struct ParlamentarierDTO: Decodable, Sendable {
    let ID: Int
    let PersonNumber: Int?
    let FirstName: String?
    let LastName: String?
    let OfficialName: String?
    let GenderAsString: String?
    let Active: Bool?
    let PartyAbbreviation: String?
    let PartyName: String?
    let ParlGroupAbbreviation: String?
    let ParlGroupName: String?
    let CantonAbbreviation: String?
    let CantonName: String?
    let CouncilName: String?
    let CouncilAbbreviation: String?
    let DateOfBirth: String?
    let DateJoining: String?
    let DateLeaving: String?
    let DateElection: String?
    let MaritalStatusText: String?
    let NumberOfChildren: Int?
    let BirthPlace_City: String?
    let BirthPlace_Canton: String?
    let Citizenship: String?
    let MilitaryRankText: String?
    let Nationality: String?
    let Mandates: String?
    let AdditionalMandate: String?
    let AdditionalActivity: String?
    let Modified: String?

    var dateOfBirthParsed: Date? {
        DateOfBirth.flatMap { ODataDateFormatter.parse($0) }
    }

    var dateJoiningParsed: Date? {
        DateJoining.flatMap { ODataDateFormatter.parse($0) }
    }

    var dateLeavingParsed: Date? {
        DateLeaving.flatMap { ODataDateFormatter.parse($0) }
    }

    var dateElectionParsed: Date? {
        DateElection.flatMap { ODataDateFormatter.parse($0) }
    }

    var modifiedParsed: Date? {
        Modified.flatMap { ODataDateFormatter.parse($0) }
    }
}
