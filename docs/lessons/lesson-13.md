# Lesson 13: Rules that live in the domain

> **Draft.** This lesson was written ahead of time and has not yet been run against your project. Before you start it, tell me and I will check every step against your code as it stands.

**Goal:** make it impossible for the rest of the code to put a reservation or a boat into a state that breaks the rules. A reservation moves through fixed steps, and only the `Reservation` class decides which moves are allowed. This is the state machine from section 4 of the README.

**Today's C#:** `private set`, methods on entities, throwing and catching exceptions, and `switch`.

- [ ] Exercise 1: A domain exception
- [ ] Exercise 2: Lock down the reservation
- [ ] Exercise 3: Expose the transitions
- [ ] Exercise 4: Turn rule violations into 409s
- [ ] Exercise 5: Taking a boat out of service
- [ ] Exercise 6: Break it on purpose
- [ ] Notes, README, commit

## The state machine

```
Requested ──► Confirmed ──► InProgress ──► Completed
    │             │
    └─────────────┴──► Cancelled
```

Today, `Status` has a public setter. Any code can write `reservation.Status = ReservationStatus.Completed` on a reservation that was cancelled last week. Nothing stops it.

## Exercise 1: A domain exception

Create **`Domain/DomainException.cs`**:

```csharp
namespace DrunkenSailor.Api.Domain;

public class DomainException : Exception
{
    public DomainException(string message) : base(message)
    {
    }
}
```

This is an exception type of your own. It means "a business rule was broken," as distinct from a bug. `: base(message)` passes the message up to the built-in `Exception` class.

## Exercise 2: Lock down the reservation

In **`Domain/Reservation.cs`**, change the status property and add four methods:

```csharp
public ReservationStatus Status { get; private set; }

public void Confirm()
{
    if (Status != ReservationStatus.Requested)
        throw new DomainException($"Only a requested reservation can be confirmed. This one is {Status}.");

    Status = ReservationStatus.Confirmed;
}

public void Start()
{
    if (Status != ReservationStatus.Confirmed)
        throw new DomainException($"Only a confirmed reservation can start. This one is {Status}.");

    Status = ReservationStatus.InProgress;
}

public void Complete()
{
    if (Status != ReservationStatus.InProgress)
        throw new DomainException($"Only a reservation in progress can be completed. This one is {Status}.");

    Status = ReservationStatus.Completed;
}

public void Cancel()
{
    if (Status != ReservationStatus.Requested && Status != ReservationStatus.Confirmed)
        throw new DomainException($"A reservation that is {Status} can't be cancelled.");

    Status = ReservationStatus.Cancelled;
}
```

- **`private set`** means only code inside `Reservation` can change the status. This is the variation described in the Lesson 4 takeaways.
- **`throw`** stops the method immediately and reports a problem to whoever called it.
- A new reservation needs no change. `Requested` is the first enum value, so it's the default.

Build. Any code that assigned `Status` directly no longer compiles, which is the compiler listing every place that bypassed the rules.

## Exercise 3: Expose the transitions

Changing state is an action, not a field update, so each transition gets its own URL. Add to `ReservationsController`:

```csharp
[HttpPost("{id:int}/confirm")]
public async Task<ActionResult<ReservationResponse>> Confirm(int id)
{
    var reservation = await db.Reservations
        .Include(r => r.Boat)
        .Include(r => r.Skipper)
        .FirstOrDefaultAsync(r => r.Id == id);

    if (reservation is null)
        return ReservationNotFound(id);

    reservation.Confirm();
    await db.SaveChangesAsync();

    return Ok(reservation.ToResponse());
}
```

**`Include`** tells EF Core to load the related boat and skipper along with the reservation, so the response can show their names.

This needs two small helpers that you write yourself, following the boat versions: a `ToResponse` extension method for `Reservation` in `Contracts/`, and a private `ReservationNotFound(int id)` method on the controller.

Write `Start`, `Complete`, and `Cancel` the same way. The four methods will be nearly identical. Notice that, and think about how you might remove the repetition once all four work.

## Exercise 4: Turn rule violations into 409s

