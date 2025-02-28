#!/bin/bash

set -e

# Create directories explicitly
mkdir -p my-aspnet-app
cd my-aspnet-app

# Create ASP.NET Core project explicitly
dotnet new webapi

# Generate HTTPS cert explicitly
dotnet dev-certs https --clean
dotnet dev-certs https -ep localhost.pfx -p "yourpassword"

# Convert pfx to PEM format explicitly for curl
openssl pkcs12 -in localhost.pfx -out localhost.pem -nodes -passin pass:yourpassword

# Trust cert explicitly (Linux)
sudo cp localhost.pem /usr/local/share/ca-certificates/localhost.crt
sudo update-ca-certificates || true

# Explicitly start the app in the background
dotnet run --urls "https://localhost:5001" &

# Explicitly wait for the app to start
sleep 10

# Explicitly test HTTPS using curl
curl -L --cacert localhost.pem https://localhost:5001/swagger

# Cleanup explicitly
kill %1
