
// 1. Initialize the builder with preconfigured defaults and command-line arguments
// 2. BEFORE builder.Build(): one registers what the app has, such as a db connection, authentication, or other services.
// 3. AFTER  builder.Build(): one defines what the app does with a request, meaning routes and the steps each request passes through. 
using DrunkenSailor.Api.Domain;
using System.Text.Json.Serialization;


var builder = WebApplication.CreateBuilder(args);

builder.Services.ConfigureHttpJsonOptions(options =>
    options.SerializerOptions.Converters.Add(new JsonStringEnumConverter()));

var app = builder.Build();

var boats = new List<Boat>
{
    new Boat { Id = 1, Name = "Wet Noodle",    Type = BoatType.Sailboat,     LengthFt = 24, Capacity = 4, InService = true },
    new Boat { Id = 2, Name = "Second Wind",   Type = BoatType.Sailboat,     LengthFt = 19, Capacity = 3, InService = true },
    new Boat { Id = 3, Name = "Knot Today",    Type = BoatType.Sailboat,     LengthFt = 30, Capacity = 6, InService = false },
    new Boat { Id = 4, Name = "Safety Dance",  Type = BoatType.Motorboat,    LengthFt = 16, Capacity = 4, InService = true },
    new Boat { Id = 5, Name = "Paddle Faster", Type = BoatType.HumanPowered, LengthFt = 12, Capacity = 1, InService = true }
};


// C# lamba example & hello world.
app.MapGet("/", () => "Hello World!");


// Initial endpoints for health check and basic route testing.
app.MapGet("/health", () => new { status = "ok", time = DateTime.UtcNow });
app.MapGet("/boats/{id}", (int id) =>
{
    var boat = boats.FirstOrDefault(b => b.Id == id);

    return boat is null
        ? Results.NotFound(new { message = $"Boat {id} not found" })
        : Results.Ok(boat);
});


// Initial query parameter example.
app.MapGet("/greet", (string? name) => $"Ahoy, {name ?? "sailor"}!");


// Create reference function for boats and make available via an endpoint.
// app.MapGet("/boats", () => boats);

// Second iteration with query parameter filtering for boats.
app.MapGet("/boats", (BoatType? type, bool? inService) =>
{
    IEnumerable<Boat> result = boats;

    if (type is not null)
        result = result.Where(b => b.Type == type);

    if (inService is not null)
        result = result.Where(b => b.InService == inService);

    return result;
}); 


app.Run();