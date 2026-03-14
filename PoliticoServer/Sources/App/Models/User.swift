import Fluent
import Vapor

final class User: Model, Content, @unchecked Sendable {
    static let schema = "user"

    @ID(custom: .id, generatedBy: .database)
    var id: Int?

    @Field(key: "username")
    var username: String

    @Field(key: "password_hash")
    var passwordHash: String

    @Field(key: "role")
    var role: String

    @Field(key: "email")
    var email: String?

    @Timestamp(key: "created_at", on: .create)
    var createdAt: Date?

    init() {}

    init(username: String, passwordHash: String, role: String = "user", email: String? = nil) {
        self.username = username
        self.passwordHash = passwordHash
        self.role = role
        self.email = email
    }
}

// MARK: - Authentication

extension User: ModelSessionAuthenticatable {}

extension User: ModelCredentialsAuthenticatable {
    static let usernameKey = \User.$username
    static let passwordHashKey = \User.$passwordHash

    func verify(password: String) throws -> Bool {
        try Bcrypt.verify(password, created: self.passwordHash)
    }
}
