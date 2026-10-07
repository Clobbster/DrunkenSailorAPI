# Lesson 16: Authentication

> **Draft.** This lesson was written ahead of time and has not yet been run against your project. Before you start it, tell me and I will check every step against your code as it stands.

**Goal:** know who is calling. Today anyone can reserve a boat in anyone's name by typing a `skipperId`. After this lesson, callers register, log in, and send a token with each request, and a reservation belongs to whoever is logged in.

**Today's C#:** inheritance from framework classes, claims, and the `[Authorize]` attribute.

- [ ] Exercise 1: Add Identity
- [ ] Exercise 2: Register and log in
- [ ] Exercise 3: Require a token
- [ ] Exercise 4: Link accounts to members
- [ ] Exercise 5: Reservations belong to the caller
- [ ] Exercise 6: Break it on purpose
- [ ] Notes, README, commit

## Three words, again

From the Lesson 1 takeaways:

| Term | Question | Lesson |
|---|---|---|
| Identification | Who do you say you are? | 1 |
| **Authentication** | Can you prove it? | **16** |
| Authorization | Are you allowed to do this? | 17 |

The flow you're building:

```
1. POST /auth/register   email + password            → account created
2. POST /auth/login      email + password            → access token
3. GET  /boats           Authorization: Bearer <token>  → 200
   GET  /boats           (no token)                     → 401
```

ASP.NET Core Identity provides the account storage, password hashing, and those endpoints. You won't write any password-handling code, and you shouldn't.

## Exercise 1: Add Identity

```powershell
dotnet add src/DrunkenSailor.Api package Microsoft.AspNetCore.Identity.EntityFrameworkCore
```

**`Data/AppUser.cs`**

```csharp
using Microsoft.AspNetCore.Identity;

namespace DrunkenSailor.Api.Data;

public class AppUser : IdentityUser
{
}
```

`IdentityUser` already has an id, email, password hash, and more. The empty class gives you a place to add fields later.

In `AppDbContext`, change the base class and keep the call to the base method:

```csharp
public class AppDbContext(DbContextOptions<AppDbContext> options)
    : IdentityDbContext<AppUser>(options)
{
    // DbSets as before

    protected override void OnModelCreating(ModelBuilder modelBuilder)
    {
        base.OnModelCreating(modelBuilder);
        modelBuilder.ApplyConfigurationsFromAssembly(typeof(AppDbContext).Assembly);
    }
}
```

`base.OnModelCreating(modelBuilder)` runs Identity's own table setup. Leave it out and the migration fails.

In phase one of `Program.cs`:

```csharp
builder.Services.AddAuthorization();
builder.Services.AddIdentityApiEndpoints<AppUser>()
    .AddEntityFrameworkStores<AppDbContext>();
```

In phase two, before `app.MapControllers();`:

```csharp
app.MapGroup("/auth").MapIdentityApi<AppUser>();
```

```powershell
dotnet ef migrations add AddIdentity --project src/DrunkenSailor.Api
dotnet ef database update --project src/DrunkenSailor.Api
```

Read the migration. Identity adds several tables, all prefixed `AspNet`.

## Exercise 2: Register and log in

Add to `requests.http`:

```http
### Register
POST {{baseUrl}}/auth/register
Content-Type: application/json

{ "email": "ada@example.com", "password": "Sailing123!" }

### Log in
# @name login
POST {{baseUrl}}/auth/login
Content-Type: application/json

{ "email": "ada@example.com", "password": "Sailing123!" }

### Remember the token
@token = {{login.response.body.accessToken}}
```

`# @name login` names the request, and the `@token` line pulls the access token out of its response. Later requests can use `{{token}}`.

Look at the login response: `accessToken`, `expiresIn` (seconds), and `refreshToken`. In the database, look at the `AspNetUsers` table and find the `PasswordHash` column. The password itself is stored nowhere.

## Exercise 3: Require a token

