# Lesson 10: Migrations

> **Draft.** This lesson was written ahead of time and has not yet been run against your project. Before you start it, tell me and I will check every step against your code as it stands.

**Goal:** change the database's structure safely as the code changes. `EnsureCreated()` can only build a database from nothing. A **migration** is a versioned script that takes an existing database from one shape to the next without losing its data.

**Today's C#:** very little. This lesson is mostly tooling, which should feel familiar from your DevOps work: migrations are version control for a database schema.

- [ ] Exercise 1: Install the EF tool
- [ ] Exercise 2: Your first migration
- [ ] Exercise 3: Change the model
- [ ] Exercise 4: Go backwards
- [ ] Exercise 5: Move configuration into its own class
- [ ] Exercise 6: Break it on purpose
- [ ] Notes, README, commit

## The idea

| Your code | Your database |
|---|---|
| Changes are tracked by Git commits | Changes are tracked by migrations |
| `git log` | `dotnet ef migrations list` |
| `git checkout <commit>` | `dotnet ef database update <migration>` |

Each migration is a C# file with an `Up` method (apply the change) and a `Down` method (undo it). The database keeps a table listing which migrations it has already applied.

## Exercise 1: Install the EF tool

From the repo root:

```powershell
dotnet new tool-manifest
dotnet tool install dotnet-ef
dotnet add src/DrunkenSailor.Api package Microsoft.EntityFrameworkCore.Design
```

The first command creates `dotnet-tools.json`. It pins the tool's version for everyone who clones the repo, as `global.json` pins the SDK. On a fresh clone, `dotnet tool restore` installs it.

## Exercise 2: Your first migration

Stop the server and delete `drunkensailor.db`. A database made by `EnsureCreated()` has no migration history, so the two approaches can't be mixed.

In `Program.cs`, change one line in the startup block:

```csharp
db.Database.Migrate();      // was: db.Database.EnsureCreated();
```

Then:

```powershell
dotnet ef migrations add InitialCreate --project src/DrunkenSailor.Api
```

Open the new `Migrations/` folder. There are three files:

- **`<timestamp>_InitialCreate.cs`**: read `Up` and `Down`. `Up` creates the `Boats` table and the unique index. `Down` drops them.
- **`<timestamp>_InitialCreate.Designer.cs`**: generated details. You won't edit it.
- **`AppDbContextModelSnapshot.cs`**: the model as of the latest migration. EF compares your classes to this file to work out what changed.

Apply it and start the server:

```powershell
dotnet ef database update --project src/DrunkenSailor.Api
dotnet ef migrations list --project src/DrunkenSailor.Api
```

Migration files are source code. Commit them.

## Exercise 3: Change the model

The club wants to record when each boat was last inspected. Add to `Domain/Boat.cs`:

```csharp
public DateOnly? LastInspectedOn { get; set; }
```

`DateOnly` is a date with no time of day. Then:

```powershell
dotnet ef migrations add AddBoatLastInspected --project src/DrunkenSailor.Api
```

Read the new migration's `Up` method: one `AddColumn`. Apply it with `dotnet ef database update --project src/DrunkenSailor.Api`, then call `GET /boats`. Your existing boats are still there. That's what `EnsureCreated()` couldn't do.

To see the SQL a migration will run, without running it:

```powershell
dotnet ef migrations script InitialCreate AddBoatLastInspected --project src/DrunkenSailor.Api
```

That script is what you'd hand to a production deployment.

## Exercise 4: Go backwards

```powershell
dotnet ef database update InitialCreate --project src/DrunkenSailor.Api
```

This runs `Down` for every migration after `InitialCreate`. Then remove the migration file itself:

```powershell
dotnet ef migrations remove --project src/DrunkenSailor.Api
```

`migrations remove` only works on a migration that isn't applied to the database, which is why the order matters. Now add and apply the migration again so the column is back.

A rule for working with others: once a migration has been pushed, treat it as permanent. Fix mistakes with a new migration.

## Exercise 5: Move configuration into its own class

`OnModelCreating` will grow with every entity. Give each entity its own configuration file.

Create **`Data/Configurations/BoatConfiguration.cs`**:

```csharp
using DrunkenSailor.Api.Domain;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;

namespace DrunkenSailor.Api.Data.Configurations;

public class BoatConfiguration : IEntityTypeConfiguration<Boat>
{
    public void Configure(EntityTypeBuilder<Boat> builder)
    {
        builder.Property(b => b.Name).HasMaxLength(50);
        builder.Property(b => b.Type).HasConversion<string>().HasMaxLength(20);
        builder.Property(b => b.MaintenanceNotes).HasMaxLength(1000);
        builder.HasIndex(b => b.Name).IsUnique();
    }
}
```

This is your first class that **implements an interface**: `: IEntityTypeConfiguration<Boat>` promises a `Configure` method, and the compiler holds you to it.

Replace the body of `OnModelCreating` in `AppDbContext`:

```csharp
modelBuilder.ApplyConfigurationsFromAssembly(typeof(AppDbContext).Assembly);
```

That finds every configuration class in the project. Adding max lengths changed the model, so:

```powershell
dotnet ef migrations add AddBoatColumnLimits --project src/DrunkenSailor.Api
dotnet ef database update --project src/DrunkenSailor.Api
```

## Exercise 6: Break it on purpose

1. Add a property to `Boat` (for example `public string? HullColor { get; set; }`) and start the server **without** creating a migration. Read the error. Then create and apply the migration.
2. Run `dotnet ef migrations remove` while the latest migration is applied. Read the message.
3. Open the SQLite file to look at the `__EFMigrationsHistory` table. In VS Code, the "SQLite Viewer" extension can open `.db` files.

---

## Deliverable

**Notes** (`docs/lesson-10.txt`):

1. What do `Up` and `Down` do in a migration? What is the snapshot file for?
2. After Exercise 3, your boats survived a schema change. Why couldn't `EnsureCreated()` do that?
3. What did the error in break-it 1 say? What is EF protecting you from?
4. Why should a migration that's been pushed never be edited or removed?
5. From a deployment point of view, when should migrations be applied to a production database, and who or what should run them?

**README updates:**

- Section 10: the `dotnet-ef` sentence can now say the tool is installed with `dotnet tool restore`.
- Section 11: add `dotnet tool restore` and `dotnet ef database update` as steps before `dotnet run`.
- Section 13: add the migration commands.

**Commit:**

```powershell
git add .
git commit -m "Lesson 10: manage the schema with migrations"
git push
```
