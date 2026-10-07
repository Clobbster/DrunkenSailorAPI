namespace DrunkenSailor.Api.Domain;


// We probably want to behavior-rich domain model here. 
// Custom domain exception
// Encapsulate a rule
public class Boat
{
    public int Id { get; set; }
    public required string Name { get; set; }
    public BoatType Type { get; set; }
    public double LengthFt { get; set; }
    public int Capacity { get; set; }
    public bool InService { get; set; }
}