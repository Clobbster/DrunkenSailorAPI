# Lesson 14: Policies and the violations response

> **Draft.** This lesson was written ahead of time and has not yet been run against your project. Before you start it, tell me and I will check every step against your code as it stands.

**Goal:** build the feature that makes this API more than a booking system. A reservation is checked against a set of club policies, and a refusal says exactly which ones failed and why. This is POL-1 and POL-6 from the README, and the 403 you reasoned about in Lesson 1.

**Today's C#:** writing your own interface, several classes that implement it, and injecting a collection of them.

- [ ] Exercise 1: Certifications
- [ ] Exercise 2: The policy contract
- [ ] Exercise 3: Two policies
- [ ] Exercise 4: The evaluator
- [ ] Exercise 5: Wire it into reservations
- [ ] Exercise 6: A dry run
- [ ] Exercise 7: Break it on purpose
- [ ] Notes, README, commit

## The design

Each policy answers one question about a proposed reservation: pass or fail, with a reason. They share nothing with each other. That's the situation interfaces exist for, as covered in the Lesson 4 takeaways: several different things that should be usable the same way.

```
                    ┌─ CertificationGate ─┐
ReservationContext ─┼─ FairUseRule ───────┼─► list of violations
                    └─ (more later) ──────┘
```

## Exercise 1: Certifications

**`Domain/CertType.cs`**

```csharp
namespace DrunkenSailor.Api.Domain;

public enum CertType
{
    DaySkipper,
    KeelboatSkipper,
    NightSailing
}
```

**`Domain/Certification.cs`**

```csharp
namespace DrunkenSailor.Api.Domain;

public class Certification
{
    public int Id { get; init; }
    public int MemberId { get; set; }
    public CertType Type { get; set; }
    public DateOnly GrantedOn { get; set; }
}
```

Add to `Member`:

```csharp
public List<Certification> Certifications { get; } = new();
```

Add to `Boat`:

```csharp
public CertType? RequiredCert { get; set; }
```

A boat with no `RequiredCert` can be taken out by any member.

Add a `DbSet<Certification>`, store `Type` and `RequiredCert` as strings in configuration, and update the seed data: "Paddle Faster" requires nothing, the small sailboats require `DaySkipper`, and "Knot Today" at 30 feet requires `KeelboatSkipper`. Give Ada both certifications, Ben `DaySkipper`, and Cy none. Create and apply a migration, dropping the database first if the seed needs to run again.

## Exercise 2: The policy contract

Create a `Policies/` folder.

**`Policies/ReservationContext.cs`**

```csharp
using DrunkenSailor.Api.Domain;

namespace DrunkenSailor.Api.Policies;

public record ReservationContext(
    Member Skipper,
    Boat Boat,
    DateTime StartUtc,
    DateTime EndUtc,
    int UpcomingReservationCount);
```

**`Policies/PolicyResult.cs`**

```csharp
namespace DrunkenSailor.Api.Policies;

public record PolicyResult(bool Passed, string? Detail)
{
    public static PolicyResult Pass()
    {
        return new PolicyResult(true, null);
    }

    public static PolicyResult Fail(string detail)
    {
        return new PolicyResult(false, detail);
    }
}
```

**`Policies/IReservationPolicy.cs`**

```csharp
namespace DrunkenSailor.Api.Policies;

public interface IReservationPolicy
{
    string Name { get; }

    PolicyResult Evaluate(ReservationContext context);
}
```

Two decisions here are worth understanding:

- **The context carries everything a policy needs.** A policy never touches the database. The caller gathers the facts first, and the policy only decides. That keeps policies simple and makes them easy to test in Lesson 15.
- **`static` methods** belong to the type, not to one object. `PolicyResult.Pass()` reads better than `new PolicyResult(true, null)`.

## Exercise 3: Two policies

**`Policies/CertificationGate.cs`**

```csharp
namespace DrunkenSailor.Api.Policies;

public class CertificationGate : IReservationPolicy
{
    public string Name => "certification_gate";

    public PolicyResult Evaluate(ReservationContext context)
    {
        var required = context.Boat.RequiredCert;

        if (required is null)
            return PolicyResult.Pass();

        var holdsIt = context.Skipper.Certifications.Any(c => c.Type == required);

        return holdsIt
            ? PolicyResult.Pass()
            : PolicyResult.Fail($"{context.Boat.Name} requires the {required} certification.");
    }
}
```

**`Policies/FairUseRule.cs`**

