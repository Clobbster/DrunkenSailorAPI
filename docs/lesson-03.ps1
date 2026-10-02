#Create the solution and project
cd C:\dev\drunkensailorapi\DrunkenSailorAPI
dotnet new sln -n DrunkenSailor
dotnet new web -n DrunkenSailor.Api -o src/DrunkenSailor.Api
dotnet sln add src/DrunkenSailor.Api/DrunkenSailor.Api.csproj
code .

#Run the api
dotnet run --project src/DrunkenSailor.Api

#Validate the api is running
curl.exe -i http://localhost:5080/

#Start api in watch mode: reloads when one saves
dotnet watch --project src/DrunkenSailor.Api
