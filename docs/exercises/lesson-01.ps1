#1
#Ask the NWS what it knows about Grand Haven, Michigan
curl.exe -i -H "User-Agent: DrunkenSailorAPI-learning (you@example.com)" https://api.weather.gov/points/43.0631,-86.2284
#NOTES1#
### -i shows the response headers as well as the body, and -H adds a request header. Look at:
### The first line, HTTP/1.1 200 OK. That's the status code.
### Content-Type, which tells you what format the body is in. Note the exact value; it isn't plain application/json.
### Cache-Control and Expires. The server is telling you how long you can reuse this answer. Remember this for FR-W2 (caching forecasts).



#2
#Look for the linked URL for forecast and modify your call. Notice that the API links to additional resources.
#curl.exe -H "User-Agent: DrunkenSailorAPI-learning (you@example.com)" <paste the forecast URL>
curl.exe -H "User-Agent: DrunkenSailorAPI-learning (you@example.com)" https://api.weather.gov/gridpoints/GRR/22,50/forecast



#3
$headers = @{ "User-Agent" = "DrunkenSailorAPI-learning (you@example.com)" }
$point = Invoke-RestMethod -Uri "https://api.weather.gov/points/43.0631,-86.2284" -Headers $headers
$point.properties.forecast
$forecast = Invoke-RestMethod -Uri $point.properties.forecast -Headers $headers
$forecast.properties.periods | Select-Object -First 4 name, windSpeed, windDirection, shortForecast
#NOTES3#
### I don't see properties.forecast in the output of the last curl. I need to verify how the $point.properties.forecast is working properly.. perhaps a simple parse of the output of the curl 



#4
#For educational benefit, break your calls on purpose
# 2xx - Your call worked
# 4xx - Your call is wrong
# 5xx - The server broke

# a) No User-Agent header at all
curl.exe -i -A "" https://api.weather.gov/points/43.0631,-86.2284

# b) A point in the middle of the Atlantic (no NWS coverage)
curl.exe -i -H "User-Agent: DrunkenSailorAPI-learning (you@example.com)" https://api.weather.gov/points/30,-40

# c) Nonsense coordinates
curl.exe -i -H "User-Agent: DrunkenSailorAPI-learning (you@example.com)" https://api.weather.gov/points/banana

# d) The wrong method: trying to POST to a read-only resource
curl.exe -i -X POST -H "User-Agent: DrunkenSailorAPI-learning (you@example.com)" https://api.weather.gov/points/43.0631,-86.2284




#5
#Alerts
$alerts = Invoke-RestMethod -Uri "https://api.weather.gov/alerts/active?area=LM" -Headers $headers
$alerts.features.properties | Select-Object event, headline
#NOTES5#
### Note the ?area=LM in the URL. This is a query string and filters a collection. The path segment identify a specific thing