# Lesson 12: PostgreSQL in Docker

> **Draft.** This lesson was written ahead of time and has not yet been run against your project. Before you start it, tell me and I will check every step against your code as it stands.

**Goal:** move from the SQLite file to PostgreSQL running in a container, which is the database in the README's target design. Almost none of your C# changes, and seeing how little changes is the lesson.

**Today's C#:** nothing new. Today's topics are configuration and secrets.

- [ ] Exercise 1: Run PostgreSQL
- [ ] Exercise 2: Swap the provider
- [ ] Exercise 3: Move the connection string out of the repo
- [ ] Exercise 4: Recreate the migrations
- [ ] Exercise 5: Look inside
- [ ] Exercise 6: Break it on purpose
- [ ] Notes, README, commit

## Why it's a small change

EF Core talks to databases through **providers**. Your queries are written against EF Core, and the provider translates them to one database's dialect of SQL.

| Layer | SQLite | PostgreSQL |
|---|---|---|
| Your LINQ queries | unchanged | unchanged |
| Your entities and configuration | unchanged | nearly unchanged |
| Provider package | `...EntityFrameworkCore.Sqlite` | `Npgsql.EntityFrameworkCore.PostgreSQL` |
| One line in `Program.cs` | `UseSqlite(...)` | `UseNpgsql(...)` |
| Migrations | SQLite-specific | must be regenerated |

## Exercise 1: Run PostgreSQL

Create **`docker-compose.yml`** in the repo root:

```yaml
services:
  db:
    image: postgres:17
    container_name: drunkensailor-db
    environment:
      POSTGRES_DB: drunkensailor
      POSTGRES_USER: drunkensailor
      POSTGRES_PASSWORD: devpass
    ports:
      - "5432:5432"
    volumes:
      - drunkensailor-data:/var/lib/postgresql/data

volumes:
  drunkensailor-data:
```

```powershell
docker compose up -d
docker compose ps
```

The named volume keeps the data when the container is removed. `devpass` is for local development only.

## Exercise 2: Swap the provider

```powershell
dotnet remove src/DrunkenSailor.Api package Microsoft.EntityFrameworkCore.Sqlite
dotnet add src/DrunkenSailor.Api package Npgsql.EntityFrameworkCore.PostgreSQL
```

In `Program.cs`, change `UseSqlite` to `UseNpgsql`.

In `ReservationConfiguration`, delete the two `HasConversion` lines on `StartUtc` and `EndUtc`. PostgreSQL has a proper "timestamp with time zone" type and returns UTC times correctly.

## Exercise 3: Move the connection string out of the repo

A connection string contains a password, so it doesn't belong in `appsettings.json`, which is committed.

Delete the `"ConnectionStrings"` section from `appsettings.json`. Then:

```powershell
dotnet user-secrets init --project src/DrunkenSailor.Api
dotnet user-secrets set --project src/DrunkenSailor.Api "ConnectionStrings:DrunkenSailor" "Host=localhost;Port=5432;Database=drunkensailor;Username=drunkensailor;Password=devpass"
```

`user-secrets` stores the value in your user profile, outside the repo. Your code doesn't change: `builder.Configuration.GetConnectionString("DrunkenSailor")` reads from several sources and merges them.

| Source | Used for | Committed? |
|---|---|---|
| `appsettings.json` | Defaults that are safe to share | Yes |
| `appsettings.Development.json` | Local, non-secret overrides | Yes |
| User secrets | Local secrets | No |
| Environment variables | Servers and CI | No |

Later sources override earlier ones. On a server, the same setting would be an environment variable named `ConnectionStrings__DrunkenSailor`, with a double underscore.

## Exercise 4: Recreate the migrations

Migration files contain provider-specific column types, so the SQLite ones can't be applied to PostgreSQL. Since nothing has been deployed anywhere, start the history over:

1. Delete the whole `Migrations/` folder.
2. Delete `drunkensailor.db`, and remove the three `*.db` lines from `.gitignore` if you like.
3. Run:

```powershell
dotnet ef migrations add InitialCreate --project src/DrunkenSailor.Api
dotnet ef database update --project src/DrunkenSailor.Api
```

Open the new migration and compare its column types with what you remember from SQLite: `integer`, `character varying(50)`, `timestamp with time zone`.

Start the server and run your requests. They should all behave as before.

## Exercise 5: Look inside

With the PostgreSQL extension in VS Code, connect using the values from the connection string. Browse the tables and run:

```sql
SELECT * FROM "Boats";
SELECT * FROM "__EFMigrationsHistory";
```

The double quotes matter. PostgreSQL lowercases unquoted names, and EF Core created the tables with capital letters.

## Exercise 6: Break it on purpose

1. Run `docker compose stop`, then call `GET /boats`. Read the status code and the server log. Start it again with `docker compose start`.
2. Run `docker compose down`, then `docker compose up -d`, and call `GET /boats`. Your data is still there.
3. Run `docker compose down -v`, then `up -d`, and start the server.
4. Send a reservation whose times have no `Z`, with your UTC check from Lesson 11 temporarily removed. Read the error from the provider, then restore the check.
5. Set the password in user secrets to something wrong, restart, and call the API.

---

## Deliverable

**Notes** (`docs/lesson-12.txt`):

1. List every file you changed to switch databases. Which of them contain business logic?
2. What's the difference between `docker compose down` and `docker compose down -v`?
3. In break-it 1, what status code did the caller get? Is that the right one? Which requirement in the README does this relate to?
4. Where is the connection string stored now? How would a teammate who clones the repo get theirs?
5. Why did the migrations have to be regenerated when the entity classes didn't change?

**README updates:**

- Section 10: Docker is now required.
- Section 11: the steps become clone, `dotnet tool restore`, `docker compose up -d`, set the user secret, `dotnet ef database update`, `dotnet run`.
- Section 13: add the three `docker compose` commands.

**Commit:**

```powershell
git add .
git commit -m "Lesson 12: move to PostgreSQL in Docker"
git push
```
