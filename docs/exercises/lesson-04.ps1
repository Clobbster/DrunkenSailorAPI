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


# Rewrite app.MapGet /boats/{id} as a powershell function without lambda for reference
function Get-BoatById {
    param([int]$Id)

    # Look through the boats for the first one whose Id matches
    $boat = $null
    foreach ($b in $boats) {
        if ($b.Id -eq $Id) {
            $boat = $b
            break
        }
    }

    # Decide what to send back
    if ($null -eq $boat) {
        return @{ Status = 404; Body = @{ message = "Boat $Id not found" } }
    }
    else {
        return @{ Status = 200; Body = $boat }
    }
}



# Rewrite app.MapGet /boats as a powershell function without lambda for reference
function Get-Boats {
    param($Type = $null, $InService = $null)

    # Start with every boat
    $result = $boats

    # If a type was given, keep only the boats of that type
    if ($null -ne $Type) {
        $kept = @()
        foreach ($b in $result) {
            if ($b.Type -eq $Type) {
                $kept += $b
            }
        }
        $result = $kept
    }

    # If inService was given, keep only the boats that match it
    if ($null -ne $InService) {
        $kept = @()
        foreach ($b in $result) {
            if ($b.InService -eq $InService) {
                $kept += $b
            }
        }
        $result = $kept
    }

    return $result
}