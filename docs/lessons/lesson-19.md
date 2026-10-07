# Lesson 19: Float plans and background work

> **Draft.** This lesson was written ahead of time and has not yet been run against your project. Before you start it, tell me and I will check every step against your code as it stands.

**Goal:** build the feature the whole project started from: knowing when someone hasn't come back. A skipper files a float plan, checks out and in, and the server notices on its own when a boat is overdue. Until now the API only acted when a request arrived. Today it acts by itself, on a timer.

**Today's C#:** `BackgroundService`, timers, and creating a scope by hand.

- [ ] Exercise 1: The float plan
- [ ] Exercise 2: File, depart, return
- [ ] Exercise 3: Notifications
- [ ] Exercise 4: The escalation logic
- [ ] Exercise 5: The background monitor
- [ ] Exercise 6: Test the escalation
- [ ] Exercise 7: Break it on purpose
- [ ] Notes, README, commit

## The state machine

```
Filed ──► Underway ──► Returned
              │            ▲
              └─► Overdue ─┘
```

The escalation, from FR-S4 and FR-S5:

| When | What happens |
|---|---|
| Expected return time passes with no check-in | Status becomes `Overdue` |
| 30 minutes after that | The shore contact is notified |
| 60 minutes after that | The club's safety officers are notified |

## Exercise 1: The float plan

**`Domain/FloatPlanStatus.cs`**: an enum with `Filed`, `Underway`, `Overdue`, `Returned`.

**`Domain/FloatPlan.cs`**

```csharp
namespace DrunkenSailor.Api.Domain;

public class FloatPlan
{
    public int Id { get; init; }

    public int ReservationId { get; set; }
    public Reservation Reservation { get; set; } = null!;

    public required string Route { get; set; }
    public int PeopleAboard { get; set; }
    public DateTime ExpectedReturnUtc { get; set; }

    public required string ShoreContactName { get; set; }
    public required string ShoreContactPhone { get; set; }

    public FloatPlanStatus Status { get; private set; }
    public DateTime? DepartedUtc { get; private set; }
    public DateTime? ReturnedUtc { get; private set; }
    public DateTime? ShoreContactNotifiedUtc { get; private set; }
    public DateTime? SafetyOfficerNotifiedUtc { get; private set; }

    public void Depart(DateTime nowUtc)
    {
        if (Status != FloatPlanStatus.Filed)
            throw new DomainException($"Only a filed float plan can depart. This one is {Status}.");

        Status = FloatPlanStatus.Underway;
        DepartedUtc = nowUtc;
    }

    public void MarkOverdue()
    {
        if (Status != FloatPlanStatus.Underway)
            throw new DomainException($"Only a float plan that is underway can become overdue. This one is {Status}.");

        Status = FloatPlanStatus.Overdue;
    }

    public void Return(DateTime nowUtc)
    {
        if (Status != FloatPlanStatus.Underway && Status != FloatPlanStatus.Overdue)
            throw new DomainException($"A float plan that is {Status} can't be marked returned.");

        Status = FloatPlanStatus.Returned;
        ReturnedUtc = nowUtc;
    }

    public void RecordShoreContactNotified(DateTime nowUtc)
    {
        ShoreContactNotifiedUtc = nowUtc;
    }

    public void RecordSafetyOfficerNotified(DateTime nowUtc)
    {
        SafetyOfficerNotifiedUtc = nowUtc;
    }
}
```

The methods take the current time as a parameter and never read the clock themselves. That's the Lesson 15 idea again, and it's what makes Exercise 6 possible.

Add the `DbSet`, a configuration (status as a string, one float plan per reservation via a unique index on `ReservationId`), and a migration.

## Exercise 2: File, depart, return

Add these endpoints:

| Request | Who | Effect |
|---|---|---|
| `POST /reservations/{id}/float-plan` | The skipper | Files the plan. The reservation must be `Confirmed`. |
| `POST /float-plans/{id}/depart` | The skipper | `Depart(now)`, and the reservation's `Start()` |
| `POST /float-plans/{id}/return` | The skipper, or a safety officer | `Return(now)`, and the reservation's `Complete()` |
| `GET /float-plans/{id}` | The skipper, or a safety officer | One plan |
| `GET /clubs/{clubId}/float-plans?status=Overdue` | Safety officers | A club's plans, filterable |

Two rules to enforce:

- **FR-S1:** remove the standalone "start" endpoint from Lesson 13. A reservation now starts only by departing on a filed float plan.
- **POL-8:** a float plan is private. Members who aren't the skipper or a safety officer get a 403. Use the authorization pieces from Lesson 17.

Get the current time from the injected `TimeProvider`, as in Lesson 15.

## Exercise 3: Notifications

Real SMS and email are out of scope for v1, so define what "notify" means and provide a version that writes to the log.

**`Notifications/INotificationService.cs`**

```csharp
using DrunkenSailor.Api.Domain;

namespace DrunkenSailor.Api.Notifications;

public interface INotificationService
{
    Task NotifyShoreContactAsync(FloatPlan plan, CancellationToken cancellationToken);

    Task NotifySafetyOfficersAsync(FloatPlan plan, CancellationToken cancellationToken);
}
```

Write `LoggingNotificationService` yourself. Each method logs a warning that includes the boat, the route, and the expected return time. Register it as scoped. When real delivery is added later, it's one new class and one changed registration line.

## Exercise 4: The escalation logic

Put the decisions in an ordinary class, separate from the timer.

**`FloatPlans/FloatPlanEscalator.cs`**

