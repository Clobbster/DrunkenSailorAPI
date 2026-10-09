########
# CRUD #
########

# Add Boat
$boat = @{
    name      = "Sea You Later"
    type      = "Sailboat"
    lengthFt  = 22
    capacity  = 4
    inService = $true
}

$response = Invoke-WebRequest -Method Post -Uri "http://localhost:5080/boats" -ContentType "application/json" -Body ($boat | ConvertTo-Json)

$response.StatusCode
$response.Headers.Location
$response.Content


# Response
HTTP/1.1 201 Created
Connection: close
Content-Type: application/json; charset=utf-8
Date: Wed, 07 Oct 2026 18:19:53 GMT
Server: Kestrel
Location: /boats/6
Transfer-Encoding: chunked





# Update/Replace Boat
$boat = @{
    name      = "Knot Today"
    type      = "Sailboat"
    lengthFt  = 30
    capacity  = 6
    inService = $true
}

$response = Invoke-WebRequest -Method Put -Uri "http://localhost:5080/boats/3" -ContentType "application/json" -Body ($boat | ConvertTo-Json) -UseBasicParsing

$response.StatusCode
$response.Content


# Response
HTTP/1.1 200 OK
Connection: close
Content-Type: application/json; charset=utf-8
Date: Thu, 08 Oct 2026 13:58:22 GMT
Server: Kestrel
Transfer-Encoding: chunked

{
  "id": 3,
  "name": "Knot Today",
  "type": "Sailboat",
  "lengthFt": 30,
  "capacity": 6,
  "inService": true
}





# Delete boat
$response = Invoke-WebRequest -Method Delete -Uri "http://localhost:5080/boats/8" -UseBasicParsing

$response.StatusCode


# Response
HTTP/1.1 204 No Content
Connection: close
Date: Thu, 08 Oct 2026 13:59:01 GMT
Server: Kestrel



#########
# TESTS #
#########

# Perform the following exercises:

# A POST with the "name" line removed.
$boat = @{
    #name      = "Sea You Later"
    type      = "Sailboat"
    lengthFt  = 22
    capacity  = 4
    inService = $true
}

$response = Invoke-WebRequest -Method Post -Uri "http://localhost:5080/boats" -ContentType "application/json" -Body ($boat | ConvertTo-Json)

$response.StatusCode
$response.Headers.Location
$response.Content

# Responds: 400 Bad Request



# A POST with "type": "Submarine".
$boat = @{
    name      = "Sea You Later"
    type      = "Submarine"
    lengthFt  = 22
    capacity  = 4
    inService = $true
}

$response = Invoke-WebRequest -Method Post -Uri "http://localhost:5080/boats" -ContentType "application/json" -Body ($boat | ConvertTo-Json)

$response.StatusCode
$response.Headers.Location
$response.Content

# Responds: 400 Bad Request



# A POST with the Content-Type: application/json line removed.
$boat = @{
    name      = "Sea You Later"
    type      = "Submarine"
    lengthFt  = 22
    capacity  = 4
    inService = $true
}

$response = Invoke-WebRequest -Method Post -Uri "http://localhost:5080/boats" -Body ($boat | ConvertTo-Json)

$response.StatusCode
$response.Headers.Location
$response.Content

# Responds: 415 Unsupported Media Type



# A POST with "id": 999 added to the body. What id does the new boat get?
$boat = @{
    name      = "Sea You Later"
    type      = "Sailboat"
    lengthFt  = 22
    capacity  = 4
    inService = $true
    id        = 999
}

$response = Invoke-WebRequest -Method Post -Uri "http://localhost:5080/boats" -ContentType "application/json" -Body ($boat | ConvertTo-Json)

$response.StatusCode
$response.Headers.Location
$response.Content

#Responds: ID is 9 instead of '999'



# A POST with "capacity": -3.
$boat = @{
    name      = "Sea You Later"
    type      = "Sailboat"
    lengthFt  = 22
    capacity  = -3
    inService = $true
}

$response = Invoke-WebRequest -Method Post -Uri "http://localhost:5080/boats" -ContentType "application/json" -Body ($boat | ConvertTo-Json)

$response.StatusCode
$response.Headers.Location
$response.Content

# Responds: Capacity at -3 is entered erroneously



# PUT /boats/999.
$boat = @{
    name      = "Sea You Later"
    type      = "Sailboat"
    lengthFt  = 22
    capacity  = 4
    inService = $true
}

$response = Invoke-WebRequest -Method Post -Uri "http://localhost:5080/boats/999" -ContentType "application/json" -Body ($boat | ConvertTo-Json)

$response.StatusCode
$response.Headers.Location
$response.Content

# Responds: 405 Method Not Allowed



# The same DELETE twice in a row.
$response = Invoke-WebRequest -Method Delete -Uri "http://localhost:5080/boats/10" -UseBasicParsing

$response.StatusCode

# Responds: 204
# Responds: 404 Not Found



# Add a boat post 2x
# Responds 201 created new entries each time

# Replace boat 3 2x
# Responds 200 OK, updates in place