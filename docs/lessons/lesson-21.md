# Lesson 21: Integration tests, API docs, and CI

> **Draft.** This lesson was written ahead of time and has not yet been run against your project. Before you start it, tell me and I will check every step against your code as it stands.

**Goal:** finish the project the way real ones are finished. Test the whole API from the outside, publish documentation that's generated from the code, and have every push built and tested automatically. With your DevOps background, the last part should be the most familiar thing in the course.

**Today's C#:** `WebApplicationFactory`, test fixtures, and replacing a service in tests.

- [ ] Exercise 1: Create the integration test project
- [ ] Exercise 2: A test server with a real database
- [ ] Exercise 3: Your first end-to-end tests
- [ ] Exercise 4: Fake the weather
- [ ] Exercise 5: Generated API documentation
- [ ] Exercise 6: Continuous integration
- [ ] Exercise 7: A container image (optional)
- [ ] Exercise 8: The final README pass
- [ ] Notes, commit

## Two kinds of test

| | Unit tests (Lesson 15) | Integration tests (today) |
|---|---|---|
| Test | One class | The whole API, through HTTP |
| Need | Nothing | A database |
| Speed | Milliseconds | Seconds |
| Catch | Wrong logic | Wrong wiring, wrong SQL, wrong status codes, missing authorization |

In your Lesson 15 notes you listed things unit tests couldn't reach: the overlap query, the float plan escalator, and whether a controller returns the right status. Those are today's targets.

## Exercise 1: Create the integration test project

```powershell
dotnet new xunit -n DrunkenSailor.IntegrationTests -o tests/DrunkenSailor.IntegrationTests
dotnet sln add tests/DrunkenSailor.IntegrationTests
dotnet add tests/DrunkenSailor.IntegrationTests reference src/DrunkenSailor.Api
dotnet add tests/DrunkenSailor.IntegrationTests package Microsoft.AspNetCore.Mvc.Testing
dotnet add tests/DrunkenSailor.IntegrationTests package Testcontainers.PostgreSql
```

Add this as the last line of `Program.cs`, so the test project can refer to the app's entry point:

```csharp
public partial class Program { }
```

## Exercise 2: A test server with a real database

**Testcontainers** starts a throwaway PostgreSQL container for the test run and removes it afterwards. The tests run against the same database engine as production, with no shared state between runs. Docker must be running.

**`tests/DrunkenSailor.IntegrationTests/ApiFactory.cs`**

```csharp
using DrunkenSailor.Application.Weather;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.AspNetCore.TestHost;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.DependencyInjection.Extensions;
using Testcontainers.PostgreSql;

namespace DrunkenSailor.IntegrationTests;

public class ApiFactory : WebApplicationFactory<Program>, IAsyncLifetime
{
    private readonly PostgreSqlContainer _database = new PostgreSqlBuilder()
        .WithImage("postgres:17")
        .Build();

    public FakeWeatherService Weather { get; } = new();

    public async Task InitializeAsync()
    {
        await _database.StartAsync();
    }

    public new async Task DisposeAsync()
    {
        await _database.DisposeAsync();
    }

    protected override void ConfigureWebHost(IWebHostBuilder builder)
    {
        builder.UseSetting("ConnectionStrings:DrunkenSailor", _database.GetConnectionString());
        builder.UseSetting("FloatPlans:CheckIntervalSeconds", "3600");

        builder.ConfigureTestServices(services =>
        {
            services.RemoveAll<IWeatherService>();
            services.AddSingleton<IWeatherService>(Weather);
        });
    }
}
```

- **`WebApplicationFactory<Program>`** runs your real app in memory, with all its middleware, controllers, and services. No port is opened.
- **`UseSetting`** overrides configuration. It's the fourth configuration source from the Lesson 12 table, and here it wins.
- **`ConfigureTestServices`** swaps the real weather service for a fake. This is the payoff of having `IWeatherService` as an interface.

Your app applies migrations at startup, so the empty container gets its schema automatically.

## Exercise 3: Your first end-to-end tests

**`tests/DrunkenSailor.IntegrationTests/BoatsTests.cs`**

