# Lesson 4: One real resource

*Completed October 4, 2026.*

**Goal:** replace the placeholder `/boats/{id}` with real data: a first C# class, a fleet of boats in memory, and a proper 404 for a boat that doesn't exist.

**C# in this lesson:** classes and properties, enums, `required`, LINQ, and `Results`.

**Reminders:** press **Ctrl+R** in the `dotnet watch` terminal after adding or replacing a route. In PowerShell, put any URL containing `&` in quotes.

## Exercise 1: Your first class

Create `src/DrunkenSailor.Api/Domain/` with two files.

**`Domain/BoatType.cs`**

```csharp
namespace DrunkenSailor.Api.Domain;

public enum BoatType
{
    Sailboat,
    Motorboat,
    HumanPowered
}
```

**`Domain/Boat.cs`**

```csharp
namespace DrunkenSailor.Api.Domain;

public class Boat
{
    public int Id { get; set; }
    public string Name { get; set; }
    public BoatType Type { get; set; }
    public double LengthFt { get; set; }
    public int Capacity { get; set; }
    public bool InService { get; set; }
}
```

- **`namespace`** is like a Python module path. By convention it matches the folder.
- **`{ get; set; }`** makes a **property**: a value that can be read (`get`) and changed (`set`).
- **`enum`** is a fixed set of named values.

```powershell
dotnet build
```

**Warning CS8618** appears on `Name`: the type says "never null," but nothing stops someone creating a `Boat` without a name. Fix it:

```csharp
public required string Name { get; set; }
```

## Exercise 2: A fleet in memory

First line of `Program.cs`:

```csharp
using DrunkenSailor.Api.Domain;
```

Just after `var app = builder.Build();`:

```csharp
var boats = new List<Boat>
{
    new Boat { Id = 1, Name = "Wet Noodle",    Type = BoatType.Sailboat,     LengthFt = 24, Capacity = 4, InService = true },
    new Boat { Id = 2, Name = "Second Wind",   Type = BoatType.Sailboat,     LengthFt = 19, Capacity = 3, InService = true },
    new Boat { Id = 3, Name = "Knot Today",    Type = BoatType.Sailboat,     LengthFt = 30, Capacity = 6, InService = false },
    new Boat { Id = 4, Name = "Safety Dance",  Type = BoatType.Motorboat,    LengthFt = 16, Capacity = 4, InService = true },
    new Boat { Id = 5, Name = "Paddle Faster", Type = BoatType.HumanPowered, LengthFt = 12, Capacity = 1, InService = true }
};
```

**Break it:** delete `Name = "Wet Noodle",` and build. That's `required` doing its job.

## Exercise 3: List all boats

```csharp
app.MapGet("/boats", () => boats);
```

The lambda uses `boats` from the surrounding code, the way a JavaScript closure does. In the JSON:

1. The keys are `camelCase` even though the properties are `PascalCase`.
2. The value of `type` is a number. Exercise 5 fixes that.

## Exercise 4: Get one boat, or a 404

**Replace** the placeholder `/boats/{id}` line with:

```csharp
app.MapGet("/boats/{id}", (int id) =>
{
    var boat = boats.FirstOrDefault(b => b.Id == id);

    return boat is null
        ? Results.NotFound(new { message = $"Boat {id} not found" })
        : Results.Ok(boat);
});
```

- **`FirstOrDefault(b => b.Id == id)`** is **LINQ**. It returns the first match, or `null`.
- **`boat is null`** checks for null.
- **`condition ? a : b`** is the ternary.
- **`Results.NotFound(...)` and `Results.Ok(...)`** let you choose the status code.

```powershell
curl.exe -i http://localhost:5080/boats/2
curl.exe -i http://localhost:5080/boats/999
curl.exe -i http://localhost:5080/boats/banana
```

**Break it:** change `: Results.Ok(boat);` to `: boat;`. A C# function must return one type, and `Results.NotFound(...)` and a `Boat` are different types. Change it back.

## Exercise 5: Fix the enum, in phase one

Second `using` line:

```csharp
using System.Text.Json.Serialization;
```

**Between** `CreateBuilder` and `builder.Build()`:

```csharp
builder.Services.ConfigureHttpJsonOptions(options =>
    options.SerializerOptions.Converters.Add(new JsonStringEnumConverter()));
```

This configures something the app *has* (a JSON serializer) so every endpoint uses it.

## Exercise 6: Filter with LINQ

Replace the `/boats` line with:

```csharp
app.MapGet("/boats", (BoatType? type, bool? inService) =>
{
    IEnumerable<Boat> result = boats;

    if (type is not null)
        result = result.Where(b => b.Type == type);

    if (inService is not null)
        result = result.Where(b => b.InService == inService);

    return result;
});
```

