# Lesson 17: Authorization and scoped roles

> **Draft.** This lesson was written ahead of time and has not yet been run against your project. Before you start it, tell me and I will check every step against your code as it stands.

**Goal:** decide what each logged-in person may do. Only a club's admin may manage its boats, and only a reservation's own skipper (or an admin) may cancel it. Roles here are **scoped**: you're an admin of *this club* and the skipper of *this reservation*, not an admin of everything.

**Today's C#:** authorization requirements and handlers, which are another use of interfaces and dependency injection.

- [ ] Exercise 1: Club memberships and roles
- [ ] Exercise 2: Joining a club
- [ ] Exercise 3: A requirement and its handler
- [ ] Exercise 4: Protect the boat endpoints
- [ ] Exercise 5: Protect a reservation
- [ ] Exercise 6: Break it on purpose
- [ ] Notes, README, commit

## Two kinds of authorization

| Kind | Question | Example |
|---|---|---|
| Role-based | Does the user have role X? | "Is this user an admin?" |
| **Resource-based** | May this user do this to **this specific thing**? | "Is this user an admin of the club that owns this boat?" |

The first is simpler and is enough for many apps. This API needs the second, because the answer depends on which club or reservation is involved. That's the scoped-roles table in section 3 of the README.

## Exercise 1: Club memberships and roles

**`Domain/ClubRole.cs`**

```csharp
namespace DrunkenSailor.Api.Domain;

public enum ClubRole
{
    Member = 0,
    SafetyOfficer = 1,
    ClubAdmin = 2
}
```

The numbers are written out on purpose. The code below compares roles with `>=`, so their order is part of the design and shouldn't change by accident.

**`Domain/ClubMembership.cs`**

```csharp
namespace DrunkenSailor.Api.Domain;

public class ClubMembership
{
    public int Id { get; init; }

    public int ClubId { get; set; }
    public Club Club { get; set; } = null!;

    public int MemberId { get; set; }
    public Member Member { get; set; } = null!;

    public ClubRole Role { get; set; }
}
```

Add a `DbSet<ClubMembership>`, a configuration that stores `Role` as a string and puts a unique index on `ClubId` plus `MemberId`, and a migration.

## Exercise 2: Joining a club

Someone has to be the first admin. Use a simple rule: the first member to join a club becomes its admin, and everyone after joins as a plain member.

Create a `ClubsController` with:

- `GET /clubs`
- `POST /clubs/{clubId}/join` for the current member. It returns 409 if they already belong.
- `PUT /clubs/{clubId}/members/{memberId}/role` to change someone's role. You'll protect it in Exercise 4.

Register, create your member profile, and join the seeded club. Check the `ClubMemberships` table: your role should be `ClubAdmin`. Then register a second user and join again as them.

## Exercise 3: A requirement and its handler

Authorization in ASP.NET Core is built from two pieces:

- A **requirement** says what is needed. It's plain data.
- A **handler** decides whether the current user meets it for a given resource.

Create an `Authorization/` folder.

**`Authorization/ClubRoleRequirement.cs`**

```csharp
using DrunkenSailor.Api.Domain;
using Microsoft.AspNetCore.Authorization;

namespace DrunkenSailor.Api.Authorization;

public class ClubRoleRequirement(ClubRole minimumRole) : IAuthorizationRequirement
{
    public ClubRole MinimumRole => minimumRole;
}
```

**`Authorization/ClubRoleHandler.cs`**

```csharp
using System.Security.Claims;
using DrunkenSailor.Api.Data;
using DrunkenSailor.Api.Domain;
using Microsoft.AspNetCore.Authorization;
using Microsoft.EntityFrameworkCore;

namespace DrunkenSailor.Api.Authorization;

public class ClubRoleHandler(AppDbContext db) : AuthorizationHandler<ClubRoleRequirement, Club>
{
    protected override async Task HandleRequirementAsync(
        AuthorizationHandlerContext context,
        ClubRoleRequirement requirement,
        Club club)
    {
        var userId = context.User.FindFirstValue(ClaimTypes.NameIdentifier);

        if (userId is null)
            return;

        var membership = await db.ClubMemberships
            .FirstOrDefaultAsync(m => m.ClubId == club.Id && m.Member.UserId == userId);

        if (membership is not null && membership.Role >= requirement.MinimumRole)
            context.Succeed(requirement);
    }
}
```

