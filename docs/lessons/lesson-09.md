# Lesson 9: A real database with EF Core

> **Draft.** This lesson was written ahead of time and has not yet been run against your project. Before you start it, tell me and I will check every step against your code as it stands.

**Goal:** replace the in-memory `BoatStore` with a database, so boats survive a restart. You'll use Entity Framework Core (EF Core), which lets you query a database with the same LINQ you've been writing against a list.

**Today's C#:** `async` and `await`, `Task<T>`, and `using` blocks.

- [ ] Exercise 1: Add the package and a DbContext
- [ ] Exercise 2: Configure the connection
- [ ] Exercise 3: Create and seed the database at startup
- [ ] Exercise 4: Rewrite the controller
- [ ] Exercise 5: Watch the SQL
- [ ] Exercise 6: Break it on purpose
- [ ] Notes, README, commit

## What EF Core is

EF Core is an **ORM**, an object-relational mapper. You work with C# objects, and it writes the SQL. If you've used SQLAlchemy or Django's ORM in Python, or Prisma or Sequelize in JavaScript, it's the same category of tool.

| EF Core | What it is |
|---|---|
| `DbContext` | Your connection to the database, and a unit of work |
| `DbSet<Boat>` | The boats table, queryable with LINQ |
| `SaveChangesAsync()` | Sends all pending inserts, updates, and deletes |

You start with **SQLite**, a database stored in one file. There's no server to run. Lesson 12 switches to PostgreSQL.

## Exercise 1: Add the package and a DbContext

```powershell
dotnet add src/DrunkenSailor.Api package Microsoft.EntityFrameworkCore.Sqlite
```

Create **`Data/AppDbContext.cs`**:

```csharp
using DrunkenSailor.Api.Domain;
using Microsoft.EntityFrameworkCore;

namespace DrunkenSailor.Api.Data;

public class AppDbContext(DbContextOptions<AppDbContext> options) : DbContext(options)
{
    public DbSet<Boat> Boats => Set<Boat>();

    protected override void OnModelCreating(ModelBuilder modelBuilder)
    {
        modelBuilder.Entity<Boat>().Property(b => b.Type).HasConversion<string>();
        modelBuilder.Entity<Boat>().HasIndex(b => b.Name).IsUnique();
    }
}
```

- **`HasConversion<string>()`** stores the boat type as the text `"Sailboat"`. Without it the column would hold `0`, the same enum-as-number issue from Lesson 4.
- **`HasIndex(...).IsUnique()`** makes the database itself refuse two boats with the same name.

## Exercise 2: Configure the connection

In **`appsettings.json`**, add a section alongside `"Logging"`:

```json
"ConnectionStrings": {
  "DrunkenSailor": "Data Source=drunkensailor.db"
}
```

In phase one of `Program.cs`, replace the `AddSingleton<BoatStore>()` line:

```csharp
builder.Services.AddDbContext<AppDbContext>(options =>
    options.UseSqlite(builder.Configuration.GetConnectionString("DrunkenSailor")));
```

Add `using DrunkenSailor.Api.Data;` and `using Microsoft.EntityFrameworkCore;` at the top. `AddDbContext` registers the context as **scoped**: each request gets its own, and it's thrown away when the request ends.

Add these lines to `.gitignore` so the database file isn't committed:

```
*.db
*.db-shm
*.db-wal
```

## Exercise 3: Create and seed the database at startup

In phase two, right after `var app = builder.Build();`:

```csharp
using (var scope = app.Services.CreateScope())
{
    var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
    db.Database.EnsureCreated();

    if (!db.Boats.Any())
    {
        db.Boats.AddRange(
            new Boat { Name = "Wet Noodle",    Type = BoatType.Sailboat,     LengthFt = 24, Capacity = 4, InService = true },
            new Boat { Name = "Second Wind",   Type = BoatType.Sailboat,     LengthFt = 19, Capacity = 3, InService = true },
            new Boat { Name = "Knot Today",    Type = BoatType.Sailboat,     LengthFt = 30, Capacity = 6, InService = false,
                       MaintenanceNotes = "Cracked rudder. Waiting on the insurer." },
            new Boat { Name = "Safety Dance",  Type = BoatType.Motorboat,    LengthFt = 16, Capacity = 4, InService = true },
            new Boat { Name = "Paddle Faster", Type = BoatType.HumanPowered, LengthFt = 12, Capacity = 1, InService = true });
        db.SaveChanges();
    }
}
```