Call `POST /reservations/1/confirm` twice. The second call throws, and the caller gets a 500. A broken business rule is the caller's mistake, so it should be a 409.

Create **`Errors/DomainExceptionHandler.cs`**:

```csharp
using DrunkenSailor.Api.Domain;
using Microsoft.AspNetCore.Diagnostics;
using Microsoft.AspNetCore.Mvc;

namespace DrunkenSailor.Api.Errors;

public class DomainExceptionHandler(IProblemDetailsService problemDetails) : IExceptionHandler
{
    public async ValueTask<bool> TryHandleAsync(
        HttpContext httpContext,
        Exception exception,
        CancellationToken cancellationToken)
    {
        if (exception is not DomainException domainException)
            return false;

        httpContext.Response.StatusCode = StatusCodes.Status409Conflict;

        return await problemDetails.TryWriteAsync(new ProblemDetailsContext
        {
            HttpContext = httpContext,
            ProblemDetails = new ProblemDetails
            {
                Title = "That action isn't allowed right now",
                Detail = domainException.Message,
                Status = StatusCodes.Status409Conflict
            }
        });
    }
}
```

Register it in phase one, before `AddProblemDetails()`:

```csharp
builder.Services.AddExceptionHandler<DomainExceptionHandler>();
```

Returning `false` means "not mine, let the next handler deal with it," so real bugs still become 500s. This plugs into the `UseExceptionHandler()` middleware from Lesson 7.

## Exercise 5: Taking a boat out of service

Apply the same idea to `Boat`. In **`Domain/Boat.cs`**:

```csharp
public bool InService { get; private set; } = true;

public void TakeOutOfService(string reason)
{
    if (!InService)
        throw new DomainException($"{Name} is already out of service.");

    InService = false;
    MaintenanceNotes = reason;
}

public void ReturnToService()
{
    if (InService)
        throw new DomainException($"{Name} is already in service.");

    InService = true;
}
```

Then:

1. Remove `InService` from `UpdateBoatRequest`, and remove `InService = true` from wherever boats are created. For the one seeded boat that's out of service, call `TakeOutOfService("Cracked rudder. Waiting on the insurer.")` on it after creating it.
2. Add `POST /boats/{id}/out-of-service`, with a small request record holding a `Reason`, and `POST /boats/{id}/return-to-service`.
3. Implement FR-S9: taking a boat out of service cancels its future reservations.

```csharp
var future = await db.Reservations
    .Where(r => r.BoatId == id
        && r.StartUtc > DateTime.UtcNow
        && (r.Status == ReservationStatus.Requested || r.Status == ReservationStatus.Confirmed))
    .ToListAsync();

boat.TakeOutOfService(request.Reason);

foreach (var reservation in future)
    reservation.Cancel();

await db.SaveChangesAsync();
```

One `SaveChangesAsync()` sends the boat update and every cancellation together, in a single transaction. Either all of it is saved or none of it is.

Adding the default value changes the model, so create and apply a migration.

## Exercise 6: Break it on purpose

1. Confirm a reservation twice.
2. Create a reservation, cancel it, then try to start it.
3. Walk one reservation through every step to `Completed`, then cancel it.
4. Reserve a boat for next week, take the boat out of service, then `GET` the reservation.
5. In a controller, try writing `reservation.Status = ReservationStatus.Completed;` and build.

---

## Deliverable

**Notes** (`docs/lesson-13.txt`):

1. What did the compiler say in break-it 5? Compare that protection with a rule that's only written in a comment or a README.
2. Why is `POST /reservations/1/confirm` a better design than `PUT /reservations/1` with `"status": "Confirmed"` in the body?
3. Why does a rule violation return 409 while an unexpected bug returns 500? Who needs to act in each case?
4. In Exercise 5, what would go wrong if the boat update and the cancellations were saved separately and the second save failed?
5. The four transition methods in the controller repeat. Describe one way to reduce the repetition.

**README updates:**

- Section 4: the Reservation state machine is now implemented. Section 5: mark FR-S9 as done.
- Section 11: add the new action endpoints.

**Commit:**

```powershell
git add .
git commit -m "Lesson 13: reservation state machine and boat service status"
git push
```
