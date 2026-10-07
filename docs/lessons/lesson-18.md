# Lesson 18: The weather and the condition gate

> **Draft.** This lesson was written ahead of time and has not yet been run against your project. Before you start it, tell me and I will check every step against your code as it stands.

**Goal:** your API becomes a client of another API. It fetches the wind forecast from the National Weather Service, the service you explored by hand in Lesson 1, and refuses a reservation when the forecast exceeds what the skipper is certified for. This is POL-2 in the README.

**Today's C#:** `HttpClient`, reading JSON into your own types, caching, and handling a dependency that fails.

- [ ] Exercise 1: Where is the club?
- [ ] Exercise 2: The service contract
- [ ] Exercise 3: Call the weather service
- [ ] Exercise 4: Cache the answer
- [ ] Exercise 5: The condition gate
- [ ] Exercise 6: A conditions endpoint
- [ ] Exercise 7: Test it with made-up weather
- [ ] Exercise 8: Break it on purpose
- [ ] Notes, README, commit

## Before you start

Run these again from Lesson 1 and keep the output open. You're about to write C# that reads this JSON:

```powershell
$headers = @{ "User-Agent" = "DrunkenSailorAPI-learning (you@example.com)" }
$point = Invoke-RestMethod -Uri "https://api.weather.gov/points/43.0631,-86.2284" -Headers $headers
$point.properties.forecastHourly
$hourly = Invoke-RestMethod -Uri $point.properties.forecastHourly -Headers $headers
$hourly.properties.periods | Select-Object -First 3 | ConvertTo-Json
```

Note the exact field names for the start time, the wind speed, and any gust value, and what a wind speed looks like. The lesson assumes `startTime`, `endTime`, `windSpeed` (text such as `"10 mph"`), `windGust` (text or null), and `shortForecast`. If yours differ, tell me before writing the code.

## Exercise 1: Where is the club?

Add to `Club`:

```csharp
public double Latitude { get; set; }
public double Longitude { get; set; }
```

Set the seeded club to Grand Haven (`43.0631`, `-86.2284`) and migrate.

## Exercise 2: The service contract

Create a `Weather/` folder.

**`Weather/HourlyForecast.cs`**

```csharp
namespace DrunkenSailor.Api.Weather;

public record HourlyForecast(
    DateTime StartUtc,
    DateTime EndUtc,
    double WindKt,
    double? GustKt,
    string Summary);
```

**`Weather/IWeatherService.cs`**

```csharp
namespace DrunkenSailor.Api.Weather;

public interface IWeatherService
{
    Task<IReadOnlyList<HourlyForecast>?> GetHourlyForecastAsync(
        double latitude,
        double longitude,
        CancellationToken cancellationToken);
}
```

- The record uses **knots and numbers**, the units the rest of the app wants. Converting from the weather service's text happens in one place.
- The return type ends in **`?`**. `null` means "the forecast couldn't be fetched," and every caller has to deal with that case.
- This is the interface predicted in the Lesson 4 takeaways: "anything that can give me a forecast."

## Exercise 3: Call the weather service

**`Weather/NwsWeatherService.cs`**