- There's no request at startup, so there's no scope for a scoped service to live in. `CreateScope()` makes one by hand, and `using (...) { }` disposes of it at the closing brace. It's the same idea as Python's `with` block.
- The boats have **no `Id`**. The database assigns one when each row is inserted.
- `EnsureCreated()` creates the file and table if they don't exist. Lesson 10 replaces it with something better.

## Exercise 4: Rewrite the controller

Change the constructor to take the context:

```csharp
public class BoatsController(AppDbContext db, ILogger<BoatsController> logger) : ControllerBase
```

Then rewrite each method. Here are two of the five; do the others the same way.

```csharp
[HttpGet]
public async Task<ActionResult<IEnumerable<BoatResponse>>> GetAll(BoatType? type, bool? inService)
{
    IQueryable<Boat> query = db.Boats;

    if (type is not null)
        query = query.Where(b => b.Type == type);

    if (inService is not null)
        query = query.Where(b => b.InService == inService);

    var boats = await query.OrderBy(b => b.Id).ToListAsync();

    return Ok(boats.Select(b => b.ToResponse()));
}

[HttpPost]
public async Task<ActionResult<BoatResponse>> Create(CreateBoatRequest request)
{
    var nameTaken = await db.Boats.AnyAsync(b => b.Name.ToLower() == request.Name.ToLower());
    if (nameTaken)
        return NameTaken(request.Name);

    var boat = new Boat
    {
        Name = request.Name,
        Type = request.Type,
        LengthFt = request.LengthFt,
        Capacity = request.Capacity,
        InService = true
    };
    db.Boats.Add(boat);
    await db.SaveChangesAsync();

    return CreatedAtAction(nameof(GetById), new { id = boat.Id }, boat.ToResponse());
}
```

What changed:

- **`async` / `await` / `Task<T>`** work as in JavaScript. A database call takes time, and `await` frees the server to handle other requests while it waits. `Task<T>` is C#'s `Promise<T>`.
- **`IQueryable<Boat>`** replaces `IEnumerable<Boat>`. It looks the same, but each `Where` is added to a SQL query and nothing runs yet.
- **`ToListAsync()`** is the moment the query is sent to the database.
- **`db.Boats.Add(boat)`** only marks the boat as new. **`SaveChangesAsync()`** performs the insert, and afterwards `boat.Id` holds the id the database chose.

For the rest: `GetById`, `Update`, and `Delete` use `await db.Boats.FindAsync(id)` to load one boat. `Update` changes its properties and calls `SaveChangesAsync()`. `Delete` calls `db.Boats.Remove(boat)` and then `SaveChangesAsync()`.

Delete `Services/BoatStore.cs`. Restart and run your requests.

## Exercise 5: Watch the SQL

Call `GET /boats?type=Sailboat&inService=true` and read the server's terminal. EF Core logs the SQL it ran. Find the `WHERE` clause and match its two conditions to your two `Where` calls.

Then call plain `GET /boats` and compare the SQL.

## Exercise 6: Break it on purpose

1. Add a boat, restart the server, and call `GET /boats`.
2. In `GetAll`, change `IQueryable<Boat> query = db.Boats;` to `IEnumerable<Boat> query = db.Boats;`. It still compiles. Call the filtered URL and read the SQL. Change it back.
3. Remove the `nameTaken` check and `POST` a duplicate name. Read the status code and the server log. Restore the check.
4. Stop the server, delete `drunkensailor.db`, and start again.

---

## Deliverable

**Notes** (`docs/lesson-09.txt`):

1. After break-it 1, was your boat still there? What's different from Lesson 5's Exercise 6?
2. In break-it 2, how did the SQL change? Where did the filtering happen in each version, and why does that matter with 50,000 boats?
3. In break-it 3, the database refused the duplicate. What status code did the caller get? Why keep the check in the controller when the database already enforces the rule?
4. `Add` and `SaveChangesAsync` are separate steps. What might be useful about that?
5. Why is the `DbContext` scoped and not a singleton like `BoatStore` was?

**README updates:**

- Section 11: remove the sentence saying boats are lost on restart.
- Section 12: add `Data/` to the "Today" tree and remove `Services/`.

**Commit:**

```powershell
git add .
git commit -m "Lesson 9: store boats in SQLite with EF Core"
git push
```
