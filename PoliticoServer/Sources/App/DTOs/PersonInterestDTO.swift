import Foundation

struct PersonInterestDTO: Decodable, Sendable {
    let ID: String?
    let PersonNumber: Int?
    let InterestName: String?
    let InterestTypeText: String?
    let FunctionInAgencyText: String?
    let Paid: Bool?
    let OrganizationTypeText: String?
}
