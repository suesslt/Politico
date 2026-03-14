import Foundation

struct BusinessRoleDTO: Decodable, Sendable {
    let ID: Int?
    let Role: Int?
    let RoleName: String?
    let MemberCouncilNumber: Int?
    let BusinessNumber: Int?
}