- **`BoatType?` and `bool?`** are optional query parameters.
- **`.Where(...)`** is LINQ's filter.
- **`IEnumerable<Boat>`** means "any sequence of boats."

Try:

```
/boats?type=Sailboat
/boats?inService=false
/boats?type=Sailboat&inService=true
/boats?type=sailboat
/boats?type=banana
```

---

## Deliverable

Notes in `docs/lesson-04.txt`:

1. What did warning CS8618 say, and what mistake was the compiler protecting you from?
2. What does `FirstOrDefault` return when nothing matches? Why couldn't the lambda return a `Boat` on one branch and `Results.NotFound(...)` on the other?
3. How did `type` appear in the JSON before Exercise 5? Give one reason that's a bad contract.
4. Why did the JSON line go *before* `builder.Build()`?
5. What status did `/boats?type=banana` return, and what did `/boats?type=sailboat` do? What does `/boats?type=Motorboat&inService=false` return, and is that an error?

README: update sections 11, 12, and 13.

```powershell
git add .
git commit -m "Lesson 4: boats resource with list, get, filter, and 404"
git push
```

## Takeaways from the review

**Class and instances.** `Boat.cs` is the blueprint and contains no boats. The five boats exist because `new Boat { ... }` runs in `Program.cs` at startup. They live only in memory.

**Enums are numbers underneath.** The compiler numbers the names in the order written, starting at 0. The numbering is fixed at build time and has nothing to do with which boats exist.

| Where | What `Type` is |
|---|---|
| In C# code | `BoatType.Sailboat` |
| In memory | `0` |
| In JSON, default | `0` |
| In JSON, with the converter | `"Sailboat"` |

Numbers are a bad contract: a consumer can't tell what `0` means, and reordering the enum silently changes every number's meaning.

**`get` and `set`.** `get` means the value can be read, `set` means it can be changed. Variations: `{ get; }` is read-only, `{ get; init; }` can be set only while creating the object, `{ get; private set; }` can be changed only by the class itself.

**How a route finds its parameters.**

| Parameter | Comes from |
|---|---|
| Its name appears in the route, like `{id}` | The URL path |
| A simple type not in the route (`int`, `bool`, an enum) | The query string |
| A class, like `Boat` | The JSON body (Lesson 5) |

**The lookup, without lambdas:**

```csharp
IResult GetBoatById(int id)
{
    Boat? boat = null;
    foreach (var b in boats)
    {
        if (b.Id == id)
        {
            boat = b;
            break;
        }
    }

    if (boat is null)
    {
        return Results.NotFound(new { message = $"Boat {id} not found" });
    }
    else
    {
        return Results.Ok(boat);
    }
}

app.MapGet("/boats/{id}", GetBoatById);
```

**`Where` checks every item.** It never stops at the first non-match. Each `Where` builds a new, smaller sequence, and filters stack. The original `boats` list is never changed.

**An empty result isn't an error.** `/boats?type=Motorboat&inService=false` returns `200` with `[]`. A 404 is for a specific thing that doesn't exist.

**`IEnumerable<Boat>`** is an interface: "something you can loop over." A `List<Boat>` and the output of `Where` are different classes that both offer it, which is why one variable can hold either. `var result = boats;` would lock the variable to `List<Boat>` and fail on the next line.

**Class vs. interface.** A class defines a thing, including how you interact with it. An interface names one way of interacting, so that many different things can offer it. Write a class first, and add an interface when a second thing needs to be usable the same way.

**The `type` filter is case-sensitive**, so `sailboat` returns 400. An optional improvement that also gives a helpful message:

```csharp
app.MapGet("/boats", (string? type, bool? inService) =>
{
    IEnumerable<Boat> result = boats;

    if (type is not null)
    {
        if (!Enum.TryParse<BoatType>(type, ignoreCase: true, out var boatType)
            || !Enum.IsDefined(boatType))
        {
            var allowed = string.Join(", ", Enum.GetNames<BoatType>());
            return Results.BadRequest(new { message = $"'{type}' is not a boat type. Use one of: {allowed}" });
        }

        result = result.Where(b => b.Type == boatType);
    }

    if (inService is not null)
        result = result.Where(b => b.InService == inService);

    return Results.Ok(result);
});
```

**PowerShell tips.** `Invoke-RestMethod` is good for data but hides error bodies; `curl.exe -i` shows status, headers, and body. Pretty-print JSON with `(curl.exe -s <url> | ConvertFrom-Json) | ConvertTo-Json`.
