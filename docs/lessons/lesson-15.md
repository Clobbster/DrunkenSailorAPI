# Lesson 15: Unit tests

> **Draft.** This lesson was written ahead of time and has not yet been run against your project. Before you start it, tell me and I will check every step against your code as it stands.

**Goal:** prove the rules work without starting the server or the database. You'll test the state machine from Lesson 13 and the policies from Lesson 14, and feel why they were designed the way they were.

**Today's C#:** xUnit, which is the C# counterpart of pytest. Also `[Fact]`, `[Theory]`, and controlling time in tests.

- [ ] Exercise 1: Create the test project
- [ ] Exercise 2: Test the state machine
- [ ] Exercise 3: Many cases, one test
- [ ] Exercise 4: Test the policies
- [ ] Exercise 5: Time as a dependency
- [ ] Exercise 6: Break it on purpose
- [ ] Notes, README, commit

## What a unit test is

A unit test creates some objects, calls one piece of logic, and checks the result. It runs in milliseconds and needs nothing outside the process: no server, no database, no network.

| pytest | xUnit |
|---|---|
| `def test_something():` | `[Fact] public void Something()` |
| `@pytest.mark.parametrize` | `[Theory]` with `[InlineData(...)]` |
| `assert x == y` | `Assert.Equal(y, x)` |
| `with pytest.raises(E):` | `Assert.Throws<E>(() => ...)` |
| `pytest` | `dotnet test` |

## Exercise 1: Create the test project

```powershell
dotnet new xunit -n DrunkenSailor.UnitTests -o tests/DrunkenSailor.UnitTests
dotnet sln add tests/DrunkenSailor.UnitTests/DrunkenSailor.UnitTests.csproj
dotnet add tests/DrunkenSailor.UnitTests reference src/DrunkenSailor.Api
dotnet test
```

Delete the sample `UnitTest1.cs`. The reference lets test code use your `Reservation`, `Boat`, and policy classes.

## Exercise 2: Test the state machine

Create **`tests/DrunkenSailor.UnitTests/ReservationTests.cs`**:

```csharp
using DrunkenSailor.Api.Domain;

namespace DrunkenSailor.UnitTests;

public class ReservationTests
{
    [Fact]
    public void A_new_reservation_is_requested()
    {
        var reservation = new Reservation();

        Assert.Equal(ReservationStatus.Requested, reservation.Status);
    }

    [Fact]
    public void Confirming_a_requested_reservation_makes_it_confirmed()
    {
        var reservation = new Reservation();

        reservation.Confirm();

        Assert.Equal(ReservationStatus.Confirmed, reservation.Status);
    }

    [Fact]
    public void Confirming_twice_is_refused()
    {
        var reservation = new Reservation();
        reservation.Confirm();

        Assert.Throws<DomainException>(() => reservation.Confirm());
    }

    [Fact]
    public void A_completed_reservation_cannot_be_cancelled()
    {
        var reservation = new Reservation();
        reservation.Confirm();
        reservation.Start();
        reservation.Complete();

        Assert.Throws<DomainException>(() => reservation.Cancel());
    }
}
```

Each test has three parts, usually called **arrange, act, assert**: set things up, do the one thing being tested, check the outcome. The blank lines mark the three parts.

Test names describe behavior in plain words. When one fails, the name alone should tell you what broke.

Run `dotnet test`. In VS Code, the Testing panel (the beaker icon) also lists them and lets you run or debug one at a time.

## Exercise 3: Many cases, one test

The same check with different inputs is a **theory**. This one verifies that `Start` is refused from every state except `Confirmed`:

```csharp
[Theory]
[InlineData(ReservationStatus.Requested)]
[InlineData(ReservationStatus.InProgress)]
[InlineData(ReservationStatus.Completed)]
[InlineData(ReservationStatus.Cancelled)]
public void Start_is_refused_unless_confirmed(ReservationStatus startingStatus)
{
    var reservation = ReservationIn(startingStatus);

    Assert.Throws<DomainException>(() => reservation.Start());
}

private static Reservation ReservationIn(ReservationStatus status)
{
    var reservation = new Reservation();

    switch (status)
    {
        case ReservationStatus.Confirmed:
            reservation.Confirm();
            break;
        case ReservationStatus.InProgress:
            reservation.Confirm();
            reservation.Start();
            break;
        case ReservationStatus.Completed:
            reservation.Confirm();
            reservation.Start();
            reservation.Complete();
            break;
        case ReservationStatus.Cancelled:
            reservation.Cancel();
            break;
    }

    return reservation;
}
```

The helper has to walk the reservation through real transitions, because `Status` has a private setter. The test can't cheat either, which is the protection from Lesson 13 doing its job.

Write the matching theories for `Confirm`, `Complete`, and `Cancel`.

## Exercise 4: Test the policies

Create **`PolicyTests.cs`**. Start with two small builders so each test stays short:

