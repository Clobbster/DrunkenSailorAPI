
// 1. Initialize the builder with preconfigured defaults and command-line arguments
// 2. BEFORE builder.Build(): one registers what the app has, such as a db connection, authentication, or other services.
// 3. AFTER  builder.Build(): one defines what the app does with a request, meaning routes and the steps each request passes through. 
var builder = WebApplication.CreateBuilder(args);
var app = builder.Build();

// C# lamba example & hello world.
app.MapGet("/", () => "Hello World!");

// Initial endpoints for health check and basic route testing.
app.MapGet("/health", () => new { status = "ok", time = DateTime.UtcNow });
app.MapGet("/boats/{id}", (int id) => $"You asked for boat {id}");
app.MapGet("/greet", (string? name) => $"Ahoy, {name ?? "sailor"}!");


app.Run();