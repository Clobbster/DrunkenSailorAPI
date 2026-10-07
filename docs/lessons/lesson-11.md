# Lesson 11: Relationships

> **Draft.** This lesson was written ahead of time and has not yet been run against your project. Before you start it, tell me and I will check every step against your code as it stands.

**Goal:** connect things. A club owns boats, and a member reserves a boat for a time window. You'll model those links, let the database enforce them, and write the first rule that involves two records at once: a boat can't be double-booked.

**Today's C#:** navigation properties, collections on a class, `DateTime`, and projecting a query into a DTO.

- [ ] Exercise 1: Three new entities
- [ ] Exercise 2: Configure and migrate
- [ ] Exercise 3: Seed a club and members
- [ ] Exercise 4: Create a reservation
- [ ] Exercise 5: Read reservations
- [ ] Exercise 6: Break it on purpose
- [ ] Notes, README, commit

## The model

This is the part of your UML diagram being built today:

```
Club 1 ──── * Boat 1 ──── * Reservation * ──── 1 Member (the skipper)
```

In a database, "a boat belongs to a club" is a **foreign key**: the boat row stores the club's id. In C#, EF Core lets you follow that link as a property.

## Exercise 1: Three new entities

**`Domain/Club.cs`**

```csharp
namespace DrunkenSailor.Api.Domain;

public class Club
{
    public int Id { get; init; }
    public required string Name { get; set; }
    public required string HomeWaters { get; set; }

    public List<Boat> Boats { get; } = new();
}
```

**`Domain/Member.cs`**

```csharp
namespace DrunkenSailor.Api.Domain;

public class Member
{
    public int Id { get; init; }
    public required string Name { get; set; }
    public required string Email { get; set; }
}
```

**`Domain/ReservationStatus.cs`**

```csharp
namespace DrunkenSailor.Api.Domain;

public enum ReservationStatus
{
    Requested,
    Confirmed,
    InProgress,
    Completed,
    Cancelled
}
```

**`Domain/Reservation.cs`**

```csharp
namespace DrunkenSailor.Api.Domain;

public class Reservation
{
    public int Id { get; init; }

    public int BoatId { get; set; }
    public Boat Boat { get; set; } = null!;

    public int SkipperId { get; set; }
    public Member Skipper { get; set; } = null!;

    public DateTime StartUtc { get; set; }
    public DateTime EndUtc { get; set; }
    public ReservationStatus Status { get; set; }
}
```

Add to **`Domain/Boat.cs`**:

```csharp
public int ClubId { get; set; }
public Club Club { get; set; } = null!;
```

- **`BoatId`** is the foreign key: a plain number stored in the row.
- **`Boat`** is a **navigation property**: the actual boat object, which EF Core can load for you.
- **`= null!`** tells the compiler "this won't be null once EF has loaded it, trust me." It's the standard way to write a required navigation property.
- **`List<Boat> Boats`** on `Club` is the other end of the same link.

## Exercise 2: Configure and migrate

Add to `AppDbContext`:

```csharp
public DbSet<Club> Clubs => Set<Club>();
public DbSet<Member> Members => Set<Member>();
public DbSet<Reservation> Reservations => Set<Reservation>();
```

Create **`Data/Configurations/ReservationConfiguration.cs`**:

```csharp
using DrunkenSailor.Api.Domain;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;

namespace DrunkenSailor.Api.Data.Configurations;

public class ReservationConfiguration : IEntityTypeConfiguration<Reservation>
{
    public void Configure(EntityTypeBuilder<Reservation> builder)
    {
        builder.Property(r => r.Status).HasConversion<string>().HasMaxLength(20);

        builder.Property(r => r.StartUtc)
            .HasConversion(v => v, v => DateTime.SpecifyKind(v, DateTimeKind.Utc));
        builder.Property(r => r.EndUtc)
            .HasConversion(v => v, v => DateTime.SpecifyKind(v, DateTimeKind.Utc));

        builder.HasOne(r => r.Boat)
            .WithMany()
            .HasForeignKey(r => r.BoatId)
            .OnDelete(DeleteBehavior.Restrict);

        builder.HasOne(r => r.Skipper)
            .WithMany()
            .HasForeignKey(r => r.SkipperId)
            .OnDelete(DeleteBehavior.Restrict);

        builder.HasIndex(r => new { r.BoatId, r.StartUtc });
    }
}
```

- **`OnDelete(DeleteBehavior.Restrict)`** means a boat with reservations can't be deleted. The default would delete its reservations along with it.
- **The two `HasConversion` lines** work around a SQLite limitation: it doesn't remember that a time is UTC. They go away in Lesson 12.

Existing boat rows have no club, so the new required `ClubId` column can't be filled in. With only sample data at stake, start fresh:

```powershell
dotnet ef database drop --project src/DrunkenSailor.Api
dotnet ef migrations add AddClubsMembersReservations --project src/DrunkenSailor.Api
```

Read the migration: three `CreateTable` calls, an `AddColumn` on `Boats`, and the foreign keys.

## Exercise 3: Seed a club and members

Replace the seeding block in `Program.cs`. Boats are now created inside a club:

