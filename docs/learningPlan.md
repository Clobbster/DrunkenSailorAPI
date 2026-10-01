Phase 0: Ground work

API design refresher: you'll call the NWS API by hand and look at how a real API names its resources and handles errors.
The .NET toolchain: the SDK, the dotnet CLI, how .csproj and NuGet work, and global.json.

Phase 1: Your first API (C#: types, classes, records, LINQ, nullability)
3. The smallest API: Program.cs line by line, compared to Express and FastAPI.
4. One resource: boats in an in-memory list, with GET all, GET one, and 404s.
5. Changing data: POST, PUT, DELETE, and choosing status codes.
6. DTOs: why the API shouldn't expose internal classes.
7. Validation and consistent error responses.
8. Minimal APIs vs. controllers.

Phase 2: Saving data (C#: async/await, generics)
9. EF Core with SQLite.
10. Migrations.
11. Relationships: clubs, boats, reservations.
12. PostgreSQL in Docker. You know Docker already, so this one is quick.

Phase 3: Business rules (C#: enums, interfaces, exceptions)
13. The reservation state machine.
14. The certification gate policy and the violations response.
15. Unit tests with xUnit (the C# version of pytest).

Phase 4: Who's asking? (C#: dependency injection in depth)
16. Authentication: register, log in, bearer tokens.
17. Authorization: club roles, then scoped roles.

Phase 5: The outside world
18. Calling the NWS API from C#, and the condition gate.
19. Background jobs: the overdue float plan monitor.

Phase 6: Growing up
20. Refactoring into layers.
21. Integration tests, API docs, and a CI pipeline in GitHub Actions, which should feel like home given your DevOps background.