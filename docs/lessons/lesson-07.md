# Lesson 7: Validation and consistent errors

**Goal:** reject bad input with a useful message, and give every error the API can produce the same shape. That shape is Problem Details, the format you saw from the weather service in Lesson 1.

**Today's C#:** attributes, `Any`, local functions, and asking the framework for a service (a logger).

- [ ] Exercise 1: Validate the request shapes
- [ ] Exercise 2: One error shape for your own 404s
- [ ] Exercise 3: One error shape for the framework's errors
- [ ] Exercise 4: A rule attributes can't express
- [ ] Exercise 5: A friendlier filter
- [ ] Exercise 6: Logging
- [ ] Exercise 7: Break it on purpose
- [ ] Notes, README, commit

## Where things stand

After Lesson 6, a `POST` with no name creates a boat called `null`, and `"capacity": -3` is accepted. The API's errors also come in several shapes: your `{"message": ...}` objects, plain text from the framework, and empty bodies.

## Exercise 1: Validate the request shapes

Add rules to **`Contracts/CreateBoatRequest.cs`**:

```csharp
using System.ComponentModel.DataAnnotations;
using DrunkenSailor.Api.Domain;

namespace DrunkenSailor.Api.Contracts;

public record CreateBoatRequest(
    [Required, StringLength(50, MinimumLength = 2)] string Name,
    BoatType Type,
    [Range(6, 80)] double LengthFt,
    [Range(1, 20)] int Capacity);
```

The parts in square brackets are **attributes**: labels attached to code that something else reads. They're the closest thing C# has to Python decorators. On their own they do nothing. Turn on the part of the framework that reads them, in phase one of `Program.cs`:

```csharp
builder.Services.AddValidation();
```

Add the same attributes to `UpdateBoatRequest`. Restart, then send a `POST` with no name and `"capacity": -3`. Read the whole response: status, `Content-Type`, and the `errors` object.

## Exercise 2: One error shape for your own 404s

Add this function in `Program.cs`, after the `boats` list:

```csharp
IResult BoatNotFound(int id)
{
    return Results.Problem(
        title: "Boat not found",
        detail: $"No boat has id {id}.",
        statusCode: StatusCodes.Status404NotFound);
}
```

`Results.Problem` builds a Problem Details response. `title:` and `detail:` are **named arguments**: you say which parameter each value is for, so the order doesn't matter and the call is easier to read.

Replace every `Results.NotFound(new { message = ... })` with `BoatNotFound(id)`. There are three: in `GET` one boat, `PUT`, and `DELETE`. The ternary in `GET` one boat becomes:

```csharp
return boat is null
    ? BoatNotFound(id)
    : Results.Ok(boat.ToResponse());
```

Call `GET /boats/999` and compare it with the validation error from Exercise 1. They now share `type`, `title`, and `status`.

## Exercise 3: One error shape for the framework's errors

Call these and look at the bodies: `GET /nope`, `POST /health`, `GET /boats/banana`. Some are empty and one is a page of plain text.

In phase one, add:

```csharp
builder.Services.AddProblemDetails();
builder.Services.Configure<RouteHandlerOptions>(options => options.ThrowOnBadRequest = false);
```

In phase two, immediately after `var app = builder.Build();`:

```csharp
app.UseExceptionHandler();
app.UseStatusCodePages();
```

- **`UseStatusCodePages`** fills in a Problem Details body whenever a response has an error status and no body.
- **`UseExceptionHandler`** catches any exception your code throws and turns it into a clean 500, without leaking a stack trace to the caller.
- **The `ThrowOnBadRequest` line** makes unreadable input (like `banana` for an id) return a 400 quietly. Without it, the framework throws an exception during development, and the exception handler would report it as a 500.

These two `Use...` lines are your first **middleware**: steps that every request and response passes through, in the order you list them. That's the "steps each request passes through" from your Lesson 3 notes.

Restart and call the three URLs again.

## Exercise 4: A rule attributes can't express

Two boats shouldn't share a name. An attribute can only look at the one request in front of it, so this check goes in the route. Add another helper:

```csharp
IResult NameTaken(string name)
{
    return Results.Problem(
        title: "Boat name already in use",
        detail: $"Another boat is already named '{name}'.",
        statusCode: StatusCodes.Status409Conflict);
}
```

At the start of the `POST` route:

```csharp
if (boats.Any(b => b.Name.Equals(request.Name, StringComparison.OrdinalIgnoreCase)))
    return NameTaken(request.Name);
```

**`Any`** is LINQ for "does at least one item pass this test?" It returns `true` or `false`.

In the `PUT` route, after the not-found check, the same rule has to skip the boat being updated:

```csharp
if (boats.Any(b => b.Id != id && b.Name.Equals(request.Name, StringComparison.OrdinalIgnoreCase)))
    return NameTaken(request.Name);
```

**409 Conflict** means the request is well formed but clashes with the current state. It's the last row of the status table from Lesson 1.

## Exercise 5: A friendlier filter

Replace the `GET /boats` route with a version that accepts any capitalization and explains itself when the type is wrong:

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
            return Results.ValidationProblem(new Dictionary<string, string[]>
            {
                ["type"] = [$"'{type}' is not a boat type. Use one of: {allowed}."]
            });
        }

        result = result.Where(b => b.Type == boatType);
    }

    if (inService is not null)
        result = result.Where(b => b.InService == inService);

    return Results.Ok(result.Select(b => b.ToResponse()));
});
```

`Results.ValidationProblem` produces the same `errors` shape as Exercise 1, so a caller handles both the same way.

## Exercise 6: Logging

Change the `DELETE` route to ask for a logger and use it:

```csharp
app.MapDelete("/boats/{id}", (int id, ILogger<Program> logger) =>
{
    var boat = boats.FirstOrDefault(b => b.Id == id);

    if (boat is null)
        return BoatNotFound(id);

    boats.Remove(boat);
    logger.LogInformation("Boat {BoatId} ({BoatName}) was deleted", boat.Id, boat.Name);

    return Results.NoContent();
});
```

`ILogger<Program>` isn't in the route and isn't in the query string or body. It's a **service**, something the app has, and the framework hands it to you because you asked for it by type. This is a fourth source for parameters, and it's the first step toward dependency injection in Lesson 8.

Delete a boat and find the message in the server's terminal.

## Exercise 7: Break it on purpose

1. Add `throw new InvalidOperationException("The bilge pump failed");` as the first line of the `GET /boats` route. Call it, and compare what the caller sees with what the server's terminal shows. Remove the line afterwards.
2. Comment out the `ThrowOnBadRequest` line, restart, and call `GET /boats/banana`. Note the status code, then restore the line.
3. Send a `PUT` to boat 2 with the name `"Wet Noodle"`.
4. Send a `PUT` to boat 2 with its own current name and a different capacity.

---

## Deliverable

**Notes** (`docs/lesson-07.txt`):

1. Paste the validation error body from Exercise 1. Which parts would a phone app use to show a message next to the right field?
2. Name three different errors the API can now produce and the status code for each. What do their bodies have in common?
3. Why does the unique-name rule live in the route and not in an attribute?
4. In break-it 1, what did the caller see, and what did the server log? Why is it right that they differ?
5. In break-it 2, `banana` turned into a 500. Using the "whose fault" table from Lesson 1, why is 500 the wrong answer for that request?
6. Where does the `logger` parameter come from?

**README updates:**

- Section 11: note that errors use Problem Details (`application/problem+json`), and add the 409 for duplicate names to the endpoints table.

**Commit:**

```powershell
git add .
git commit -m "Lesson 7: validation and consistent error responses"
git push
```
