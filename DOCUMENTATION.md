# PolitikServer Technologie-Dokumentation

## Inhaltsverzeichnis
1. [Übersicht](#übersicht)
2. [Technologie-Stack](#technologie-stack)
3. [Dependencies & Packages](#dependencies--packages)
4. [Architektur-Patterns](#architektur-patterns)
5. [Design-Patterns](#design-patterns)
6. [Komponenten-Übersicht](#komponenten-übersicht)
7. [Datenfluss](#datenfluss)
8. [Sicherheitskonzepte](#sicherheitskonzepte)

---

## Übersicht

PolitikServer ist ein Backend-Server für die Politik-Anwendung, entwickelt mit **Vapor**, einem modernen, asynchronen Web Framework für Swift. Der Server orchestriert Datensynchronisation mit dem Schweizer Parlamentsdaten-API, führt KI-basierte Analysen durch und stellt sowohl eine Web-UI (mit Leaf Templates) als auch eine REST API bereit.

**Kernfunktionalitäten:**
- Synchronisation von Parlamentsdaten aus dem OData-API (`ws.parlament.ch`)
- KI-gestützte politische Analyse via Claude API
- Session-basierte Web-UI für Administratoren
- REST API (v1) für externe Clients
- Benutzerverwaltung und Authentifizierung
- Tägliche Parlamentsberichte

---

## Technologie-Stack

### Laufzeitumgebung
- **Swift 5.10+** (Swift Tools Version)
- **macOS 14+** (Minimum Deployment Target)

### Core Web Framework
- **Vapor 4.99.0+** — Modernes, asynchrones Web Framework für Swift
  - HTTP Server & Request/Response Handling
  - Middleware-Pipeline
  - Routing System
  - Session Management
  - Error Handling

### Datenbankzugriff
- **PostgreSQL 16** — Relationsdatenbank (via Docker Compose)
- **Fluent 4.11.0+** — Async ORM für Swift
  - Database Abstraction
  - Query Builder
  - Migrations
  - Model Definition

### Datenbank-Driver
- **FluentPostgresDriver 2.9.0+** — PostgreSQL-spezifischer Fluent Driver
  - Connection Pooling
  - SQL Query Execution
  - Type-safe Database Operations

### Template Engine
- **Leaf 4.4.0+** — Swift Template Engine
  - Server-side HTML Rendering
  - Template Variables & Loops
  - Custom Leaf Tags (z.B. `raw` Tag für HTML)
  - Integration mit Vapor Views

### Testing
- **XCTVapor** — Vapor Testing Utilities
  - HTTP Request Testing
  - In-Memory Database Testing
  - Mock-Unterstützung

---

## Dependencies & Packages

### Package.swift Definition

```swift
// Swift Tools Version: 5.10
// Platform: macOS 14+

Vapor              4.99.0+  (Web Framework)
Fluent             4.11.0+  (ORM)
FluentPostgresDriver 2.9.0+ (PostgreSQL Driver)
Leaf               4.4.0+   (Template Engine)
```

### Abhängigkeits-Auflösung

Die Dependency-Struktur:

```
Vapor (HTTP, Routing, Middleware, Sessions)
  ├─ Fluent (ORM Abstraction)
  │   └─ FluentPostgresDriver (PostgreSQL Adapter)
  ├─ Leaf (Template Rendering)
  └─ [HTTP Client, Error Handling, Logging]

App (PolitikServer)
  ├─ Controllers (Route Handlers)
  ├─ Models (Fluent Models)
  ├─ Services (Business Logic)
  ├─ Middleware (Cross-cutting Concerns)
  ├─ Migrations (Schema Management)
  └─ DataStore (Persistence Abstraction)
```

---

## Architektur-Patterns

### 1. **Model-View-Controller (MVC)**

PolitikServer folgt einem Web-basierten MVC-Pattern mit klarer Separation of Concerns:

```
HTTP Request
     ↓
  Router
     ↓
  Controller (Request Handler)
     ↓
  Service Layer (Business Logic)
     ↓
  Model + DataStore (Persistence)
     ↓
  View (Leaf Template oder JSON Response)
     ↓
  HTTP Response
```

**Komponenten:**
- **Models**: Fluent ORM models (`Session`, `Geschaeft`, `Parlamentarier`, etc.)
- **Views**: Leaf templates (.leaf files) für Web-UI und JSON responses für API
- **Controllers**: 10 Controller-Klassen handhaben HTTP-Requests und delegieren an Services

### 2. **Service Layer Pattern**

Geschäftslogik ist isoliert in speziellen Service-Klassen:

```swift
// Services sind dependency-injected in die App
app.parlamentService = ParlamentService(client: app.client, logger: app.logger)
app.claudeService = ClaudeService(client: app.client, logger: app.logger, apiKey: ...)
```

**Services:**
- `ParlamentService` — OData API Integration, Data Fetching
- `ClaudeService` — KI-basierte Analyse
- `DailyReportService` — Report Generation
- `SessionSyncService` — Orchestrierung der Datensynchronisation

**Vorteile:**
- Testability: Services können gemockt werden
- Reusability: Services können von mehreren Controllern genutzt werden
- Separation of Concerns: Geschäftslogik vs. HTTP-Handling

### 3. **Repository Pattern (DataStore Abstraction)**

Eine `DataStore` Protokoll abstrahiert den Datenzugriff:

```swift
protocol DataStore: Sendable {
    var database: Database { get }
    func find<M: Model>(_ type: M.Type, id: M.IDValue) async throws -> M?
    func all<M: Model>(_ type: M.Type) async throws -> [M]
    func save<M: Model>(_ model: M) async throws
    func delete<M: Model>(_ model: M) async throws
    func query<M: Model>(_ type: M.Type) -> QueryBuilder<M>
    func transaction<T>(_ closure: @escaping (DataStore) async throws -> T) async throws -> T
}
```

**Implementierung:** `FluentDataStore` — Konkrete Implementierung mit Fluent

**Vorteile:**
- Backend-Austausch möglich (z.B. SQLite für Tests)
- Transaction-Unterstützung
- Type-safe Queries

### 4. **Middleware Pipeline Pattern**

Vapor's Middleware-System ermöglicht cross-cutting concerns:

```
FileMiddleware (Static Files)
  ↓
ErrorMiddleware (Global Error Handling)
  ↓
SessionMiddleware (Session Management)
  ↓
User.sessionAuthenticator() (Authentication)
  ↓
EnsureAuthenticatedMiddleware (Optional, Route-specific)
  ↓
EnsureAdminMiddleware (Optional, Route-specific)
  ↓
Route Handler (Controller)
```

**Middleware-Implementierungen:**
- `FileMiddleware` — Statische Dateien aus public/
- `ErrorMiddleware` — Globales Error Handling
- `SessionMiddleware` — Session-Token Management
- `User.sessionAuthenticator()` — Automatische User-Authentication aus Session
- `EnsureAuthenticatedMiddleware` — Schutz für protected Routes
- `EnsureAdminMiddleware` — Admin-only Access Control

### 5. **Service Locator Pattern**

Services werden als Properties auf der Vapor `Application` registriert:

```swift
extension Application {
    var parlamentService: ParlamentService {
        get {
            guard let service = storage[ParlamentService.storageKey] as? ParlamentService else {
                fatalError("ParlamentService not configured")
            }
            return service
        }
        set { storage[ParlamentService.storageKey] = newValue }
    }
}
```

**Zugriff in Controllern:**
```swift
let sessions = try await req.application.parlamentService.fetchSessions()
```

**Vorteile:**
- Zentrale Service-Verwaltung
- Einfache Dependency Injection
- Consistent Service Access Pattern

---

## Design-Patterns

### 1. **Async/Await Concurrency**

Alle I/O-Operationen verwenden Swift's modernes Async/Await-Modell:

```swift
// Non-blocking asynchrone API-Aufrufe
func fetchSessions() async throws -> [SessionDTO]

// Transaktionen sind async
func transaction<T>(_ closure: @escaping (DataStore) async throws -> T) async throws -> T
```

**Vorteile:**
- Natürliches Kontrollfluss-Modell
- Keine Callback-Pyramiden
- Strukturierte Concurrency mit Task Groups

### 2. **Sendable Protocol Conformance**

Services und Models konform mit `Sendable` für Thread-safe Concurrency:

```swift
struct ParlamentService: Sendable { ... }
protocol DataStore: Sendable { ... }
```

**Bedeutung:** Garantiert, dass Daten sicher zwischen Tasks geteilt werden können.

### 3. **Type-safe Dependency Injection**

Controller erhalten Dependencies über Vapor's Request-Context:

```swift
let sessions = try await req.application.parlamentService.fetchSessions()
let user = try req.auth.require(User.self)
```

**Vorteile:**
- Compile-time Type Safety
- Request-scoped Dependencies
- Keine Manual Service Lookups nötig

### 4. **Error Handling mit Vapor's ErrorMiddleware**

Unerwartete Fehler werden automatisch zu JSON oder HTML Responses:

```swift
// ErrorMiddleware konvertiert automatisch:
throw Abort(.badRequest, reason: "Invalid ID")
```

### 5. **Configuration Management**

Umgebungsvariablen für sensitive Daten:

```swift
let apiKey = Environment.get("CLAUDE_API_KEY") ?? ""
let dbConfig = SQLPostgresConfiguration(
    hostname: Environment.get("DB_HOST") ?? "localhost",
    // ...
)
```

**Sicherheit:** Secrets nie in Code hartcodieren.

### 6. **Automatic Migration System**

Schema-Migrationen laufen beim Startup automatisch:

```swift
try await app.autoMigrate()
```

**Migrationen:**
- `CreateInitialSchema` — Initiales Database Layout
- `CreateUsersTable` — User/Admin Table

### 7. **Custom Leaf Tags**

Erweiterbar mit benutzerdefinierten Template-Funktionen:

```swift
app.leaf.tags["raw"] = RawTag()  // Unsanitized HTML Output
```

---

## Komponenten-Übersicht

### Controllers (10 Stück)

| Controller | Verantwortung |
|------------|--------------|
| `AuthController` | Login, Logout, Session Management |
| `SessionController` | Parlamentssitzungs-Management |
| `GeschaeftController` | Parlamentarische Geschäfte (Bills) |
| `ParlamentarierController` | Parlamentarier (MPs) |
| `WortmeldungController` | Parlamentarische Reden/Statements |
| `AgendaController` | Tagesordnung |
| `DailyReportController` | Tägliche Berichte |
| `SyncController` | Datensynchronisation |
| `SettingsController` | Anwendungseinstellungen |
| `UserManagementController` | Admin: Benutzerverwaltung |

### Models (10 Stück)

```
Session          — Parlamentssitzung
Geschaeft        — Parlamentarisches Geschäft/Bill
Parlamentarier   — Parlamentsmitglied
Wortmeldung      — Parlamentarische Rede
Abstimmung       — Abstimmungsobjekt
Stimmabgabe      — Individuelle Stimme
Proposition      — KI-extrahierte Propositions
PersonInterest   — Interessen eines Parlamentariers
PersonOccupation — Beruf/Tätigkeit eines Parlamentariers
DailyReport      — Täglicher Parlamentsbericht
User             — Benutzer/Admin
```

### Services (4 Stück)

| Service | Verantwortung |
|---------|--------------|
| `ParlamentService` | OData API Integration, Datenbeschaffung |
| `ClaudeService` | Claude API Integration für AI-Analyse |
| `DailyReportService` | Report-Generierung |
| `SessionSyncService` | Orchestrierung der Datensynchronisation |

### Middleware (4 + 2 Custom)

**Built-in:**
- `FileMiddleware` — Statische Dateien
- `ErrorMiddleware` — Fehlerbehandlung
- `SessionMiddleware` — Session-Management
- `User.sessionAuthenticator()` — User Authentication

**Custom:**
- `EnsureAuthenticatedMiddleware` — Authentifizierung erzwingen
- `EnsureAdminMiddleware` — Admin-Zugriff erzwingen

### Migrations (2 Stück)

- `CreateInitialSchema` — Basis-Datenschema
- `CreateUsersTable` — User/Admin-Tabelle

---

## Datenfluss

### 1. **Datensynchronisation (OData API → Database)**

```
SyncController
    ↓
SessionSyncService
    ↓
ParlamentService (OData Fetch)
    ↓
ws.parlament.ch/odata.svc
    ↓
JSON Response (Sessions, Geschaefte, Wortmeldungen, etc.)
    ↓
Fluent Models (Mapping)
    ↓
PostgreSQL Database
```

**Inkrementelle Sync:**
- Modified-Timestamp-basierte Filter
- Nur Änderungen seit letzter Synchronisation

### 2. **KI-Analyse (Speech → Political Positioning)**

```
GeschaeftController.analyze()
    ↓
ClaudeService.analyzePolitician()
    ↓
Claude API (Tool Calling)
    ↓
Political Positioning Scores (7 Axes)
    ↓
Fluent Models (Save)
    ↓
PostgreSQL
```

### 3. **Web UI Rendering (Controller → Leaf Template → HTML)**

```
Request (Session-Auth)
    ↓
EnsureAuthenticatedMiddleware (Check User)
    ↓
Controller.handler()
    ↓
Database Query (Fluent)
    ↓
ViewContext (Template Variables)
    ↓
Leaf Template Rendering
    ↓
HTML Response
```

### 4. **REST API Response (JSON)**

```
Request (Basic Auth or Session)
    ↓
API Route Handler
    ↓
Service Layer (Business Logic)
    ↓
Fluent Query Builder
    ↓
JSON Encoding (Codable)
    ↓
JSON Response (Content-Type: application/json)
```

---

## Sicherheitskonzepte

### 1. **Authentifizierung**

**Web UI: Session-basiert**
```swift
app.grouped(User.sessionAuthenticator())
```
- Login via Credentials (Username/Password)
- Server-side Session Storage
- Session-Token in HTTP Cookies
- CSRF-Protection via Sessions

**API: Basic Auth**
```swift
apiAuth.grouped(User.authenticator())
       .grouped(User.guardMiddleware())
```
- HTTP Basic Authentication Header
- Credentials Verification
- Per-Request Validation

### 2. **Autorisierung (Access Control)**

**Protected Routes (Authenticated Users)**
```swift
let protected = app.grouped(EnsureAuthenticatedMiddleware())
```

**Admin-Only Routes**
```swift
let admin = protected.grouped(EnsureAdminMiddleware())
```

**Implementierung:** Middleware checken User.role

### 3. **Umgebungsvariablen für Secrets**

```swift
let apiKey = Environment.get("CLAUDE_API_KEY") ?? ""
```

**Best Practices:**
- Secrets nie in Source Code
- Environment-spezifische Konfiguration
- Docker-Container nutzen `.env` Files

### 4. **Database-Sicherheit**

**PostgreSQL Configuration:**
```swift
let dbConfig = SQLPostgresConfiguration(
    hostname: Environment.get("DB_HOST") ?? "localhost",
    username: Environment.get("DB_USER") ?? "politik",
    password: Environment.get("DB_PASSWORD") ?? "politik",
    database: Environment.get("DB_NAME") ?? "politik",
    tls: .disable  // ⚠️ Only für Local Dev; TLS in Production!
)
```

**Empfehlungen:**
- TLS in Production aktivieren (`.require` oder `.prefer`)
- Starke Passwörter
- Principle of Least Privilege für DB-User

### 5. **Input Validation**

**Leaf Templates:**
- HTML Escaping (default in Leaf)
- Custom `raw` Tag nur für trusted Content

**API Payloads:**
- Codable Structs mit Type Safety
- Vapor Validations (optional)

### 6. **CORS (wenn nötig)**

Nicht aktuell konfiguriert, aber möglich via:
```swift
app.middleware.use(CORSMiddleware(configuration: ...))
```

---

## Build & Betrieb

### Entwicklung

```bash
cd PolitikServer

# Database starten
docker compose up -d

# Build
swift build

# Server starten
swift run App serve

# Tests
swift test
```

### Environment Variables

Erforderlich für Betrieb:

```bash
DB_HOST=localhost
DB_PORT=5432
DB_USER=politik
DB_PASSWORD=your_secure_password
DB_NAME=politik
CLAUDE_API_KEY=sk-ant-v0-xxxxxxx
```

### Docker Compose

```yaml
# Lokale PostgreSQL-Instance
services:
  db:
    image: postgres:16
    environment:
      POSTGRES_USER: politik
      POSTGRES_PASSWORD: politik
      POSTGRES_DB: politik
    ports:
      - "5432:5432"
```

---

## Zusammenfassung

PolitikServer kombiniert moderne Swift-Web-Technologien mit bewährten Architektur-Patterns:

✅ **Technisch:**
- Async/Await Concurrency
- Type-safe Dependency Injection
- ORM Abstraction (Fluent)
- Template Rendering (Leaf)

✅ **Architektur:**
- MVC mit klarer Separation of Concerns
- Service Layer für Business Logic
- Repository Pattern für Datenzugriff
- Middleware Pipeline für Cross-Cutting Concerns

✅ **Sicherheit:**
- Session- & Basic-Auth
- Role-based Access Control
- Environment-basierte Secrets
- Input Validation

✅ **Skalierbarkeit:**
- Asynchrone, non-blocking I/O
- Database Connection Pooling
- Incremental Data Sync
- Transaction Support

---

**Letztes Update:** 2026-03-14
