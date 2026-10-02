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

#View the various routes and content-types call to call
curl.exe -i http://localhost:5080/
curl.exe -i http://localhost:5080/health
curl.exe -i http://localhost:5080/boats/42

#Call greet
curl.exe -i http://localhost:5080/greet
curl.exe -i http://localhost:5080/greet?name=Christian



# BREAK IT ON PURPOSE. FOR SCIENCE!
# a) A route that doesn't exist
curl.exe -i http://localhost:5080/nope           #404 Not Found

# b) A boat id that isn't a number
curl.exe -i http://localhost:5080/boats/banana   #400 Bad Request

# c) The wrong method
curl.exe -i -X POST http://localhost:5080/health #405 Meathod Not Allowed

# d) Stop the server (Ctrl+C), then call it   
curl.exe -i http://localhost:5080/               #Failed to connect to ...