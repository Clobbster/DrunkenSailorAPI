# Lesson 6: DTOs

**Goal:** stop exposing the `Boat` class directly. Callers get one shape for reading boats and other shapes for creating and updating them. After this lesson the server, not the caller, controls the id and anything internal.

**Today's C#:** records, `init`, extension methods, and LINQ's `Select`.

**Reminder:** press Ctrl+R in the `dotnet watch` terminal after changing routes or classes.

- [ ] Exercise 1: See the leak
- [ ] Exercise 2: A response shape
- [ ] Exercise 3: A request shape for creating
- [ ] Exercise 4: A request shape for updating
- [ ] Exercise 5: Break it on purpose
- [ ] Notes, README, commit

## The idea

Right now `Boat` does two jobs: it's the app's internal model, and it's the JSON the API sends and accepts. That ties them together. Add a field to `Boat` and it instantly appears in the API. Any field on `Boat` can also be set by any caller.

A **DTO** (data transfer object) is a small class whose only job is to describe JSON going in or out. With DTOs, the API's contract and the internal model can change separately.

| | Internal model | DTO |
|---|---|---|
| Example | `Boat` | `BoatResponse`, `CreateBoatRequest` |
| Who sees it | Only your code | Callers of the API |
| Changes when | The business changes | You decide to change the contract |

## Exercise 1: See the leak

Add an internal field to `Domain/Boat.cs`, and change `Id` from `set` to `init`:

```csharp
public int Id { get; init; }
public string? MaintenanceNotes { get; set; }
```

`init` means "can be set while creating the object, never after." An id shouldn't change.

Build. The `POST` route no longer compiles, because it assigns `boat.Id` after the boat exists. Leave it broken for a moment and add a note to "Knot Today" in the fleet in `Program.cs`:

```csharp
new Boat { Id = 3, Name = "Knot Today", Type = BoatType.Sailboat, LengthFt = 30, Capacity = 6, InService = false,
           MaintenanceNotes = "Cracked rudder. Waiting on the insurer." },
```

Comment out the `POST` route so the project builds, restart, and call `GET /boats/3`. The maintenance note, which is internal club business, is now visible to anyone. You never chose to publish it.

## Exercise 2: A response shape

Create a folder `src/DrunkenSailor.Api/Contracts/`.

**`Contracts/BoatResponse.cs`**

```csharp
using DrunkenSailor.Api.Domain;

namespace DrunkenSailor.Api.Contracts;

public record BoatResponse(
    int Id,
    string Name,
    BoatType Type,
    double LengthFt,
    int Capacity,
    bool InService);
```

A **record** is a compact way to write a class that only holds data. This one line creates six properties and a constructor that takes all six. Records are also immutable: once created, the values can't change. It's close to a Python `@dataclass(frozen=True)`.

**`Contracts/BoatMappings.cs`**

```csharp
using DrunkenSailor.Api.Domain;

namespace DrunkenSailor.Api.Contracts;

public static class BoatMappings
{
    public static BoatResponse ToResponse(this Boat boat)
    {
        return new BoatResponse(
            boat.Id,
            boat.Name,
            boat.Type,
            boat.LengthFt,
            boat.Capacity,
            boat.InService);
    }
}
```

The `this` in front of `Boat boat` makes it an **extension method**: you can call it as `boat.ToResponse()`, as if `Boat` had that method built in. `MaintenanceNotes` isn't copied, so it can't leak.

In `Program.cs`, add `using DrunkenSailor.Api.Contracts;` at the top, then change what the two `GET` routes return:

```csharp
// in GET /boats, the last line becomes:
return result.Select(b => b.ToResponse());

// in GET /boats/{id}:
: Results.Ok(boat.ToResponse());
```

**`Select`** is LINQ's "transform each item." It's `[f(b) for b in boats]` in Python and `.map(...)` in JavaScript. `Where` chooses which items to keep, and `Select` changes what each one looks like.

Restart and call `GET /boats/3`. The note is gone from the response, though it's still on the boat in memory.

## Exercise 3: A request shape for creating

**`Contracts/CreateBoatRequest.cs`**

```csharp
using DrunkenSailor.Api.Domain;

namespace DrunkenSailor.Api.Contracts;

public record CreateBoatRequest(
    string Name,
    BoatType Type,
    double LengthFt,
    int Capacity);
```

There's no `Id` (the server chooses it), no `InService` (new boats start in service), and no `MaintenanceNotes`. A caller can't set what the shape doesn't contain.

Replace the `POST` route:

```csharp
app.MapPost("/boats", (CreateBoatRequest request) =>
{
    var boat = new Boat
    {
        Id = nextId++,
        Name = request.Name,
        Type = request.Type,
        LengthFt = request.LengthFt,
        Capacity = request.Capacity,
        InService = true
    };
    boats.Add(boat);

    return Results.Created($"/boats/{boat.Id}", boat.ToResponse());
});
```

`Id` is set inside the `{ ... }` while the boat is being created, which is what `init` allows.

## Exercise 4: A request shape for updating

**`Contracts/UpdateBoatRequest.cs`**

```csharp
using DrunkenSailor.Api.Domain;

namespace DrunkenSailor.Api.Contracts;

public record UpdateBoatRequest(
    string Name,
    BoatType Type,
    double LengthFt,
    int Capacity,
    bool InService);
```

Update the `PUT` route to take `UpdateBoatRequest request` in place of `Boat updated`, copy from `request`, and return `Results.Ok(boat.ToResponse())`.

Creating and updating have different shapes because they allow different things. That's common.

## Exercise 5: Break it on purpose

Send each with `requests.http`:

1. A `POST` with `"id": 999`, `"inService": false`, and `"maintenanceNotes": "hacked"` added to the body. Check what the new boat looks like.
2. A `POST` with the `"name"` line removed. Compare the result with what the same request did in Lesson 5.
3. A `POST` with a body of just `{}`.

Number 2 is a step backwards, and it's deliberate. Lesson 7 fixes it properly.

---

## Deliverable

**Notes** (`docs/lesson-06.txt`):

1. In Exercise 1, what appeared in the API that you never chose to publish? Why did it appear?
2. What happened to `id`, `inService`, and `maintenanceNotes` in break-it 1? Is silently ignoring extra fields a good choice, or should the API reject them?
3. What did break-it 2 return? In Lesson 5 the same request gave a 400. What changed?
4. Why are there separate request shapes for create and update, when they're nearly the same?
5. In your own words: what's the difference between `set`, `init`, and having no setter at all?

**README updates:**

- Section 12: add the `Contracts/` folder to the "Today" tree.

**Commit:**

```powershell
git add .
git commit -m "Lesson 6: separate API contracts from the Boat class"
git push
```
