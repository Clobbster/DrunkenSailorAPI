# Lesson 8: Controllers and your first service

> **Draft.** This lesson was written ahead of time and has not yet been run against your project. Before you start it, tell me and I will check every step against your code as it stands.

**Goal:** `Program.cs` now holds configuration, data, helper functions, and seven routes. Move the boat endpoints into a **controller** class and the fleet into a **service**, and let the framework connect them. This is dependency injection, the idea most of ASP.NET Core is built around.

**Today's C#:** constructors, primary constructors, attributes on methods, and service lifetimes.

- [ ] Exercise 1: Move the fleet into a service
- [ ] Exercise 2: Register it
- [ ] Exercise 3: Write the controller
- [ ] Exercise 4: Switch over
- [ ] Exercise 5: Break it on purpose
- [ ] Notes, README, commit

## Two styles

| | Minimal API (what you have) | Controllers |
|---|---|---|
| A route is | A lambda passed to `MapGet` | A method on a class |
| Routes are grouped by | Wherever you put them | One class per resource |
| The URL and method come from | The `MapGet("/boats", ...)` call | Attributes like `[HttpGet]` |
| Good for | Small APIs, quick starts | Larger APIs with many resources |

Neither is more correct. The README's target design uses controllers, and by the end the API has about nine resources, so the switch happens now while there's only one.

## The problem that forces a service

The lambdas could use `boats` because they were written in the same file, below the variable. A controller is a separate class in a separate file, so it can't see a variable inside `Program.cs`. Something has to hold the fleet and hand it to whoever needs it.

## Exercise 1: Move the fleet into a service

Create **`Services/BoatStore.cs`**:

```csharp
using DrunkenSailor.Api.Domain;

namespace DrunkenSailor.Api.Services;

public class BoatStore
{
    private int _nextId = 6;

    public List<Boat> Boats { get; } = new List<Boat>
    {
        new Boat { Id = 1, Name = "Wet Noodle",    Type = BoatType.Sailboat,     LengthFt = 24, Capacity = 4, InService = true },
        new Boat { Id = 2, Name = "Second Wind",   Type = BoatType.Sailboat,     LengthFt = 19, Capacity = 3, InService = true },
        new Boat { Id = 3, Name = "Knot Today",    Type = BoatType.Sailboat,     LengthFt = 30, Capacity = 6, InService = false,
                   MaintenanceNotes = "Cracked rudder. Waiting on the insurer." },
        new Boat { Id = 4, Name = "Safety Dance",  Type = BoatType.Motorboat,    LengthFt = 16, Capacity = 4, InService = true },
        new Boat { Id = 5, Name = "Paddle Faster", Type = BoatType.HumanPowered, LengthFt = 12, Capacity = 1, InService = true }
    };

    public int NextId()
    {
        return _nextId++;
    }
}
```

- **`private int _nextId`** is a **field**: data that belongs to the object and that only the class itself can touch. The leading underscore is the usual naming convention.
- **`{ get; }`** with no setter means the list itself can't be swapped for another list, though boats can still be added to it and removed.

## Exercise 2: Register it

In phase one of `Program.cs`:

```csharp
builder.Services.AddSingleton<BoatStore>();
```

This tells the framework: "the app has a `BoatStore`. Create one, and give that same one to anything that asks." The three lifetimes:

| Registration | How many are created |
|---|---|
| `AddSingleton` | One for the whole app |
| `AddScoped` | One per request |
| `AddTransient` | A new one every time something asks |

The fleet must outlive any single request, so it's a singleton.

## Exercise 3: Write the controller

Create **`Controllers/BoatsController.cs`**:

