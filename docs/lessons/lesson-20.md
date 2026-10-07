# Lesson 20: Refactoring into layers

> **Draft.** This lesson was written ahead of time and has not yet been run against your project. Before you start it, tell me and I will check every step against your code as it stands.

**Goal:** split the single project into the four layers in section 9 of the README, so the compiler enforces which code may depend on which. No behavior changes. If every request and every test gives the same result afterwards, the lesson worked.

**Today's C#:** project references, namespaces, and extension methods for registering services.

- [ ] Exercise 1: Feel the problem
- [ ] Exercise 2: Create the projects and references
- [ ] Exercise 3: Move the domain
- [ ] Exercise 4: Move the application layer
- [ ] Exercise 5: Move the infrastructure
- [ ] Exercise 6: Tidy the wiring
- [ ] Exercise 7: Break it on purpose
- [ ] Notes, README, commit

## Why now

On October 4 you asked whether any of the API followed a layered architecture, and the answer was "not yet, on purpose." You've since built everything the layers are meant to organize. Open the project and look at what sits side by side in one place:

- `Reservation.cs`, which is pure rules with no dependencies
- `NwsWeatherService.cs`, which makes network calls
- `AppDbContext.cs`, which knows about PostgreSQL
- `BoatsController.cs`, which knows about HTTP

Nothing stops `Reservation` from calling the weather service or a policy from running SQL. Only your discipline does.

## The target

```
            ┌────────────────────┐
            │  DrunkenSailor.Api │  controllers, contracts, Program.cs
            └─────────┬──────────┘
                      │ references
        ┌─────────────┴──────────────┐
        ▼                            ▼
┌───────────────────┐      ┌──────────────────────────────┐
│ ...Application    │◄─────│ ...Infrastructure            │
│ policies,         │      │ EF Core, migrations, weather │
│ service contracts │      │ client, background jobs      │
└─────────┬─────────┘      └──────────────────────────────┘
          ▼
┌───────────────────┐
│ ...Domain         │  entities, enums, DomainException
└───────────────────┘
```

| Project | Contains | May reference |
|---|---|---|
| `Domain` | Entities, enums, `DomainException` | Nothing |
| `Application` | Policies, evaluator, `IWeatherService`, `INotificationService`, `HourlyForecast` | Domain |
| `Infrastructure` | `AppDbContext`, configurations, migrations, `AppUser`, `NwsWeatherService`, notifications, float plan monitor and escalator | Application, Domain |
| `Api` | Controllers, contracts, authorization handlers, `Program.cs` | Application, Infrastructure |

The interfaces live in Application and their implementations live in Infrastructure. That's why the Infrastructure arrow points *at* Application: the inner layer says what it needs, and the outer layer provides it.

## Before you start

1. Commit everything. The working tree must be clean.
2. Create a branch: `git switch -c layers`.
3. Run `dotnet test` and every request in `requests.http`. This is your baseline.

Work in small steps and build after each one. Use `git mv` to move files so their history follows them. When the build breaks, read the first error only, fix it, and build again.

## Exercise 1: Feel the problem

In `Domain/Reservation.cs`, add `using DrunkenSailor.Api.Weather;` and a field of type `NwsWeatherService`. Build. It compiles, and it shouldn't be allowed to. Remove both lines.

By the end of this lesson, that same edit will be a compile error.

## Exercise 2: Create the projects and references

```powershell
dotnet new classlib -n DrunkenSailor.Domain         -o src/DrunkenSailor.Domain
dotnet new classlib -n DrunkenSailor.Application    -o src/DrunkenSailor.Application
dotnet new classlib -n DrunkenSailor.Infrastructure -o src/DrunkenSailor.Infrastructure

dotnet sln add src/DrunkenSailor.Domain src/DrunkenSailor.Application src/DrunkenSailor.Infrastructure

dotnet add src/DrunkenSailor.Application    reference src/DrunkenSailor.Domain
dotnet add src/DrunkenSailor.Infrastructure reference src/DrunkenSailor.Application
dotnet add src/DrunkenSailor.Api            reference src/DrunkenSailor.Application src/DrunkenSailor.Infrastructure
```

Delete the `Class1.cs` placeholder from each. A **class library** is a project with no `Program.cs`. It can't run by itself and exists to be referenced. Build to confirm the empty structure works.

## Exercise 3: Move the domain

```powershell
git mv src/DrunkenSailor.Api/Domain/* src/DrunkenSailor.Domain/
```

In each moved file, change the namespace:

```csharp
namespace DrunkenSailor.Domain;      // was DrunkenSailor.Api.Domain
```

Then, across the solution, replace `using DrunkenSailor.Api.Domain;` with `using DrunkenSailor.Domain;`. VS Code's search and replace across files (Ctrl+Shift+H) does this in one step.

Build. The Domain project should compile with **no package references at all**. If an entity needs a package, something that isn't domain logic has crept into it.

## Exercise 4: Move the application layer

Move into `src/DrunkenSailor.Application/`:

- the whole `Policies/` folder
- `Weather/IWeatherService.cs` and `Weather/HourlyForecast.cs`
- `Notifications/INotificationService.cs`

Leave `NwsWeatherService.cs` and `LoggingNotificationService.cs` where they are for now. Update namespaces to `DrunkenSailor.Application.Policies` and so on, fix the `using` lines, and build.