Put `[Authorize]` on each controller class, above `[ApiController]`:

```csharp
using Microsoft.AspNetCore.Authorization;

[Authorize]
[ApiController]
[Route("boats")]
public class BoatsController ...
```

Restart. Call `GET /boats` with no token, then with one:

```http
### All boats
GET {{baseUrl}}/boats
Authorization: Bearer {{token}}
```

Add that `Authorization` line to every request in the file except register, login, and health. NFR-4 in the README is now true: everything except registering and logging in requires authentication.

## Exercise 4: Link accounts to members

An `AppUser` is a login. A `Member` is a person in the sailing domain, with certifications and reservations. Keep them separate and link them.

Add to `Member`:

```csharp
public string? UserId { get; set; }
```

Add a unique index on `UserId` in a `MemberConfiguration`, and migrate.

Create a `MembersController` with two endpoints:

- `POST /members/me` with a body of `{ "name": "..." }` creates the member profile for the logged-in user. It returns 409 if they already have one.
- `GET /members/me` returns that profile, or 404 if they haven't created one.

The logged-in user's id comes from the token's **claims**, which are facts about the caller that the token carries:

```csharp
using System.Security.Claims;

var userId = User.FindFirstValue(ClaimTypes.NameIdentifier)!;
var email = User.FindFirstValue(ClaimTypes.Email)!;
```

`User` is available in every controller. You'll need "the current member" in several places, so put the lookup in one spot.

**`Services/CurrentMember.cs`**

```csharp
using System.Security.Claims;
using DrunkenSailor.Api.Data;
using DrunkenSailor.Api.Domain;
using Microsoft.EntityFrameworkCore;

namespace DrunkenSailor.Api.Services;

public class CurrentMember(IHttpContextAccessor accessor, AppDbContext db)
{
    public async Task<Member?> GetAsync()
    {
        var userId = accessor.HttpContext?.User.FindFirstValue(ClaimTypes.NameIdentifier);

        if (userId is null)
            return null;

        return await db.Members
            .Include(m => m.Certifications)
            .FirstOrDefaultAsync(m => m.UserId == userId);
    }
}
```

```csharp
builder.Services.AddHttpContextAccessor();
builder.Services.AddScoped<CurrentMember>();
```

Remove the three seeded members from the seed data. Members now come from people registering.

## Exercise 5: Reservations belong to the caller

1. Delete `SkipperId` from `CreateReservationRequest`.
2. In `ReservationsController.Create`, get the skipper from `CurrentMember`. If the caller has no member profile yet, return a 409 telling them to create one.
3. Use that member when building the `ReservationContext` and the reservation.

A caller can no longer reserve in someone else's name, because there's nowhere to put another name.

## Exercise 6: Break it on purpose

1. Call `GET /boats` with no `Authorization` header. Read the status and the `WWW-Authenticate` response header.
2. Call it with `Authorization: Bearer nonsense`.
3. Register with the password `abc`. Read the validation errors.
4. Register the same email twice.
5. Log in with the wrong password.
6. Register a second user, log in as them, and create a reservation. Check whose name is on it.
7. Add `"skipperId": 1` back into a reservation request body and send it.

---

## Deliverable

**Notes** (`docs/lesson-16.txt`):

1. What status code means "we don't know who you are"? What will "we know who you are, and you can't do this" be?
2. What's stored in the `AspNetUsers` table in place of the password? Why does that matter if the database is ever stolen?
3. Why keep `AppUser` and `Member` as two separate things?
4. In break-it 7, what happened to the `skipperId` you sent? Which earlier lesson made that safe?
5. The access token expires after an hour. What's the refresh token for?
6. Any logged-in user can still delete any boat. What's missing?

**README updates:**

- Section 11: explain how to register, log in, and send the token. Mark FR-M1 and NFR-4 as done.

**Commit:**

```powershell
git add .
git commit -m "Lesson 16: registration, login, and bearer tokens"
git push
```