```csharp
namespace DrunkenSailor.Api.Policies;

public class FairUseRule : IReservationPolicy
{
    public const int MaxUpcoming = 2;

    public string Name => "fair_use";

    public PolicyResult Evaluate(ReservationContext context)
    {
        return context.UpcomingReservationCount >= MaxUpcoming
            ? PolicyResult.Fail($"You already hold {context.UpcomingReservationCount} upcoming reservations. The limit is {MaxUpcoming}.")
            : PolicyResult.Pass();
    }
}
```

`: IReservationPolicy` is each class's promise to provide `Name` and `Evaluate`. Delete one of them from a class and build, to see the compiler enforce it.

## Exercise 4: The evaluator

**`Policies/PolicyViolation.cs`**

```csharp
namespace DrunkenSailor.Api.Policies;

public record PolicyViolation(string Policy, string Detail);
```

**`Policies/PolicyEvaluator.cs`**

```csharp
namespace DrunkenSailor.Api.Policies;

public class PolicyEvaluator(IEnumerable<IReservationPolicy> policies)
{
    public List<PolicyViolation> Evaluate(ReservationContext context)
    {
        var violations = new List<PolicyViolation>();

        foreach (var policy in policies)
        {
            var result = policy.Evaluate(context);

            if (!result.Passed)
                violations.Add(new PolicyViolation(policy.Name, result.Detail!));
        }

        return violations;
    }
}
```

Register everything in phase one of `Program.cs`:

```csharp
builder.Services.AddScoped<IReservationPolicy, CertificationGate>();
builder.Services.AddScoped<IReservationPolicy, FairUseRule>();
builder.Services.AddScoped<PolicyEvaluator>();
```

The evaluator asks for `IEnumerable<IReservationPolicy>` and receives **every** class registered under that interface. It doesn't know their names or how many there are. Adding a third policy later means writing one class and one registration line, with no change to the evaluator or the controller.

It runs all the policies and collects every failure. A caller who fixes one problem shouldn't then discover a second one.

## Exercise 5: Wire it into reservations

In `ReservationsController`, add `PolicyEvaluator evaluator` to the constructor. In `Create`, after the existing checks and before saving:

```csharp
var skipper = await db.Members
    .Include(m => m.Certifications)
    .FirstAsync(m => m.Id == request.SkipperId);

var upcoming = await db.Reservations.CountAsync(r =>
    r.SkipperId == skipper.Id &&
    r.StartUtc > DateTime.UtcNow &&
    (r.Status == ReservationStatus.Requested || r.Status == ReservationStatus.Confirmed));

var context = new ReservationContext(skipper, boat, request.StartUtc, request.EndUtc, upcoming);
var violations = evaluator.Evaluate(context);

if (violations.Count > 0)
{
    return Problem(
        title: "Reservation not allowed",
        detail: "One or more club policies were not met.",
        statusCode: StatusCodes.Status403Forbidden,
        extensions: new Dictionary<string, object?> { ["violations"] = violations });
}
```

`extensions` adds your own fields to a Problem Details body. The response keeps its standard shape and gains a `violations` array, matching the example in section 6 of the README.

Try it: reserve "Knot Today" as Cy, after returning the boat to service.

## Exercise 6: A dry run

FR-F7 asks for a way to check a reservation without making one. Add `POST /reservations/evaluate`, taking the same request body, which returns `200` with:

```json
{ "allowed": false, "violations": [ ... ] }
```

Both endpoints need the same context-building code. Move it into a private method on the controller and call it from both.

## Exercise 7: Break it on purpose

1. As Cy, reserve "Wet Noodle" (needs `DaySkipper`).
2. As Ben, make two reservations, then a third.
3. As Cy, with two reservations already made on "Paddle Faster", try to reserve "Wet Noodle". Count the violations.
4. Comment out the `FairUseRule` registration line and repeat number 2.
5. Call the dry-run endpoint for a request that would fail, then check that no reservation was created.

---

## Deliverable

**Notes** (`docs/lesson-14.txt`):

1. Paste the response from break-it 3. How many violations, and why is it better to return all of them at once?
2. In break-it 4, you turned off a policy by removing one line. What did you *not* have to change?
3. Why don't the policies query the database themselves?
4. A double booking returns 409 and a policy failure returns 403. In your own words, what's the difference between those two situations?
5. The dry run returns 200 even when the answer is "not allowed." Why is that right?

**README updates:**

- Section 6: mark POL-1 and POL-6 as implemented. Section 5: FR-F3, FR-F4, and FR-F7.

**Commit:**

```powershell
git add .
git commit -m "Lesson 14: reservation policies with detailed violations"
git push
```
