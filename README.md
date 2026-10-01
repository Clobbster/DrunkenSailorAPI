# Sail Club API

A .NET 10 Web API for small sailing clubs on Michigan lakes. Members reserve club boats, skippers recruit crew, everyone files float plans, and the API enforces safety and access rules, some of which depend on live wind and wave conditions from NOAA.

> **Status:** Being built step by step as a learning project. See the [learning plan](docs/learningPlan.md) for progress.
>
> Sections 1–8 are the requirements: what the finished API must do. Sections 9 and 12 describe the **target design**, not the current code. Sections 10, 11 and 13 describe only what works **today** and grow as each lesson is completed. Items marked **TBD** are open for decision.

---

## Table of contents

1. [Purpose and goals](#1-purpose-and-goals)
2. [Scope](#2-scope)
3. [Roles](#3-roles)
4. [Domain model](#4-domain-model)
5. [Functional requirements](#5-functional-requirements)
6. [Policies](#6-policies)
7. [Non-functional requirements](#7-non-functional-requirements)
8. [External data sources](#8-external-data-sources)
9. [Architecture](#9-architecture)
10. [Prerequisites](#10-prerequisites)
11. [Getting started](#11-getting-started)
12. [Project structure](#12-project-structure)
13. [Common commands](#13-common-commands)
14. [Open questions](#14-open-questions)
15. [Glossary](#15-glossary)

---

## 1. Purpose and goals

Sailing on Michigan's Great Lakes and inland lakes depends heavily on conditions. Clubs that share boats need a way to decide who can take which boat out, when, and with whom, and to know when someone hasn't come back.

**Goals**

- G1. Let club members reserve shared boats and recruit crew.
- G2. Enforce club safety rules automatically, including rules based on forecast conditions.
- G3. Track float plans and escalate when a boat is overdue.
- G4. Explain every denied action in plain language ("Forecast gusts 21 kt exceed your 15 kt limit").
- G5. Demonstrate scoped roles, policy-based authorization, stateful workflows, and external API integration.

---

## 2. Scope

**In scope (v1)**

- Clubs, members, roles, and certifications
- Boats and reservations
- Crew requests (invite and apply)
- Float plans, check-ins, and overdue escalation
- Condition-aware reservation policies
- Incident reporting and fleet closures
- Audit log of overrides

**Out of scope (v1)**

- Payments or dues
- Real SMS/email delivery (notifications are logged or stored; delivery is **TBD**)
- Mobile or web front end (the API is tested through Scalar and `.http` files)
- Live GPS tracking

---

## 3. Roles

Roles are **scoped**: a user can be a Skipper on one reservation and Crew on another.

| Role | Scope | Summary |
|---|---|---|
| Club Admin | Club | Manages members, boats, certifications, and policies; can override blocked actions with a reason |
| Safety Officer | Club | Sets condition limits, views all active float plans, receives overdue alerts, closes the fleet |
| Skipper | Reservation | Reserves boats they're certified for, files float plans, manages crew |
| Crew | Reservation | Applies to or accepts invitations to sails, checks in and out |
| Member | Club | Browses sails, requests to crew, works toward certifications |
| Shore Contact | Float plan | Read-only access to one float plan; notified if the boat is overdue |

---

## 4. Domain model

Entities are grouped by subdomain. **Bold** entities are aggregate roots.

| Subdomain | Entities | Priority |
|---|---|---|
| Membership & Training | **Club**, ClubMembership, **Member**, Certification | Supporting |
| Fleet & Reservations | **Boat**, **Reservation**, CrewRequest | Core |
| Safety | **FloatPlan**, CheckIn, Incident, FleetClosure | Core |
| Policies | Policy, PolicyResult, PolicyOverride | Core |
| Conditions | Forecast, BuoyReading (value objects) | Generic |

### State machines

**Reservation:** `Requested → Confirmed → InProgress → Completed`, and from `Requested` or `Confirmed` to `Cancelled`

**Float plan:** `Filed → Underway → Returned`, and `Underway → Overdue → Returned`

**Crew request:** `Pending → Accepted | Declined | Withdrawn`

---

## 5. Functional requirements

Format: **ID - requirement.** *(roles allowed)*

### Membership

- **FR-M1** - A user can register and log in. *(anyone)*
- **FR-M2** - A Club Admin can create a club and invite members. *(Club Admin)*
- **FR-M3** - A Club Admin can assign and remove club roles. *(Club Admin)*
- **FR-M4** - A Club Admin can grant a certification to a member. *(Club Admin)*
- **FR-M5** - A member can view their own certifications and logged sails. *(Member)*

### Fleet and reservations

- **FR-F1** - A Club Admin can add, edit, and retire boats, including the certification each boat requires. *(Club Admin)*
- **FR-F2** - A certified member can request a reservation for a boat and time window. *(Skipper)*
- **FR-F3** - Every reservation request is checked against all active policies before it is saved. *(system)*
- **FR-F4** - A denied reservation returns every violated policy with a readable reason. *(system)*
- **FR-F5** - A Club Admin can override a denied reservation by giving a reason; the override is audited. *(Club Admin)*
- **FR-F6** - A skipper can cancel their own reservation. *(Skipper)*
- **FR-F7** - A user can ask whether an action would be allowed without performing it (dry-run evaluation). *(Member)*

### Crew

- **FR-C1** - A Skipper can post open crew spots on a reservation. *(Skipper)*
- **FR-C2** - A member can apply to an open spot. *(Member)*
- **FR-C3** - A Skipper can invite a specific member. *(Skipper)*
- **FR-C4** - A Skipper can accept or decline applications. *(Skipper)*
- **FR-C5** - Crew count cannot exceed the boat's capacity. *(system)*

### Safety

- **FR-S1** - A Skipper must file a float plan before a reservation can move to `InProgress`. *(Skipper)*
- **FR-S2** - A float plan lists people aboard, planned route, expected return time, and a Shore Contact. *(Skipper)*
- **FR-S3** - The Skipper or a crew member aboard can record departure and return check-ins. *(Skipper, Crew)*
- **FR-S4** - A float plan with no return check-in past its expected return time becomes `Overdue`. *(system)*
- **FR-S5** - Overdue escalation: notify the Shore Contact at +30 min and the Safety Officer at +60 min. *(system)*
- **FR-S6** - A Safety Officer can view all active and overdue float plans for the club. *(Safety Officer)*
- **FR-S7** - A Safety Officer can close and reopen the fleet with a reason. *(Safety Officer)*
- **FR-S8** - Any crew member can report an incident; an incident can mark a boat out of service. *(Crew, Skipper)*
- **FR-S9** - Taking a boat out of service cancels its future reservations and notifies affected Skippers. *(system)*

### Conditions

- **FR-W1** - The API can return current conditions and forecast for a club's home waters. *(Member)*
- **FR-W2** - Forecast data is cached to limit calls to NOAA services. *(system)*

---

## 6. Policies

Policies are stored as data per club so each club can set its own limits. Each policy returns pass/fail with a reason.

| ID | Policy | Rule | Overridable |
|---|---|---|---|
| POL-1 | Certification gate | Skipper must hold the certification the boat requires | Yes |
| POL-2 | Condition gate | Forecast wind, gusts, and wave height during the reservation must be within the Skipper's certification limits | Yes |
| POL-3 | Crew minimum | Boats over a set length require a minimum number aboard before confirmation | Yes |
| POL-4 | Daylight | Expected return must be before sunset unless Skipper holds "Night sailing" | Yes |
| POL-5 | Cold water | When water temperature is below a set threshold, the float plan must confirm PFDs are worn | No |
| POL-6 | Fair use | A member may hold at most N upcoming weekend reservations | Yes |
| POL-7 | Fleet closure | No new departures while the fleet is closed | Safety Officer only |
| POL-8 | Float plan privacy | Float plans are visible only to people aboard, their Shore Contact, and Safety Officers | No |

**Example denial response**

```json
{
  "allowed": false,
  "violations": [
    { "policy": "condition_gate", "detail": "Forecast gusts 21 kt exceed your 15 kt limit (Day Skipper)" },
    { "policy": "crew_minimum", "detail": "J/24 requires 2 aboard; 0 crew confirmed" }
  ],
  "overridableBy": ["club_admin"]
}
```

Default limits (TBD, to be confirmed with the club):

| Certification | Max wind | Max gust | Max waves |
|---|---|---|---|
| Day Skipper | 15 kt | 18 kt | 3 ft |
| Keelboat Skipper | 20 kt | 25 kt | 5 ft |

---

## 7. Non-functional requirements

| ID | Category | Requirement |
|---|---|---|
| NFR-1 | Portability | Runs on Windows, macOS, and Linux with only the prerequisites in section 10 |
| NFR-2 | Portability | A new developer can clone and run the API in under 15 minutes |
| NFR-3 | Portability | SDK version is pinned with `global.json`; tools are pinned with a local tool manifest |
| NFR-4 | Security | All endpoints except register/login require authentication |
| NFR-5 | Security | Secrets are never committed; local development uses `dotnet user-secrets` or a git-ignored `.env` |
| NFR-6 | Auditability | Overrides, role changes, fleet closures, and incidents are written to an audit log |
| NFR-7 | Reliability | If NOAA services are unavailable, condition-based policies fail safe (deny with reason) and the Admin can override |
| NFR-8 | Performance | Policy evaluation for a reservation completes in under 1 second using cached forecasts |
| NFR-9 | Documentation | OpenAPI document and interactive Scalar UI are available in development |
| NFR-10 | Testability | Policies are unit tested with fake condition data; integration tests use a containerized database |
| NFR-11 | Time | All times are stored in UTC and displayed in America/Detroit |

---

## 8. External data sources

| Source | Used for | Notes |
|---|---|---|
| [National Weather Service API](https://www.weather.gov/documentation/services-web-api) | Forecasts, marine zone forecasts, Small Craft Advisories | Free, no key; requires a `User-Agent` header identifying the app |
| [NOAA National Data Buoy Center](https://www.ndbc.noaa.gov/) | Live wind, gusts, waves, and water temperature | Great Lakes buoys are seasonal |
| [NOAA GLERL](https://www.glerl.noaa.gov/) | Great Lakes wave and current forecasts | Optional for v1 |
| [NOAA Tides & Currents](https://tidesandcurrents.noaa.gov/) | Great Lakes water levels and water temperature | Optional for v1 |

---

## 9. Architecture

> **Target design.** The project starts as a single project and is refactored into these layers in Lesson 20, once the reasons for them have been felt firsthand.

Layered (Clean Architecture). Dependencies point inward: Api → Application → Domain. Infrastructure implements interfaces defined in Application.

```
┌───────────────────────────────────────────────┐
│ Clients: Scalar, .http files, future web app  │
├───────────────────────────────────────────────┤
│ Api: controllers, auth, DTOs, validation      │
├───────────────────────────────────────────────┤
│ Application: services, policy engine, authz   │
├───────────────────────────────────────────────┤
│ Domain: entities, state machines, contracts   │
├───────────────────────────────────────────────┤
│ Infrastructure: EF Core, weather client,      │
│ float plan monitor (BackgroundService)        │
└───────────────────────────────────────────────┘
          │                         │
     PostgreSQL               NWS / NDBC APIs
```

**Technology**

| Concern | Choice |
|---|---|
| Runtime | .NET 10 (LTS) |
| Web framework | ASP.NET Core Web API (controllers) |
| ORM | Entity Framework Core 10 |
| Database | PostgreSQL 17 (Docker) via Npgsql |
| Auth | ASP.NET Core Identity + bearer tokens |
| API docs | OpenAPI + Scalar |
| Background jobs | `BackgroundService` |
| Tests | xUnit, `WebApplicationFactory`, Testcontainers |

---

## 10. Prerequisites

Install these on any development machine (Windows, macOS, or Linux).

| Tool | Version | Check | Download |
|---|---|---|---|
| .NET SDK | 10.0.x | `dotnet --version` | https://dotnet.microsoft.com/download/dotnet/10.0 |
| Docker Desktop (or Docker Engine + Compose) | Current | `docker --version`, `docker compose version` | https://www.docker.com/products/docker-desktop/ |
| Git | Current | `git --version` | https://git-scm.com/downloads |
| Visual Studio Code | Current | `code --version` | https://code.visualstudio.com/ |

Docker isn't needed until Lesson 12; the early lessons use SQLite, a database stored in a single file.

**VS Code extensions**

- C# Dev Kit (`ms-dotnettools.csdevkit`)
- Container Tools (`ms-azuretools.vscode-containers`)
- PostgreSQL (`ms-ossdata.vscode-pgsql`)
- REST Client (`humao.rest-client`)

`dotnet-ef` will not need a global install. When EF Core is added (Lesson 9), it will be pinned in a local tool manifest, `dotnet-tools.json`, in the repo root, and restored with `dotnet tool restore`.

---

## 11. Getting started

```bash
# 1. Clone
git clone https://github.com/<your-github-username>/DrunkenSailorAPI.git
cd DrunkenSailorAPI

# 2. Restore pinned local tools (dotnet-ef)
dotnet tool restore

# 3. Start PostgreSQL
docker compose up -d

# 4. Set the connection string (stored outside the repo)
dotnet user-secrets --project src/SailClub.Api set "ConnectionStrings:SailClub" "Host=localhost;Port=5432;Database=sailclub;Username=sailclub;Password=devpass"

# 5. Create the database schema
dotnet ef database update --project src/SailClub.Infrastructure --startup-project src/SailClub.Api

# 6. Run
dotnet run --project src/SailClub.Api
```

Open the Scalar UI at `http://localhost:<port>/scalar` (the port is in `src/SailClub.Api/Properties/launchSettings.json`).

### Portability files

These files live in the repo so every machine gets the same setup.

**`global.json`** pins the SDK:

```json
{
  "sdk": {
    "version": "10.0.100",
    "rollForward": "latestFeature"
  }
}
```

**`.config/dotnet-tools.json`** pins `dotnet-ef`. Create it once with:

```bash
dotnet new tool-manifest
dotnet tool install dotnet-ef
```

**`docker-compose.yml`** runs the database:

```yaml
services:
  db:
    image: postgres:17
    container_name: sailclub-db
    environment:
      POSTGRES_DB: sailclub
      POSTGRES_USER: sailclub
      POSTGRES_PASSWORD: devpass
    ports:
      - "5432:5432"
    volumes:
      - sailclub-data:/var/lib/postgresql/data

volumes:
  sailclub-data:
```

**`.vscode/extensions.json`** prompts teammates to install the right extensions:

```json
{
  "recommendations": [
    "ms-dotnettools.csdevkit",
    "ms-azuretools.vscode-containers",
    "ms-ossdata.vscode-pgsql",
    "humao.rest-client"
  ]
}
```

**`.gitignore`**: generate with `dotnet new gitignore`.

> The `devpass` password is for local development only. Never reuse it in a deployed environment.

---

## 12. Project structure

```
DrunkenSailorAPI/
├── .config/dotnet-tools.json
├── .vscode/extensions.json
├── docker-compose.yml
├── global.json
├── SailClub.slnx
├── README.md
├── docs/                          requirements, diagrams, decisions
├── src/
│   ├── SailClub.Api/              controllers, DTOs, auth setup, Program.cs
│   │   └── requests.http
│   ├── SailClub.Application/      services, policy engine, authorization, interfaces
│   ├── SailClub.Domain/
│   │   ├── Membership/            Club, ClubMembership, Member, Certification
│   │   ├── Fleet/                 Boat, Reservation, CrewRequest
│   │   ├── Safety/                FloatPlan, CheckIn, Incident, FleetClosure
│   │   ├── Policies/              IReservationPolicy, PolicyResult
│   │   └── Conditions/            Forecast, BuoyReading
│   └── SailClub.Infrastructure/   AppDbContext, migrations, weather client, background jobs
└── tests/
    ├── SailClub.UnitTests/        domain and policy tests
    └── SailClub.IntegrationTests/ API tests with Testcontainers
```

---

## 13. Common commands

| Task | Command |
|---|---|
| Build | `dotnet build` |
| Run API | `dotnet run --project src/SailClub.Api` |
| Run with hot reload | `dotnet watch --project src/SailClub.Api` |
| Run tests | `dotnet test` |
| Add a migration | `dotnet ef migrations add <Name> --project src/SailClub.Infrastructure --startup-project src/SailClub.Api` |
| Apply migrations | `dotnet ef database update --project src/SailClub.Infrastructure --startup-project src/SailClub.Api` |
| Start database | `docker compose up -d` |
| Stop database | `docker compose down` |
| Reset database (deletes data) | `docker compose down -v` |

---

## 14. Open questions

- [ ] Which lakes and launch sites does v1 support? (One home lake is enough to start.)
- [ ] Default condition limits per certification: confirm with a sailing instructor or club.
- [ ] How are notifications delivered in v1: stored only, email, or a webhook?
- [ ] Can a member belong to more than one club?
- [ ] Private boat owners: include in v1 or defer?
- [ ] How far ahead can reservations be made?
- [ ] Inland lakes have no buoys: which data source estimates their conditions?
- [ ] Deployment target, if any (Azure App Service, container host, or local only)?

---

## 15. Glossary

| Term | Meaning |
|---|---|
| Float plan | A record of who is aboard, where the boat is going, and when it will return, left with someone ashore |
| Shore Contact | The person ashore who is alerted if the boat doesn't return on time |
| Small Craft Advisory | NWS alert for conditions hazardous to small boats |
| kt (knots) | Nautical miles per hour; wind and boat speed unit |
| Gust | A brief increase in wind speed above the sustained wind |
| Reef | Reducing sail area in strong wind |
| Skipper | The person in charge of the boat |
| Aggregate root | The entity through which a cluster of related entities is loaded and changed |
