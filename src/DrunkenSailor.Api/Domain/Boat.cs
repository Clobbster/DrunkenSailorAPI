namespace DrunkenSailor.Api.Domain;

public class Boat
{
    public int Id { get; set; }
    public required string Name { get; set; }
    public BoatType Type { get; set; }
    public double LengthFt { get; set; }
    public int Capacity { get; set; }
    public bool InService { get; set; }
}