A handler never says "no." It either calls `context.Succeed(...)` or does nothing, and doing nothing means the requirement isn't met.

Register the handler and name two policies in phase one:

```csharp
builder.Services.AddScoped<IAuthorizationHandler, ClubRoleHandler>();

builder.Services.AddAuthorization(options =>
{
    options.AddPolicy("ClubAdmin", policy =>
        policy.AddRequirements(new ClubRoleRequirement(ClubRole.ClubAdmin)));

    options.AddPolicy("SafetyOfficer", policy =>
        policy.AddRequirements(new ClubRoleRequirement(ClubRole.SafetyOfficer)));
});
```

Replace the earlier plain `AddAuthorization()` call with this one.

"Policy" now means two things in this project. An **authorization policy** decides who may call an endpoint. A **reservation policy**, from Lesson 14, decides whether a booking meets club rules. Keep them apart in your head and in your notes.

## Exercise 4: Protect the boat endpoints

`[Authorize]` alone can't do this job, because it runs before your code has loaded the boat and can't know which club is involved. Ask for the check yourself once you have the resource.

Add `IAuthorizationService authorization` to the `BoatsController` constructor. In `Create`:

```csharp
var club = await db.Clubs.FindAsync(request.ClubId);

if (club is null)
    return ClubNotFound(request.ClubId);

var check = await authorization.AuthorizeAsync(User, club, "ClubAdmin");

if (!check.Succeeded)
    return Forbid();
```

`Forbid()` returns **403**.

For `Update`, `Delete`, and the two service-status actions, load the boat with its club first (`Include(b => b.Club)`), then check against `boat.Club`. Reading boats stays open to any logged-in user.

Protect the role-change endpoint from Exercise 2 the same way. This implements FR-F1 and FR-M3.

## Exercise 5: Protect a reservation

FR-F6: a skipper can cancel their own reservation. An admin of the boat's club can too.

**`Authorization/ReservationOwnerRequirement.cs`**

```csharp
using Microsoft.AspNetCore.Authorization;

namespace DrunkenSailor.Api.Authorization;

public class ReservationOwnerRequirement : IAuthorizationRequirement
{
}
```

Write `ReservationOwnerHandler : AuthorizationHandler<ReservationOwnerRequirement, Reservation>` yourself, following the club handler. It succeeds when either is true:

- the reservation's skipper has the current user's id, or
- the current user holds `ClubAdmin` in the club that owns the reservation's boat.

Register it, add a policy named `"ReservationOwner"`, and use it in `Cancel`. Confirming a reservation should require `SafetyOfficer` or above in the boat's club.

## Exercise 6: Break it on purpose

Use two accounts: Ada (admin, joined first) and Ben (member).

1. As Ben, `POST` a new boat.
2. As Ben, `DELETE` a boat.
3. As Ada, create a reservation. As Ben, cancel it.
4. As Ada, cancel Ben's reservation.
5. As Ada, promote Ben to `SafetyOfficer`. As Ben, confirm a reservation.
6. As Ben (now a Safety Officer), `POST` a new boat.
7. With no token at all, `DELETE` a boat.

---

## Deliverable

**Notes** (`docs/lesson-17.txt`):

1. Which break-its returned 403, and which returned 401? State the difference in one sentence.
2. Why couldn't a plain `[Authorize(Roles = "Admin")]` attribute express "admin of this boat's club"?
3. The handler compares roles with `>=`. What does that assume about a Club Admin and a Safety Officer? Is the assumption right for a real club?
4. In break-it 3, Ben got a 403, which confirms that the reservation exists. Some APIs return 404 in that situation. Why might they?
5. Authorization policies and reservation policies both end in a 403. What's different about what each one is checking?

**README updates:**

- Section 3: note which roles are implemented. Section 5: mark FR-F1, FR-F6, FR-M2 (in part), and FR-M3.

**Commit:**

```powershell
git add .
git commit -m "Lesson 17: club roles and resource-based authorization"
git push
```