```csharp
using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;

namespace DrunkenSailor.IntegrationTests;

public class BoatsTests(ApiFactory factory) : IClassFixture<ApiFactory>
{
    [Fact]
    public async Task Listing_boats_without_a_token_is_unauthorized()
    {
        var client = factory.CreateClient();

        var response = await client.GetAsync("/boats");

        Assert.Equal(HttpStatusCode.Unauthorized, response.StatusCode);
    }

    [Fact]
    public async Task A_logged_in_user_can_list_boats()
    {
        var client = await LoggedInClientAsync("lister@example.com");

        var response = await client.GetAsync("/boats");

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
    }

    private async Task<HttpClient> LoggedInClientAsync(string email)
    {
        var client = factory.CreateClient();
        var credentials = new { email, password = "Sailing123!" };

        await client.PostAsJsonAsync("/auth/register", credentials);
        var login = await client.PostAsJsonAsync("/auth/login", credentials);
        var body = await login.Content.ReadFromJsonAsync<LoginResponse>();

        client.DefaultRequestHeaders.Authorization =
            new AuthenticationHeaderValue("Bearer", body!.AccessToken);

        return client;
    }

    private record LoginResponse(string AccessToken);
}
```

**`IClassFixture<ApiFactory>`** shares one factory, and so one container, among all the tests in the class.

This is `requests.http` as code. Every request you clicked by hand through twenty lessons can become a test that runs in seconds.

Now write these yourself. Move `LoggedInClientAsync` into a shared helper first, since every test class will need it.

1. A plain member who tries to create a boat gets 403.
2. Two overlapping reservations: the second gets 409.
3. An uncertified member who reserves a boat gets 403, and the body's `violations` array names `certification_gate`.
4. Creating a boat with an empty name gets 400, and the `errors` object mentions `Name`.
5. Confirming a reservation twice gets 409.

Tests share one database, so use a different email in each test and don't assume the tables are empty.

## Exercise 4: Fake the weather

**`tests/DrunkenSailor.IntegrationTests/FakeWeatherService.cs`**

```csharp
using DrunkenSailor.Application.Weather;

namespace DrunkenSailor.IntegrationTests;

public class FakeWeatherService : IWeatherService
{
    public double WindKt { get; set; } = 8;
    public double? GustKt { get; set; } = 10;
    public bool Unavailable { get; set; }

    public Task<IReadOnlyList<HourlyForecast>?> GetHourlyForecastAsync(
        double latitude,
        double longitude,
        CancellationToken cancellationToken)
    {
        if (Unavailable)
            return Task.FromResult<IReadOnlyList<HourlyForecast>?>(null);

        var start = DateTime.UtcNow.Date;

        IReadOnlyList<HourlyForecast> hours = Enumerable.Range(0, 24 * 7)
            .Select(h => new HourlyForecast(start.AddHours(h), start.AddHours(h + 1), WindKt, GustKt, "Test weather"))
            .ToList();

        return Task.FromResult<IReadOnlyList<HourlyForecast>?>(hours);
    }
}
```

Write two tests: with `factory.Weather.GustKt = 22`, a Day Skipper's reservation is refused with a `condition_gate` violation. With `factory.Weather.Unavailable = true`, the reservation is refused and the violation says the forecast is unavailable. Reset the fake's values at the end of each test.

Then write the test you described in your Lesson 19 notes, for the float plan escalator, using a `FakeTimeProvider` registered through `ConfigureTestServices`.

## Exercise 5: Generated API documentation

```powershell
dotnet add src/DrunkenSailor.Api package Microsoft.AspNetCore.OpenApi
dotnet add src/DrunkenSailor.Api package Scalar.AspNetCore
```

Phase one:

```csharp
builder.Services.AddOpenApi();
```

Phase two:

```csharp
if (app.Environment.IsDevelopment())
{
    app.MapOpenApi();
    app.MapScalarApiReference();
}
```

Start the app and open `http://localhost:5080/scalar`. Every endpoint, request shape, and response shape is listed, generated from your controllers and DTOs. Open `/openapi/v1.json` to see the machine-readable version underneath, which other tools can turn into client code.

Improve what it shows by telling it which statuses each action can return:

