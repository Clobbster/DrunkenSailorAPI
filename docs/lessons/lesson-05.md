# Lesson 5: Changing data

**Goal:** let callers add, replace, and delete boats. You'll use the three remaining HTTP methods and choose a status code for each outcome. This is an unprotected first version of FR-F1 in the README ("add, edit, and retire boats"). Anyone can do it for now; Lesson 17 restricts it to Club Admins.

**Today's C#:** reading a JSON body into an object, changing properties (`set` in action), and early returns.

- [ ] Before you start
- [ ] Exercise 1: POST
- [ ] Exercise 2: PUT
- [ ] Exercise 3: DELETE
- [ ] Exercise 4: Break it on purpose
- [ ] Exercise 5: Send it twice
- [ ] Exercise 6: Restart
- [ ] Exercise 7: Your first 500
- [ ] Notes, README, commit

## Before you start: use `requests.http` today

Sending JSON from PowerShell means fighting with quote characters, so this lesson uses `src/DrunkenSailor.Api/requests.http`. It shows the status line, the headers, and formatted JSON in one panel.

The file still has the Lesson 3 requests. Replace the "One boat" entry and add the Lesson 4 ones:

```http
### All boats
GET {{baseUrl}}/boats

### Sailboats in service
GET {{baseUrl}}/boats?type=Sailboat&inService=true

### One boat
GET {{baseUrl}}/boats/2
```

## The plan

| Action | Request | Success | Failure |
|---|---|---|---|
| Add a boat | `POST /boats` + JSON body | `201 Created` + `Location` header | `400` bad body |
| Replace a boat | `PUT /boats/{id}` + JSON body | `200 OK` + the boat | `404`, `400` |
| Delete a boat | `DELETE /boats/{id}` | `204 No Content` | `404` |

## Exercise 1: POST, add a boat

In `Program.cs`, add this line right after the `boats` list:

```csharp
var nextId = 6;
```

Then add the route, above `app.Run();`:

```csharp
app.MapPost("/boats", (Boat boat) =>
{
    boat.Id = nextId++;
    boats.Add(boat);

    return Results.Created($"/boats/{boat.Id}", boat);
});
```

- **`(Boat boat)`** completes the parameter rule. A parameter whose name is in the route comes from the URL. A simple type like `int` or `bool` comes from the query string. A **class**, like `Boat`, is read from the **JSON body**. The framework builds the object for you.
- **`nextId++`** uses the current value, then adds one. The server chooses the id, not the caller.
- **`Results.Created(url, boat)`** sends `201` and a `Location` header saying where the new boat lives.

Restart (Ctrl+R), then add to `requests.http`:

```http
### Add a boat
POST {{baseUrl}}/boats
Content-Type: application/json

{
  "name": "Sea You Later",
  "type": "Sailboat",
  "lengthFt": 22,
  "capacity": 4,
  "inService": true
}
```

The blank line between the header and the body is required. Send it, look at the status and the `Location` header, then call `GET /boats` to see six boats.

## Exercise 2: PUT, replace a boat

```csharp
app.MapPut("/boats/{id}", (int id, Boat updated) =>
{
    var boat = boats.FirstOrDefault(b => b.Id == id);

    if (boat is null)
        return Results.NotFound(new { message = $"Boat {id} not found" });

    boat.Name = updated.Name;
    boat.Type = updated.Type;
    boat.LengthFt = updated.LengthFt;
    boat.Capacity = updated.Capacity;
    boat.InService = updated.InService;

    return Results.Ok(boat);
});
```

- **Two parameters, two sources:** `id` from the URL, `updated` from the body.
- **The early return:** if the boat is missing, the function ends at that line. This reads more easily than the `? :` form once a function has more steps.
- **`boat.Name = updated.Name;`** is `set` doing its job. Each line reads a value from one object (`get`) and writes it to another (`set`). `Id` is deliberately not copied: the URL decides which boat, and its id never changes.

Take "Knot Today" out of the repair yard:

```http
### Replace boat 3
PUT {{baseUrl}}/boats/3
Content-Type: application/json

{
  "name": "Knot Today",
  "type": "Sailboat",
  "lengthFt": 30,
  "capacity": 6,
  "inService": true
}
```

`PUT` means "replace the whole thing," so you send every field, including the ones that aren't changing.

## Exercise 3: DELETE, remove a boat

```csharp
app.MapDelete("/boats/{id}", (int id) =>
{
    var boat = boats.FirstOrDefault(b => b.Id == id);

    if (boat is null)
        return Results.NotFound(new { message = $"Boat {id} not found" });

    boats.Remove(boat);

    return Results.NoContent();
});
```

`204 No Content` means "it worked, and there's nothing to send back."

```http
### Delete boat 5
DELETE {{baseUrl}}/boats/5
```

If lambdas still feel cramped, write any of these three as a named function and pass the name to `MapPost`, `MapPut`, or `MapDelete`. Both forms behave the same.

## Exercise 4: Break it on purpose

Send each of these and note the status code:

1. A `POST` with the `"name"` line removed.
2. A `POST` with `"type": "Submarine"`.
3. A `POST` with the `Content-Type: application/json` line removed.
4. A `POST` with `"id": 999` added to the body. What id does the new boat get?
5. A `POST` with `"capacity": -3`.
6. `PUT /boats/999`.
7. The same `DELETE` twice in a row.

## Exercise 5: Send it twice

1. Send the "Add a boat" `POST` twice. Call `GET /boats`.
2. Send the "Replace boat 3" `PUT` twice. Call `GET /boats`.

Compare what repeating each one did to the fleet. Imagine a phone app on a bad connection that isn't sure its request arrived, and think about which of the two it could safely send again.

## Exercise 6: Restart

Restart the server and call `GET /boats`. Look for the boats you added, changed, and deleted.

## Exercise 7: Your first 500

Temporarily change the id line in the `POST` to:

```csharp
boat.Id = boats.Max(b => b.Id) + 1;
```

`Max` finds the highest id in the fleet. Restart, **delete all five boats**, then send the `POST`. Read the response, and then read the server's terminal. Change the line back to `nextId++` when you're done.

---

## Deliverable

**Notes** (`docs/lesson-05.txt`):

1. What did the `Location` header contain after the `POST`? How does it relate to what NWS did with the `forecast` URL in Lesson 1?
2. In break-it 4, what id did the boat get, and why should the server choose it? Name one other `Boat` field a caller probably shouldn't be allowed to set freely.
3. From Exercise 5: what happened to the fleet when you repeated the `POST`, and when you repeated the `PUT`? Which is safe to retry?
4. What status codes did break-its 1, 3, and 7 return? For 7, the second `DELETE` gave a different answer from the first. Is that reasonable?
5. What happened with `"capacity": -3`? What should happen?
6. What caused the 500 in Exercise 7? Using the table from Lesson 1, whose fault is a 5xx, and how does that differ from every other error you produced today?

**README updates:**

- Section 11: add the three new endpoints to the table, and say that changes are lost when the server restarts.

**Commit:**

```powershell
git add .
git commit -m "Lesson 5: add, replace, and delete boats"
git push
```
