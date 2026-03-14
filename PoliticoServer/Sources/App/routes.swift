import Vapor

func routes(_ app: Application) throws {
    // Public routes
    let authController = AuthController()
    try app.register(collection: authController)

    // Protected routes (require authentication)
    let protected = app.grouped(
        User.sessionAuthenticator(),
        EnsureAuthenticatedMiddleware()
    )

    let sessionController = SessionController()
    try protected.register(collection: sessionController)

    let syncController = SyncController()
    try protected.register(collection: syncController)

    // Root redirect
    app.get { req -> Response in
        req.redirect(to: "/sessions")
    }
}
