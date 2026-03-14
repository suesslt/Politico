import Fluent
import Vapor

final class Subject: Model, Content, @unchecked Sendable {
    static let schema = "subject"

    @ID(custom: "id", generatedBy: .user)
    var id: Int?

    @Field(key: "id_meeting")
    var idMeeting: Int?

    @Field(key: "sort_order")
    var sortOrder: Int?

    @Field(key: "verbalix_oid")
    var verbalixOid: Int?

    init() {}

    init(id: Int, idMeeting: Int?) {
        self.id = id
        self.idMeeting = idMeeting
    }
}
