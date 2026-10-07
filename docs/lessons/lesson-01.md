# Lesson 1: Reading a real API

*Completed October 1, 2026.*

**Goal:** before you build an API, look closely at a well-designed one and name what it does. You call the National Weather Service API by hand (the same one the app will use later) and pick up five ideas reused in every later lesson.

**You need:** PowerShell. No C# in this lesson.

> **PowerShell gotcha:** in Windows PowerShell, `curl` is an alias for `Invoke-WebRequest`, which behaves differently from real curl. Always type **`curl.exe`** to get actual curl.

## Idea 1: An HTTP call is just text

Every API call is a request (method, URL, headers, optional body) and a response (status code, headers, body).

**Exercise 1.** Ask the NWS what it knows about Grand Haven, Michigan:

```powershell
curl.exe -i -H "User-Agent: DrunkenSailorAPI-learning (you@example.com)" https://api.weather.gov/points/43.0631,-86.2284
```

`-i` shows the response headers as well as the body, and `-H` adds a request header. Look at:

- The **first line**, `HTTP/1.1 200 OK`. That's the status code.
- **`Content-Type`**, which tells you what format the body is in.
- **`Cache-Control`** and **`Expires`**. The server is telling you how long you can reuse this answer. Remember this for FR-W2 (caching forecasts).

## Idea 2: URLs name things, not actions

The URL `/points/43.0631,-86.2284` is a noun, "this point on the map," not `/getPointInfo?lat=...`. That's the core idea of REST: **URLs identify resources, and HTTP methods say what you're doing to them.**

**Exercise 2.** In the body, find `"properties"`. Inside are URLs like `forecast`, `forecastHourly`, and `forecastZone`. The API **links** to the next URL instead of making you build it. Copy the `forecast` URL and call it:

```powershell
curl.exe -H "User-Agent: DrunkenSailorAPI-learning (you@example.com)" <paste the forecast URL>
```

The URL has the shape `/gridpoints/GRR/x,y/forecast`. The parent resource is the gridpoint, and `forecast` is a sub-resource of it. This is the same pattern as `/reservations/{id}/crew-requests` in the README.

## Idea 3: Parse it like a program would

PowerShell can parse JSON into objects, much like `json.loads()` in Python.

**Exercise 3.**

```powershell
$headers = @{ "User-Agent" = "DrunkenSailorAPI-learning (you@example.com)" }
$point = Invoke-RestMethod -Uri "https://api.weather.gov/points/43.0631,-86.2284" -Headers $headers
$point.properties.forecast
$forecast = Invoke-RestMethod -Uri $point.properties.forecast -Headers $headers
$forecast.properties.periods | Select-Object -First 4 name, windSpeed, windDirection, shortForecast
```

`windSpeed` is a **string**, like `"10 to 15 mph"`, not a number, and it's in mph, not knots. The condition gate in Lesson 18 has to deal with that. With an external API, you take the data in whatever shape they send it.

## Idea 4: Status codes are a contract

**Exercise 4: break it on purpose.** Run each with `-i` and note the status code and body:

```powershell
# a) No User-Agent header at all
curl.exe -i -H "User-Agent:" https://api.weather.gov/points/43.0631,-86.2284

# b) A point in the middle of the Atlantic (no NWS coverage)
curl.exe -i -H "User-Agent: DrunkenSailorAPI-learning (you@example.com)" https://api.weather.gov/points/30,-40

# c) Nonsense coordinates
curl.exe -i -H "User-Agent: DrunkenSailorAPI-learning (you@example.com)" https://api.weather.gov/points/banana

# d) The wrong method: trying to POST to a read-only resource
curl.exe -i -X POST -H "User-Agent: DrunkenSailorAPI-learning (you@example.com)" https://api.weather.gov/points/43.0631,-86.2284
```

| Range | Meaning | Whose fault |
|---|---|---|
| 2xx | It worked | n/a |
| 4xx | Your request was wrong | The caller's |
| 5xx | The server broke | The server's |

## Idea 5: Errors deserve a shape too

Look at the error bodies from Exercise 4: the `Content-Type` and the fields `type`, `title`, `status`, `detail`. This is a standard format called **Problem Details** (RFC 9457). ASP.NET Core uses the same format, and the README's "violations" response is a Problem Details body with extra fields.

**Exercise 5: something useful for sailors.** Active alerts for the Lake Michigan marine area:

```powershell
$alerts = Invoke-RestMethod -Uri "https://api.weather.gov/alerts/active?area=LM" -Headers $headers
$alerts.features.properties | Select-Object event, headline
```

No active alerts gives an empty list, which is a valid answer and still a `200`. Note `?area=LM`: **query strings filter a collection**, while path segments identify a specific thing.

---

## Deliverable

Notes in `docs/lesson-01.txt`:

1. What status code and `Content-Type` did each request in Exercise 4 return? Was any of them surprising?
2. Why do you think NWS requires a User-Agent header?
3. The `points` response links to the forecast URL instead of making you build it. What's one advantage of that for the API's owners?
4. Write three endpoints for **boats**, using a method and URL for each: list all boats, get one boat, and add a boat. What status code should "get a boat that doesn't exist" return?
5. A reservation is denied by the certification gate. Is that a 4xx or a 5xx? Which specific code would you pick, and why?

## Takeaways from the review

- **4a:** removing the header returns **403 Forbidden**. Windows PowerShell silently drops empty strings like `""` when passing arguments to programs, which is why `-A ""` didn't work and `-H "User-Agent:"` does.
- **4d:** the textbook answer for a wrong method is **405 Method Not Allowed**. NWS returned a 400 from the server in front of the API, so the error came from a different layer and had a different shape.
- **Identification, authentication, authorization** are three different things. The User-Agent header is only the first: it says who claims to be calling, with no proof.
- **Links in responses** let the owner change URL structure without breaking clients that follow the links.
- **Boat endpoints:** `GET /boats` (200 + array), `GET /boats/{id}` (200, or 404 if missing), `POST /boats` (201 + `Location` header). Boat *type* is a property of a boat, not the resource itself.
- **A policy denial is 403 Forbidden**, not 404. The 4xx codes used most:

| Code | Meaning | Sailing example |
|---|---|---|
| 400 Bad Request | The request is malformed | End time before start time |
| 401 Unauthorized | We don't know who you are | No login token |
| 403 Forbidden | We know who you are, and you're not allowed | Not certified for this boat |
| 404 Not Found | That thing doesn't exist | Boat 999 |
| 409 Conflict | It clashes with the current state | Boat already booked |
