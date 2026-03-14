import Vapor

struct EnsureAuthenticatedMiddleware: AsyncMiddleware {
    func respond(to request: Request, chainingTo next: AsyncResponder) async throws -> Response {
        guard request.auth.has(User.self) else {
            return request.redirect(to: "/login")
        }
        return try await next.respond(to: request)
    }
}
