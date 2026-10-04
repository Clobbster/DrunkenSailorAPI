# Return boats and format as table
Invoke-RestMethod http://localhost:5080/boats | Format-Table

# Return test cases
curl.exe -i http://localhost:5080/boats/2
curl.exe -i http://localhost:5080/boats/999
curl.exe -i http://localhost:5080/boats/banana

# NOTES: I would like a greater understanding of the lamba and the boat return. Moving on for now for time's sake.

 
# I should also like to review the builder.Services.ConfigureHttpJsonOptions. It has changed the contract for type from a number to a string.. it appears to me that a hidden dict enumerates and maps Type to numbers. 
<# ANSWER: You have the right instinct that there's a hidden mapping from names to numbers. It comes from a different place than you guessed, though. The numbers aren't created when the boats list is built. They come from the enum definition itself, in BoatType.cs:

csharp
public enum BoatType
{
    Sailboat,       // 0
    Motorboat,      // 1
    HumanPowered    // 2
}

#>



# Return test cases for new app.MapGet /boats route
curl.exe -i "http://localhost:5080/boats?type=Sailboat"
curl.exe -i "http://localhost:5080/boats?inService=false"
curl.exe -i "http://localhost:5080/boats?type=Sailboat&inService=true"
curl.exe -i "http://localhost:5080/boats?type=sailboat"
curl.exe -i "http://localhost:5080/boats?type=banana"