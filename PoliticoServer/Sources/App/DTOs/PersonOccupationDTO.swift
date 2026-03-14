import Foundation

struct PersonOccupationDTO: Decodable, Sendable {
    let ID: String?
    let PersonNumber: Int?
    let OccupationName: String?
    let Employer: String?
    let JobTitle: String?
}