```csharp
using System.Net.Http.Json;
using System.Text.RegularExpressions;

namespace DrunkenSailor.Api.Weather;

public class NwsWeatherService(HttpClient http, ILogger<NwsWeatherService> logger) : IWeatherService
{
    private const double MphToKnots = 0.868976;

    public async Task<IReadOnlyList<HourlyForecast>?> GetHourlyForecastAsync(
        double latitude,
        double longitude,
        CancellationToken cancellationToken)
    {
        try
        {
            var point = await http.GetFromJsonAsync<PointResponse>(
                $"points/{latitude:0.####},{longitude:0.####}", cancellationToken);

            var hourlyUrl = point?.Properties?.ForecastHourly;

            if (hourlyUrl is null)
                return null;

            var hourly = await http.GetFromJsonAsync<ForecastResponse>(hourlyUrl, cancellationToken);

            if (hourly?.Properties?.Periods is null)
                return null;

            return hourly.Properties.Periods
                .Select(p => new HourlyForecast(
                    p.StartTime.UtcDateTime,
                    p.EndTime.UtcDateTime,
                    ToKnots(p.WindSpeed) ?? 0,
                    ToKnots(p.WindGust),
                    p.ShortForecast ?? ""))
                .ToList();
        }
        catch (Exception ex) when (ex is HttpRequestException or TaskCanceledException or System.Text.Json.JsonException)
        {
            logger.LogWarning(ex, "Could not fetch the forecast for {Latitude},{Longitude}", latitude, longitude);
            return null;
        }
    }

    // "10 mph" -> 8.7, "10 to 15 mph" -> 13.0 (the higher number), null -> null
    internal static double? ToKnots(string? text)
    {
        if (string.IsNullOrWhiteSpace(text))
            return null;

        var numbers = Regex.Matches(text, @"\d+(\.\d+)?")
            .Select(m => double.Parse(m.Value, System.Globalization.CultureInfo.InvariantCulture))
            .ToList();

        if (numbers.Count == 0)
            return null;

        return Math.Round(numbers.Max() * MphToKnots, 1);
    }

    private record PointResponse(PointProperties? Properties);
    private record PointProperties(string? ForecastHourly);
    private record ForecastResponse(ForecastProperties? Properties);
    private record ForecastProperties(List<Period>? Periods);
    private record Period(
        DateTimeOffset StartTime,
        DateTimeOffset EndTime,
        string? WindSpeed,
        string? WindGust,
        string? ShortForecast);
}
```

- **The private records** at the bottom describe only the parts of the JSON you need. They're DTOs for someone else's API, and they stay hidden inside this class.
- **`GetFromJsonAsync<T>`** makes the request and reads the JSON into your type. It throws if the status isn't a success, the same choice `Invoke-RestMethod` makes.
- **`try` / `catch ... when`** catches three specific failures: the request failed, it timed out, or the JSON wasn't what you expected. Each becomes `null` plus a logged warning. Any other exception is a bug and is left alone.
- **`ToKnots`** deals with the string you noticed in Lesson 1. It's `internal static` so a test can call it directly.

Register it in phase one:

```csharp
builder.Services.AddHttpClient<IWeatherService, NwsWeatherService>(client =>
{
    client.BaseAddress = new Uri("https://api.weather.gov/");
    client.DefaultRequestHeaders.UserAgent.ParseAdd("DrunkenSailorAPI/0.1 (you@example.com)");
    client.DefaultRequestHeaders.Accept.ParseAdd("application/geo+json");
    client.Timeout = TimeSpan.FromSeconds(10);
});
```

Use your own email. This is the User-Agent rule from Lesson 1, and without it the service returns 403. The timeout matters: without one, a slow weather service would make your reservations hang.

For the test in Exercise 7 to reach `ToKnots`, add this to `DrunkenSailor.Api.csproj` inside a new `<ItemGroup>`:

```xml
<InternalsVisibleTo Include="DrunkenSailor.UnitTests" />
```

## Exercise 4: Cache the answer

The forecast changes about once an hour. Fetching it on every request is slow, and it's rude to a free public service. This is FR-W2.

```csharp
builder.Services.AddMemoryCache();
```

Add `IMemoryCache cache` to the `NwsWeatherService` constructor, rename the existing method body into a private `FetchAsync`, and make the public method:

```csharp
var key = $"forecast:{latitude:0.##},{longitude:0.##}";

if (cache.TryGetValue(key, out IReadOnlyList<HourlyForecast>? cached))
    return cached;

var fresh = await FetchAsync(latitude, longitude, cancellationToken);

if (fresh is not null)
    cache.Set(key, fresh, TimeSpan.FromMinutes(30));

return fresh;
```

Failures aren't cached, so the next request tries again.

## Exercise 5: The condition gate

Limits come from the README's table. Put them in one place.

