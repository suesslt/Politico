import Vapor
import Fluent

struct AuthController: RouteCollection {
    func boot(routes: RoutesBuilder) throws {
        let sessionRoutes = routes.grouped(User.sessionAuthenticator())

        sessionRoutes.get("login", use: loginPage)
        sessionRoutes.post("login", use: login)
        sessionRoutes.get("logout", use: logout)
    }

    @Sendable
    func loginPage(req: Request) async throws -> View {
        if req.auth.has(User.self) {
            throw Abort.redirect(to: "/sessions")
        }
        return try await req.view.render("login", LoginContext(error: nil))
    }

    @Sendable
    func login(req: Request) async throws -> Response {
        let loginData = try req.content.decode(LoginRequest.self)

        guard let user = try await User.query(on: req.db)
            .filter(\.$username == loginData.username)
            .first() else {
            let context = LoginContext(error: "Ungültiger Benutzername oder Passwort")
            return try await req.view.render("login", context).encodeResponse(for: req).get()
        }

        guard try Bcrypt.verify(loginData.password, created: user.passwordHash) else {
            let context = LoginContext(error: "Ungültiger Benutzername oder Passwort")
            return try await req.view.render("login", context).encodeResponse(for: req).get()
        }

        req.auth.login(user)
        return req.redirect(to: "/sessions")
    }

    @Sendable
    func logout(req: Request) async throws -> Response {
        req.auth.logout(User.self)
        req.session.destroy()
        return req.redirect(to: "/login")
    }
}

struct LoginRequest: Content {
    let username: String
    let password: String
}

struct LoginContext: Encodable {
    let error: String?
}
