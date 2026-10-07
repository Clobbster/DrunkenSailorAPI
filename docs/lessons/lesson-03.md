# Lesson 3: The smallest possible API

*Completed October 2, 2026.*

**Goal:** create the first web project, understand every line of it, and call it. The result is a running server with four endpoints.

**C# in this lesson:** lambdas, anonymous objects, and nullable types (`string?`).

## Exercise 1: Create the solution and project

From the repo root:

```powershell
cd C:\dev\drunkensailorapi\DrunkenSailorAPI
dotnet new sln -n DrunkenSailorAPI
dotnet new web -n DrunkenSailor.Api -o src/DrunkenSailor.Api
dotnet sln add src/DrunkenSailor.Api/DrunkenSailor.Api.csproj
code .
```

`dotnet new web` is the **empty** web template. It creates, in `src/DrunkenSailor.Api/`:

| File | What it is |
|---|---|
| `DrunkenSailor.Api.csproj` | Like Lesson 2, except the first line says `Microsoft.NET.Sdk.Web` |
| `Program.cs` | The entire application: four lines |
| `appsettings.json` | Configuration, like a `.env` or `config.json` |
| `appsettings.Development.json` | Overrides that apply only on your machine |
| `Properties/launchSettings.json` | How `dotnet run` starts the app locally (port, environment) |

## Exercise 2: Read `Program.cs`

```csharp
var builder = WebApplication.CreateBuilder(args);
var app = builder.Build();

app.MapGet("/", () => "Hello World!");

app.Run();
```

| | C# | Express | FastAPI |
|---|---|---|---|
| Create app | `builder.Build()` | `express()` | `FastAPI()` |
| Add a route | `app.MapGet("/", () => "...")` | `app.get('/', (req, res) => ...)` | `@app.get("/")` |
| Start listening | `app.Run()` | `app.listen(3000)` | `uvicorn.run(app)` |

The **two phases**:

1. **Before `builder.Build()`**: register *what the app has*, such as a database connection, authentication, or your own services.
2. **After `builder.Build()`**: define *what the app does* with a request, meaning routes and the steps each request passes through.

`() => "Hello World!"` is a **lambda**, the same idea as a JavaScript arrow function: no arguments, returns a string.

## Exercise 3: Run it and call it

In `Properties/launchSettings.json`, in the `http` profile, set:

```json
"launchBrowser": false,
"applicationUrl": "http://localhost:5080",
```

```powershell
dotnet run --project src/DrunkenSailor.Api
```

When you see `Now listening on: http://localhost:5080`, open a **second** terminal:

```powershell
curl.exe -i http://localhost:5080/
```

Note the `Content-Type` and the `Server` header. Kestrel is the web server built into .NET. Stop the server with **Ctrl+C**.

## Exercise 4: Add three endpoints

Start in watch mode:

```powershell
dotnet watch --project src/DrunkenSailor.Api
```

Add these above `app.Run();`, one at a time. **After adding a route, press Ctrl+R in the watch terminal to restart.** If a new route returns 404, the server is still running the old code.

**a) Returning an object**

```csharp
app.MapGet("/health", () => new { status = "ok", time = DateTime.UtcNow });
```

`new { ... }` is an **anonymous object**, like a JavaScript object literal or a Python dict.

**b) A route parameter**

```csharp
app.MapGet("/boats/{id}", (int id) => $"You asked for boat {id}");
```

The `{id}` in the URL is matched to the lambda's `id` parameter by name, and converted to an `int`.

**c) An optional query parameter**

```csharp
app.MapGet("/greet", (string? name) => $"Ahoy, {name ?? "sailor"}!");
```

- **`string?`** means "a string, or null." Plain `string` means "never null."
- **`??`** means "use the left side unless it's null, then use the right."

Because `name` isn't in the route, .NET looks for it in the query string.

## Exercise 5: Break it on purpose

```powershell
# a) A route that doesn't exist
curl.exe -i http://localhost:5080/nope

# b) A boat id that isn't a number
curl.exe -i http://localhost:5080/boats/banana

# c) The wrong method
curl.exe -i -X POST http://localhost:5080/health

# d) Stop the server (Ctrl+C), then call it
curl.exe -i http://localhost:5080/
```

## Exercise 6: Save your requests

Create `src/DrunkenSailor.Api/requests.http`:

```http
@baseUrl = http://localhost:5080

### Root
GET {{baseUrl}}/

### Health
GET {{baseUrl}}/health

### One boat
GET {{baseUrl}}/boats/42

### Greeting
GET {{baseUrl}}/greet?name=Christian
```

With the REST Client extension, a "Send Request" link appears above each one.

---

## Deliverable

Notes in `docs/lesson-03.txt`:

1. What are the two phases of `Program.cs`? Which phase does "connect to the database" belong in, and which does "add a `/reservations` route" belong in?
2. What `Content-Type` did `/` return, and what did `/health` return? Why are they different when you never set either one?
3. What status did `/boats/banana` return? NWS returned 404 for `/points/banana`. Which choice is better, and why?
4. Compare the result of 5c with what NWS did in Lesson 1's Exercise 4d.
5. What happened in 5d? Why is there no status code?

README: rename `SailClub` to `DrunkenSailor`, and update sections 11, 12, and 13.

```powershell
git status
git add .
git commit -m "Lesson 3: first running API"
```

## Takeaways from the review

- **The framework chooses the `Content-Type` from what the lambda returns:** a `string` goes out as `text/plain`, an object is converted to JSON and goes out as `application/json`.
- **JSON has two building blocks:** objects `{ "key": value }` and arrays `[a, b, c]`.
- **Three different failures, three different answers:**

| Request | What's wrong | Status |
|---|---|---|
| `/nope` | No such route | 404 |
| `/boats/banana` | The route exists, but `banana` can't be a boat id | 400 |
| `/boats/999` | A valid id, but no boat has it | 404 |

- **A route constraint** changes the banana case to a 404: `"/boats/{id:int}"`.
- **A good 405** includes an `Allow` header saying which methods would work.
- **A connection error isn't an HTTP response.** HTTP runs on top of a TCP connection, and status codes only exist once a server answers. "The server returned an error" and "the server didn't answer" need different handling (NFR-7).
- **`MapGet` runs once, at startup. The lambda runs on every request.**
- **A missing `app.Run();`** means the program registers its routes, reaches the end of the file, and exits.