```csharp
using DrunkenSailor.Api.Domain;
using DrunkenSailor.Api.Policies;

namespace DrunkenSailor.UnitTests;

public class PolicyTests
{
    private static Member MemberWith(params CertType[] certs)
    {
        var member = new Member { Name = "Test Member", Email = "test@example.com" };

        foreach (var cert in certs)
            member.Certifications.Add(new Certification { Type = cert });

        return member;
    }

    private static Boat BoatRequiring(CertType? cert)
    {
        return new Boat { Name = "Test Boat", Type = BoatType.Sailboat, LengthFt = 24, Capacity = 4, RequiredCert = cert };
    }

    private static ReservationContext Context(Member skipper, Boat boat, int upcoming = 0)
    {
        var start = new DateTime(2026, 10, 10, 14, 0, 0, DateTimeKind.Utc);
        return new ReservationContext(skipper, boat, start, start.AddHours(4), upcoming);
    }

    [Fact]
    public void Certification_gate_passes_when_the_skipper_holds_the_cert()
    {
        var gate = new CertificationGate();
        var context = Context(MemberWith(CertType.DaySkipper), BoatRequiring(CertType.DaySkipper));

        var result = gate.Evaluate(context);

        Assert.True(result.Passed);
    }

    [Fact]
    public void Certification_gate_fails_and_names_the_missing_cert()
    {
        var gate = new CertificationGate();
        var context = Context(MemberWith(), BoatRequiring(CertType.KeelboatSkipper));

        var result = gate.Evaluate(context);

        Assert.False(result.Passed);
        Assert.Contains("KeelboatSkipper", result.Detail);
    }
}
```

`params CertType[] certs` lets a caller pass any number of values, as in `MemberWith(CertType.DaySkipper, CertType.NightSailing)`. `int upcoming = 0` is a parameter with a default.

Now write, on your own:

1. The gate passes for a boat with no required certification.
2. The gate fails when the skipper holds a *different* certification.
3. `FairUseRule` passes at 1 upcoming reservation and fails at 2. Use a theory.
4. `PolicyEvaluator` returns two violations when both policies fail, and an empty list when both pass. You create it with `new PolicyEvaluator(new IReservationPolicy[] { new CertificationGate(), new FairUseRule() })`.

No database and no web server were involved. That's possible because of the decision in Lesson 14 to hand each policy a context with the facts already gathered.

## Exercise 5: Time as a dependency

The controller calls `DateTime.UtcNow` to count upcoming reservations. Code that reads the clock directly can't be tested reliably: a test that passes today may fail next month.

.NET has a built-in answer, `TimeProvider`. Add a third policy that refuses reservations starting in the past.

**`Policies/NotInThePastRule.cs`**

```csharp
namespace DrunkenSailor.Api.Policies;

public class NotInThePastRule(TimeProvider clock) : IReservationPolicy
{
    public string Name => "not_in_the_past";

    public PolicyResult Evaluate(ReservationContext context)
    {
        var now = clock.GetUtcNow().UtcDateTime;

        return context.StartUtc < now
            ? PolicyResult.Fail("A reservation can't start in the past.")
            : PolicyResult.Pass();
    }
}
```

Register it and the real clock in `Program.cs`:

```csharp
builder.Services.AddSingleton(TimeProvider.System);
builder.Services.AddScoped<IReservationPolicy, NotInThePastRule>();
```

In the test project:

```powershell
dotnet add tests/DrunkenSailor.UnitTests package Microsoft.Extensions.TimeProvider.Testing
```

```csharp
using Microsoft.Extensions.Time.Testing;

[Fact]
public void A_reservation_starting_yesterday_is_refused()
{
    var clock = new FakeTimeProvider(new DateTimeOffset(2026, 10, 11, 12, 0, 0, TimeSpan.Zero));
    var rule = new NotInThePastRule(clock);
    var context = Context(MemberWith(), BoatRequiring(null));   // starts 2026-10-10

    var result = rule.Evaluate(context);

    Assert.False(result.Passed);
}
```

The test sets the clock to a fixed moment, so it gives the same answer forever. In the controller, replace `DateTime.UtcNow` with an injected `TimeProvider` as well.

## Exercise 6: Break it on purpose

1. In `FairUseRule`, change `>=` to `>`. Run the tests and read the failure output.
2. In `Reservation.Cancel`, remove the `Confirmed` half of the condition. Run the tests.
3. Change `MaxUpcoming` to 3. Decide whether the failing tests are wrong or the code is.
4. Run `dotnet test --logger "console;verbosity=detailed"` to see each test by name.

Restore each change afterwards.

---

## Deliverable

**Notes** (`docs/lesson-15.txt`):

1. How long did the full test run take? How long would it take to check the same rules by hand with `requests.http`?
2. Paste the failure message from break-it 1. What three things does it tell you?
3. In break-it 3, how did you decide whether the test or the code was wrong?
4. Why can't these tests reach `Status` directly, and why is that good?
5. The overlap check in the controller has no test yet. What makes it harder to test than a policy?

**README updates:**

- Section 13: add `dotnet test`.
- Section 12: add the `tests/` folder to the "Today" tree.

**Commit:**

```powershell
git add .
git commit -m "Lesson 15: unit tests for the state machine and policies"
git push
```