```csharp
if (!db.Clubs.Any())
{
    var club = new Club { Name = "Grand Haven Sail Club", HomeWaters = "Lake Michigan" };
    club.Boats.AddRange(new[]
    {
        new Boat { Name = "Wet Noodle",    Type = BoatType.Sailboat,     LengthFt = 24, Capacity = 4, InService = true },
        new Boat { Name = "Second Wind",   Type = BoatType.Sailboat,     LengthFt = 19, Capacity = 3, InService = true },
        new Boat { Name = "Knot Today",    Type = BoatType.Sailboat,     LengthFt = 30, Capacity = 6, InService = false,
                   MaintenanceNotes = "Cracked rudder. Waiting on the insurer." },
        new Boat { Name = "Safety Dance",  Type = BoatType.Motorboat,    LengthFt = 16, Capacity = 4, InService = true },
        new Boat { Name = "Paddle Faster", Type = BoatType.HumanPowered, LengthFt = 12, Capacity = 1, InService = true }
    });
    db.Clubs.Add(club);

    db.Members.AddRange(
        new Member { Name = "Ada Skipper",  Email = "ada@example.com" },
        new Member { Name = "Ben Crew",     Email = "ben@example.com" },
        new Member { Name = "Cy Beginner",  Email = "cy@example.com" });

    db.SaveChanges();
}
```

You add the boats to the club's list and save the club. EF Core works out the order of inserts and fills in each boat's `ClubId`.

`CreateBoatRequest` now needs a `ClubId`, and `BoatsController.Create` must set it and confirm the club exists. Make that change, then start the server.

## Exercise 4: Create a reservation

**`Contracts/CreateReservationRequest.cs`**

```csharp
namespace DrunkenSailor.Api.Contracts;

public record CreateReservationRequest(
    int BoatId,
    int SkipperId,
    DateTime StartUtc,
    DateTime EndUtc);
```

**`Contracts/ReservationResponse.cs`**

```csharp
using DrunkenSailor.Api.Domain;

namespace DrunkenSailor.Api.Contracts;

public record ReservationResponse(
    int Id,
    int BoatId,
    string BoatName,
    int SkipperId,
    string SkipperName,
    DateTime StartUtc,
    DateTime EndUtc,
    ReservationStatus Status);
```

Create **`Controllers/ReservationsController.cs`** with a `Create` method. It checks, in order:

| Check | If it fails |
|---|---|
| Both times are UTC, and the end is after the start | `400` validation problem |
| The boat exists | `400` validation problem on `boatId` |
| The skipper exists | `400` validation problem on `skipperId` |
| The boat is in service | `409 Conflict` |
| No other active reservation overlaps | `409 Conflict` |

The overlap check is the heart of the lesson:

```csharp
var overlaps = await db.Reservations.AnyAsync(r =>
    r.BoatId == request.BoatId &&
    r.Status != ReservationStatus.Cancelled &&
    r.StartUtc < request.EndUtc &&
    request.StartUtc < r.EndUtc);

if (overlaps)
{
    return Problem(
        title: "Boat already reserved",
        detail: "Another reservation overlaps that time window.",
        statusCode: StatusCodes.Status409Conflict);
}
```

Two windows overlap when each one starts before the other ends. Draw two bars on paper and test that rule against a few cases before trusting it.

To check that a time is UTC: `request.StartUtc.Kind == DateTimeKind.Utc`. A JSON time ending in `Z` is read as UTC.

Try it:

```http
### Reserve Wet Noodle
POST {{baseUrl}}/reservations
Content-Type: application/json

{
  "boatId": 1,
  "skipperId": 1,
  "startUtc": "2026-10-10T14:00:00Z",
  "endUtc": "2026-10-10T18:00:00Z"
}
```

The skipper id is in the request body for now, which means anyone can reserve in anyone's name. Lesson 16 replaces it with the logged-in user.

## Exercise 5: Read reservations

Add `GET /reservations/{id}` and, on the boats controller, `GET /boats/{id}/reservations`. Build the response inside the query:

```csharp
var reservations = await db.Reservations
    .Where(r => r.BoatId == id)
    .OrderBy(r => r.StartUtc)
    .Select(r => new ReservationResponse(
        r.Id,
        r.BoatId,
        r.Boat.Name,
        r.SkipperId,
        r.Skipper.Name,
        r.StartUtc,
        r.EndUtc,
        r.Status))
    .ToListAsync();
```

`r.Boat.Name` reaches across the relationship. Read the SQL in the server log: EF Core wrote the `JOIN`s for you and selected only the columns the response needs.

`/boats/{id}/reservations` is a **sub-resource** URL, the pattern you saw in the weather service's `/gridpoints/.../forecast`.

## Exercise 6: Break it on purpose

1. Reserve "Wet Noodle" for 14:00 to 18:00, then try 16:00 to 20:00, then 18:00 to 20:00. Which are refused?
2. Reserve "Knot Today", which is out of service.
3. Send a start time without the `Z`.
4. `DELETE` a boat that has a reservation. Read the status and the server log.
5. Temporarily return entities instead of DTOs: in `GET /boats/{id}/reservations`, replace the `Select` with `.Include(r => r.Boat).ThenInclude(b => b.Club)` and return the list. Read the error. Restore the `Select`.

---

## Deliverable

**Notes** (`docs/lesson-11.txt`):

1. What's the difference between `BoatId` and `Boat` on a reservation?
2. In break-it 1, which requests were refused? Is a reservation that starts exactly when another ends an overlap, according to your code? Is that the right rule for a sailing club?
3. Why is a double booking a 409 and not a 400?
4. What went wrong in break-it 5? How do DTOs prevent it?
5. Break-it 4 returned a 500. What should it return, and what would you change?

**README updates:**

- Section 11: add the reservation endpoints.
- FR-F2 says "a certified member can request a reservation." Note next to it which parts work today.

**Commit:**

```powershell
git add .
git commit -m "Lesson 11: clubs, members, and reservations"
git push
```