**`Policies/CertLimits.cs`**

```csharp
using DrunkenSailor.Api.Domain;

namespace DrunkenSailor.Api.Policies;

public record CertLimits(double MaxWindKt, double MaxGustKt)
{
    public static CertLimits? For(CertType type)
    {
        return type switch
        {
            CertType.DaySkipper => new CertLimits(15, 18),
            CertType.KeelboatSkipper => new CertLimits(20, 25),
            _ => null
        };
    }
}
```

`type switch { ... }` is a **switch expression**: it picks a value by matching. `_` means "anything else."

Add a field to `ReservationContext`:

```csharp
IReadOnlyList<HourlyForecast>? Forecast
```

Then write **`Policies/ConditionGate.cs`** yourself. Its rules:

1. If the boat needs no certification (`RequiredCert` is null), pass.
2. If `Forecast` is null, **fail** with "The forecast is unavailable, so conditions can't be checked." This is NFR-7: fail safe.
3. Take the forecast hours that overlap the reservation window. If there are none (the date is beyond the forecast), pass.
4. Find the skipper's most generous limits among their certifications. If they have none with limits, pass and let the certification gate handle it.
5. If the highest wind exceeds `MaxWindKt`, or the highest gust exceeds `MaxGustKt`, fail with a message like "Forecast gusts 21 kt exceed your 18 kt limit."

In the controller's context-building method, fetch the forecast for the boat's club and pass it in. Register the gate as a third `IReservationPolicy`.

## Exercise 6: A conditions endpoint

Add `GET /clubs/{clubId}/conditions`, returning the next 12 hours of forecast for that club. If the weather service is unavailable, return a 503 with a Problem Details body. This is FR-W1.

**503 Service Unavailable** is the honest answer when your API is working but something it depends on isn't.

## Exercise 7: Test it with made-up weather

In `PolicyTests.cs`, build a forecast by hand:

```csharp
private static List<HourlyForecast> ForecastWith(double windKt, double? gustKt)
{
    var start = new DateTime(2026, 10, 10, 14, 0, 0, DateTimeKind.Utc);

    return Enumerable.Range(0, 4)
        .Select(hour => new HourlyForecast(
            start.AddHours(hour), start.AddHours(hour + 1), windKt, gustKt, "Test weather"))
        .ToList();
}
```

Write tests for: calm weather passes, 22 kt gusts fail for a Day Skipper, the same 22 kt gusts pass for a Keelboat Skipper, and a missing forecast fails. Add a theory for `ToKnots` covering `"10 mph"`, `"10 to 15 mph"`, `null`, and `""`.

This is the payoff promised when the plan was drawn up: you tested "22 kt gusts" without waiting for a windy day.

## Exercise 8: Break it on purpose

1. Remove the `UserAgent` line, restart, and call the conditions endpoint. Read the logged warning.
2. Change the base address to `https://api.weather.invalid/` and try to make a reservation. Read the violations.
3. Call the conditions endpoint twice and compare the response times.
4. Set the club's coordinates to `0, 0` and call the conditions endpoint.
5. Set the timeout to 1 millisecond.

---

## Deliverable

**Notes** (`docs/lesson-18.txt`):

1. In break-it 2, the weather service was unreachable and the reservation was refused. Argue for that choice, then argue against it.
2. What did caching change in break-it 3? What's the risk of caching a forecast for too long?
3. Why does the app use `HourlyForecast` in knots everywhere, when the weather service sends text in mph?
4. `NwsWeatherService` and a fake used in tests both satisfy `IWeatherService`. What does the condition gate know about either of them?
5. The README's POL-2 also mentions wave height, which this forecast doesn't include. Where would you look for it, and what would have to change?

**README updates:**

- Section 6: mark POL-2 as implemented for wind and gusts. Section 5: FR-W1 and FR-W2. Add wave height to the open questions.

**Commit:**

```powershell
git add .
git commit -m "Lesson 18: weather forecast and the condition gate"
git push
```