```csharp
[HttpPost]
[ProducesResponseType<BoatResponse>(StatusCodes.Status201Created)]
[ProducesResponseType<ProblemDetails>(StatusCodes.Status400BadRequest)]
[ProducesResponseType<ProblemDetails>(StatusCodes.Status403Forbidden)]
[ProducesResponseType<ProblemDetails>(StatusCodes.Status409Conflict)]
public async Task<ActionResult<BoatResponse>> Create(CreateBoatRequest request)
```

Do this for the reservation endpoints as well. Documentation generated from code can't drift away from the code, which is the reason to prefer it over a hand-written endpoint table.

## Exercise 6: Continuous integration

Create **`.github/workflows/ci.yml`**:

```yaml
name: CI

on:
  push:
    branches: [main]
  pull_request:

jobs:
  build-and-test:
    runs-on: ubuntu-latest

    steps:
      - uses: actions/checkout@v4

      - uses: actions/setup-dotnet@v4
        with:
          global-json-file: global.json

      - name: Restore
        run: dotnet restore

      - name: Build
        run: dotnet build --no-restore --configuration Release

      - name: Test
        run: dotnet test --no-build --configuration Release --logger "trx" --results-directory test-results

      - name: Upload test results
        if: always()
        uses: actions/upload-artifact@v4
        with:
          name: test-results
          path: test-results
```

Three things from earlier lessons come together here:

- **`global-json-file`** makes CI use the SDK version you pinned in Lesson 2.
- **No database setup is needed.** GitHub's Linux runners have Docker, so Testcontainers starts PostgreSQL for the tests by itself.
- **No secrets are needed.** The tests override the connection string, so nothing sensitive goes into the workflow.

Push, open the Actions tab on GitHub, and watch the run. Then add a status badge to the top of the README.

## Exercise 7: A container image (optional)

Create a **`Dockerfile`** in the repo root. This is the two-image build mentioned in the Lesson 2 takeaways:

```dockerfile
FROM mcr.microsoft.com/dotnet/sdk:10.0 AS build
WORKDIR /source
COPY . .
RUN dotnet publish src/DrunkenSailor.Api -c Release -o /app

FROM mcr.microsoft.com/dotnet/aspnet:10.0
WORKDIR /app
COPY --from=build /app .
EXPOSE 8080
ENTRYPOINT ["dotnet", "DrunkenSailor.Api.dll"]
```

The first stage has the SDK and compiles. The second has only the runtime and receives the compiled output. After building, compare the sizes of the `sdk` and `aspnet` base images with `docker images`.

Add the API as a second service in `docker-compose.yml`, passing the connection string as the environment variable `ConnectionStrings__DrunkenSailor`, with `Host=db` in place of `Host=localhost`.

## Exercise 8: The final README pass

Go through the README once more, top to bottom:

1. **Status line:** it's no longer "being built step by step."
2. **Section 5:** mark each functional requirement as done, partly done, or not started. Be honest about the gaps: crew requests and incidents were never built.
3. **Section 11:** follow your own "Getting started" steps on a fresh clone in a new folder. Fix anything that doesn't work.
4. **Section 14:** answer the open questions you can now answer, and leave the rest.
5. Replace the hand-written endpoints table with a link to `/scalar`.

---

## Deliverable

**Notes** (`docs/lesson-21.txt`):

1. Which bug would an integration test catch that no unit test could? Give one real example from your own code.
2. The integration tests replaced the weather service and left the database real. Why treat those two dependencies differently?
3. How long does the CI run take? Which step is slowest, and what could speed it up?
4. Break a test on purpose, push to a branch, and open a pull request. What does GitHub show?
5. Look back at your Lesson 1 notes. Which answer would you write differently today?

**Commit:**

```powershell
git add .
git commit -m "Lesson 21: integration tests, API docs, and CI"
git push
```

## What you built

Starting from an empty folder: a layered .NET API with a relational database, migrations, authentication, scoped authorization, a rule engine that explains its refusals, an external weather integration that fails safely, a background monitor, two levels of automated tests, generated documentation, and a pipeline that checks every change.

What's left in the README for a version 2: crew requests, incident reports, fleet closures, the daylight and cold-water policies, wave height in the condition gate, and real notification delivery. Each one follows a pattern you've now used at least once.