```csharp
using DrunkenSailor.Api.Contracts;
using DrunkenSailor.Api.Domain;
using DrunkenSailor.Api.Services;
using Microsoft.AspNetCore.Mvc;

namespace DrunkenSailor.Api.Controllers;

[ApiController]
[Route("boats")]
public class BoatsController(BoatStore store, ILogger<BoatsController> logger) : ControllerBase
{
    [HttpGet]
    public ActionResult<IEnumerable<BoatResponse>> GetAll(BoatType? type, bool? inService)
    {
        IEnumerable<Boat> result = store.Boats;

        if (type is not null)
            result = result.Where(b => b.Type == type);

        if (inService is not null)
            result = result.Where(b => b.InService == inService);

        return Ok(result.Select(b => b.ToResponse()));
    }

    [HttpGet("{id:int}")]
    public ActionResult<BoatResponse> GetById(int id)
    {
        var boat = store.Boats.FirstOrDefault(b => b.Id == id);

        if (boat is null)
            return BoatNotFound(id);

        return Ok(boat.ToResponse());
    }

    [HttpPost]
    public ActionResult<BoatResponse> Create(CreateBoatRequest request)
    {
        if (store.Boats.Any(b => b.Name.Equals(request.Name, StringComparison.OrdinalIgnoreCase)))
            return NameTaken(request.Name);

        var boat = new Boat
        {
            Id = store.NextId(),
            Name = request.Name,
            Type = request.Type,
            LengthFt = request.LengthFt,
            Capacity = request.Capacity,
            InService = true
        };
        store.Boats.Add(boat);

        return CreatedAtAction(nameof(GetById), new { id = boat.Id }, boat.ToResponse());
    }

    [HttpPut("{id:int}")]
    public ActionResult<BoatResponse> Update(int id, UpdateBoatRequest request)
    {
        var boat = store.Boats.FirstOrDefault(b => b.Id == id);

        if (boat is null)
            return BoatNotFound(id);

        if (store.Boats.Any(b => b.Id != id && b.Name.Equals(request.Name, StringComparison.OrdinalIgnoreCase)))
            return NameTaken(request.Name);

        boat.Name = request.Name;
        boat.Type = request.Type;
        boat.LengthFt = request.LengthFt;
        boat.Capacity = request.Capacity;
        boat.InService = request.InService;

        return Ok(boat.ToResponse());
    }

    [HttpDelete("{id:int}")]
    public IActionResult Delete(int id)
    {
        var boat = store.Boats.FirstOrDefault(b => b.Id == id);

        if (boat is null)
            return BoatNotFound(id);

        store.Boats.Remove(boat);
        logger.LogInformation("Boat {BoatId} ({BoatName}) was deleted", boat.Id, boat.Name);

        return NoContent();
    }

    private ObjectResult BoatNotFound(int id)
    {
        return Problem(
            title: "Boat not found",
            detail: $"No boat has id {id}.",
            statusCode: StatusCodes.Status404NotFound);
    }

    private ObjectResult NameTaken(string name)
    {
        return Problem(
            title: "Boat name already in use",
            detail: $"Another boat is already named '{name}'.",
            statusCode: StatusCodes.Status409Conflict);
    }
}
```

What's new:

- **`BoatsController(BoatStore store, ILogger<BoatsController> logger)`** is a **primary constructor**. It lists what the class needs in order to exist. The framework reads that list, finds each item among the registered services, and passes them in. You never write `new BoatsController(...)` yourself. That's **dependency injection**: a class declares what it depends on, and something else supplies it.
- **`: ControllerBase`** means the class inherits from a framework class that provides `Ok(...)`, `NoContent()`, `Problem(...)` and the rest. These replace `Results.Ok(...)`.
- **`[Route("boats")]`** sets the URL prefix for the class. **`[HttpGet("{id:int}")]`** adds to it, so that method answers `GET /boats/{id}`.
- **`[ApiController]`** turns on automatic behavior: request shapes are validated from their attributes, bad input returns a 400 with Problem Details, and class parameters are read from the JSON body.
- **`ActionResult<BoatResponse>`** is the "one return type" again: a method can return a `BoatResponse` or any error result.
- **`CreatedAtAction(nameof(GetById), ...)`** builds the `Location` header from the `GetById` route, so the URL isn't typed twice.

## Exercise 4: Switch over

In `Program.cs`:

1. Delete the `boats` list, `nextId`, the two helper functions, and all five `/boats` routes. Delete `/` and `/greet` too. Keep `/health`.
2. Delete `builder.Services.AddValidation();` and the `RouteHandlerOptions` line. `[ApiController]` now does both jobs for controllers.
3. Add to phase one:

```csharp
builder.Services.AddControllers()
    .AddJsonOptions(options =>
        options.JsonSerializerOptions.Converters.Add(new JsonStringEnumConverter()));
```

4. Add to phase two, before `app.Run();`:

```csharp
app.MapControllers();
```

Restart and run every request in `requests.http`. They should all behave as before.

`Program.cs` should now be about twenty lines, and all of it configuration.

## Exercise 5: Break it on purpose

1. Comment out `builder.Services.AddSingleton<BoatStore>();`, restart, and call `GET /boats`. Read the error in the server's terminal.
2. Restore it, but change `AddSingleton` to `AddScoped`. Send a `POST`, then `GET /boats`. Look for your new boat.
3. Change it to `AddTransient` and repeat. Then put it back to `AddSingleton`.
4. Remove the `.AddJsonOptions(...)` part and call `GET /boats`. Look at `type`.
5. Call `GET /boats?type=sailboat` (lowercase), which the controller handles with the plain `BoatType?` parameter.

---

## Deliverable

**Notes** (`docs/lesson-08.txt`):

1. In your own words, what is dependency injection? Who creates the `BoatsController`, and who creates the `BoatStore`?
2. What happened to your new boat under `AddScoped`, and why?
3. You configured the enum converter in Lesson 4, yet break-it 4 brought the numbers back. What does that tell you about minimal APIs and controllers?
4. What does `[ApiController]` do that you previously had to set up yourself?
5. Compare `Program.cs` before and after. What kind of code is left in it?

**README updates:**

- Section 9: the web framework row already says "controllers." Section 12: add `Controllers/` and `Services/` to the "Today" tree.

**Commit:**

```powershell
git add .
git commit -m "Lesson 8: move boats to a controller and a service"
git push
```