```csharp
using DrunkenSailor.Api.Data;
using DrunkenSailor.Api.Domain;
using DrunkenSailor.Api.Notifications;
using Microsoft.EntityFrameworkCore;

namespace DrunkenSailor.Api.FloatPlans;

public class FloatPlanEscalator(
    AppDbContext db,
    INotificationService notifications,
    TimeProvider clock,
    ILogger<FloatPlanEscalator> logger)
{
    public static readonly TimeSpan ShoreContactDelay = TimeSpan.FromMinutes(30);
    public static readonly TimeSpan SafetyOfficerDelay = TimeSpan.FromMinutes(60);

    public async Task RunAsync(CancellationToken cancellationToken)
    {
        var now = clock.GetUtcNow().UtcDateTime;

        var plans = await db.FloatPlans
            .Include(p => p.Reservation).ThenInclude(r => r.Boat)
            .Where(p => p.Status == FloatPlanStatus.Underway || p.Status == FloatPlanStatus.Overdue)
            .Where(p => p.ExpectedReturnUtc < now)
            .ToListAsync(cancellationToken);

        foreach (var plan in plans)
        {
            if (plan.Status == FloatPlanStatus.Underway)
            {
                plan.MarkOverdue();
                logger.LogWarning("Float plan {FloatPlanId} is overdue", plan.Id);
            }

            var overdueFor = now - plan.ExpectedReturnUtc;

            if (overdueFor >= ShoreContactDelay && plan.ShoreContactNotifiedUtc is null)
            {
                await notifications.NotifyShoreContactAsync(plan, cancellationToken);
                plan.RecordShoreContactNotified(now);
            }

            if (overdueFor >= SafetyOfficerDelay && plan.SafetyOfficerNotifiedUtc is null)
            {
                await notifications.NotifySafetyOfficersAsync(plan, cancellationToken);
                plan.RecordSafetyOfficerNotified(now);
            }
        }

        await db.SaveChangesAsync(cancellationToken);
    }
}
```

The "notified" timestamps are what stop the same person being alerted every minute. Register the class as scoped.

## Exercise 5: The background monitor

**`FloatPlans/FloatPlanMonitor.cs`**

```csharp
namespace DrunkenSailor.Api.FloatPlans;

public class FloatPlanMonitor(
    IServiceScopeFactory scopeFactory,
    IConfiguration configuration,
    ILogger<FloatPlanMonitor> logger) : BackgroundService
{
    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        var seconds = configuration.GetValue("FloatPlans:CheckIntervalSeconds", 60);
        using var timer = new PeriodicTimer(TimeSpan.FromSeconds(seconds));

        logger.LogInformation("Float plan monitor started, checking every {Seconds} seconds", seconds);

        while (await timer.WaitForNextTickAsync(stoppingToken))
        {
            try
            {
                using var scope = scopeFactory.CreateScope();
                var escalator = scope.ServiceProvider.GetRequiredService<FloatPlanEscalator>();

                await escalator.RunAsync(stoppingToken);
            }
            catch (Exception ex) when (ex is not OperationCanceledException)
            {
                logger.LogError(ex, "The float plan check failed and will be retried on the next tick");
            }
        }
    }
}
```

```csharp
builder.Services.AddHostedService<FloatPlanMonitor>();
```

- **`BackgroundService`** starts with the app and runs until the app stops. `stoppingToken` is how the app asks it to finish.
- **The scope.** The monitor lives for the whole life of the app, so it's effectively a singleton. The database context is scoped and short-lived. A long-lived object can't hold a short-lived one, so each tick creates a scope, as the seeding code did in Lesson 9, uses it, and disposes of it.
- **The `try` / `catch`.** An unhandled exception would end the loop permanently, and overdue boats would go unnoticed with no error anywhere. One failed check is logged and the next tick tries again.

For development, set a short interval in `appsettings.Development.json`:

```json
"FloatPlans": { "CheckIntervalSeconds": 10 }
```

Try it: file a float plan with an expected return two minutes away, depart, and watch the server's terminal. To see the notifications without waiting an hour, temporarily shorten the two delays.

## Exercise 6: Test the escalation

The escalator needs a database, so it can't be a pure unit test like the policies. Write the tests you can today, on the `FloatPlan` class: departing, returning, returning when overdue, and each refused transition.

Then write down, in your notes, what a test of `FloatPlanEscalator` would need. You'll write it in Lesson 21, with a fake clock moved forward 31 minutes and then 61.

## Exercise 7: Break it on purpose

1. Add `AppDbContext db` directly to the `FloatPlanMonitor` constructor and start the app. Read the startup error, then remove it.
2. Remove the `try` / `catch` in the monitor, add `throw new Exception("boom");` inside the loop, and watch what happens after the first tick. Restore both.
3. Return an overdue boat, and confirm that no further notifications are logged.
4. As a plain member, request someone else's float plan.
5. Try to start a reservation that has no float plan.

---

## Deliverable

**Notes** (`docs/lesson-19.txt`):

1. What did the error in break-it 1 say? Explain it using the lifetime table from Lesson 8.
2. In break-it 2, what happened to the monitoring after the exception? Why is that failure especially dangerous in this app?
3. Why are the "notified" timestamps stored in the database and not kept in a variable in the monitor?
4. The server only checks once a minute. A boat could be overdue for 59 seconds before anyone knows. Is that acceptable here? When wouldn't it be?
5. If two copies of the API ran at once, both monitors would run. What could go wrong?

**README updates:**

- Section 4: the float plan state machine is implemented. Section 5: FR-S1 through FR-S6. Section 6: POL-8.

**Commit:**

```powershell
git add .
git commit -m "Lesson 19: float plans and overdue escalation"
git push
```