`NotInThePastRule` uses `TimeProvider`, which is part of .NET itself, so no package is needed.

## Exercise 5: Move the infrastructure

Add the framework reference so this library can use ASP.NET Core and hosting types. In `DrunkenSailor.Infrastructure.csproj`, inside an `<ItemGroup>`:

```xml
<FrameworkReference Include="Microsoft.AspNetCore.App" />
```

Move the EF Core and Identity packages from the Api project to Infrastructure:

```powershell
dotnet add src/DrunkenSailor.Infrastructure package Npgsql.EntityFrameworkCore.PostgreSQL
dotnet add src/DrunkenSailor.Infrastructure package Microsoft.AspNetCore.Identity.EntityFrameworkCore
dotnet remove src/DrunkenSailor.Api package Npgsql.EntityFrameworkCore.PostgreSQL
dotnet remove src/DrunkenSailor.Api package Microsoft.AspNetCore.Identity.EntityFrameworkCore
```

Keep `Microsoft.EntityFrameworkCore.Design` in the Api project. The EF tool needs it in the project that starts the app.

Move into `src/DrunkenSailor.Infrastructure/`:

- the whole `Data/` folder, including `Configurations/` and `AppUser.cs`
- the whole `Migrations/` folder
- `Weather/NwsWeatherService.cs`
- `Notifications/LoggingNotificationService.cs`
- the `FloatPlans/` folder

Update namespaces and `using` lines, and build until it's clean.

The migration commands now name two projects, because the migrations live in one and the app starts from another:

```powershell
dotnet ef migrations list --project src/DrunkenSailor.Infrastructure --startup-project src/DrunkenSailor.Api
```

That should list every migration you've made, unchanged.

## Exercise 6: Tidy the wiring

`Program.cs` still registers every service by hand. Give each layer one method that registers its own.

**`src/DrunkenSailor.Application/DependencyInjection.cs`**

```csharp
using DrunkenSailor.Application.Policies;
using Microsoft.Extensions.DependencyInjection;

namespace DrunkenSailor.Application;

public static class DependencyInjection
{
    public static IServiceCollection AddApplication(this IServiceCollection services)
    {
        services.AddSingleton(TimeProvider.System);
        services.AddScoped<IReservationPolicy, CertificationGate>();
        services.AddScoped<IReservationPolicy, FairUseRule>();
        services.AddScoped<IReservationPolicy, NotInThePastRule>();
        services.AddScoped<IReservationPolicy, ConditionGate>();
        services.AddScoped<PolicyEvaluator>();

        return services;
    }
}
```

The Application project needs one package for this:

```powershell
dotnet add src/DrunkenSailor.Application package Microsoft.Extensions.DependencyInjection.Abstractions
```

Write `AddInfrastructure(this IServiceCollection services, IConfiguration configuration)` in the Infrastructure project yourself. It registers the database context, Identity stores, the weather client, the memory cache, the notification service, the escalator, and the monitor.

`Program.cs` then reads:

```csharp
builder.Services.AddApplication();
builder.Services.AddInfrastructure(builder.Configuration);
```

These are extension methods, the same feature as `ToResponse()` from Lesson 6, applied to service registration. It's how `AddControllers()` and `AddDbContext()` work too.

Finally, point the unit tests at the layers they test:

```powershell
dotnet remove tests/DrunkenSailor.UnitTests reference src/DrunkenSailor.Api
dotnet add tests/DrunkenSailor.UnitTests reference src/DrunkenSailor.Domain src/DrunkenSailor.Application
```

The `ToKnots` test needs `NwsWeatherService`, which is now in Infrastructure. Move the `InternalsVisibleTo` line to that project and add the reference, or move that one test to the integration tests in Lesson 21.

Run `dotnet test` and every request in `requests.http`. Compare against your baseline.

## Exercise 7: Break it on purpose

1. Repeat Exercise 1: in `Reservation.cs`, try to use `NwsWeatherService`. Read the error.
2. In `CertificationGate.cs`, add `using DrunkenSailor.Infrastructure.Data;` and try to use `AppDbContext`.
3. In the Domain project, run `dotnet add package Microsoft.EntityFrameworkCore`. It will succeed. Then think about why you shouldn't, and remove it.
4. Run `dotnet build src/DrunkenSailor.Domain` alone. Note how fast it is and what it didn't need.

When everything passes, merge the branch:

```powershell
git switch main
git merge layers
```

---

## Deliverable

**Notes** (`docs/lesson-20.txt`):

1. What errors did break-its 1 and 2 give? Before today, what prevented those mistakes?
2. `IWeatherService` is in Application and `NwsWeatherService` is in Infrastructure. Why are they in different projects?
3. Your controllers still use `AppDbContext` directly, so the Api project depends on Infrastructure for more than wiring. A stricter design would hide the database behind interfaces defined in Application. What would that gain, and what would it cost?
4. Did any behavior change? How do you know?
5. Was it right to wait until Lesson 20 for this? What would have been harder, and what easier, if the layers had existed from Lesson 3?

**README updates:**

- Section 9: remove the "Target design" note. It's the current design now.
- Section 12: the "Today" tree and the "Target design" tree should now match. Keep one.
- Section 13: update the migration commands with `--startup-project`.

**Commit:**

```powershell
git add .
git commit -m "Lesson 20: split into Domain, Application, Infrastructure, and Api"
git push
```
