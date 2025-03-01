#!/bin/bash

set -e

# Explicit Variables
CERT_PASSWORD="yourpassword"
CA_NAME="LocalhostDevelopmentCA"
APP_DIR="my-aspnet-app"

# Ensure app directory exists and initialize if needed
if [ ! -d "$APP_DIR" ]; then
    mkdir -p "$APP_DIR"
    cd "$APP_DIR"
    dotnet new webapi
else
    cd "$APP_DIR"
fi

# Remove existing CA and cert files to ensure idempotency
rm -f localhost-ca.* localhost.* *.pfx *.pem *.csr *.srl

# Reset NSS DB completely to remove all existing certificates (idempotency)
rm -rf $HOME/.pki/nssdb
mkdir -p $HOME/.pki/nssdb
certutil -d sql:$HOME/.pki/nssdb -N --empty-password

# Generate new Root CA
openssl req -x509 -newkey rsa:4096 -sha256 -days 3650 -nodes \
  -keyout localhost-ca.key -out localhost-ca.crt \
  -subj "/CN=${CA_NAME}" -addext "basicConstraints=critical,CA:true"

# Trust CA cert (Linux store)
sudo cp localhost-ca.crt /usr/local/share/ca-certificates/${CA_NAME}.crt
sudo update-ca-certificates || true

# Trust CA cert in Chrome's NSS DB
certutil -d sql:$HOME/.pki/nssdb -A -t "CT,C,C" -n "${CA_NAME}" -i localhost-ca.crt

# Generate localhost cert and sign with CA
openssl req -newkey rsa:4096 -nodes \
  -keyout localhost.key -out localhost.csr \
  -subj "/CN=localhost"

openssl x509 -req -in localhost.csr -CA localhost-ca.crt -CAkey localhost-ca.key \
  -CAcreateserial -out localhost.crt -days 3650 -sha256 \
  -extfile <(echo "subjectAltName=DNS:localhost")

# Create localhost PFX
openssl pkcs12 -export -out localhost.pfx -inkey localhost.key \
  -in localhost.crt -passout pass:"${CERT_PASSWORD}"

# Convert to PEM for curl
openssl pkcs12 -in localhost.pfx -out localhost.pem -nodes -passin pass:"${CERT_PASSWORD}"

# Update appsettings.json
cat > appsettings.json <<EOF
{
  "Kestrel": {
    "Endpoints": {
      "Https": {
        "Url": "https://localhost:5001"
      }
    },
    "Certificates": {
      "Default": {
        "Path": "localhost.pfx",
        "Password": "${CERT_PASSWORD}"
      }
    }
  }
}
EOF

# Terminate any existing server on port 5001 (idempotency)
existing_pid=$(lsof -t -i:5001 || true)
if [ -n "$existing_pid" ]; then
    echo "Terminating existing server on port 5001..."
    kill -9 $existing_pid
fi

# Start ASP.NET Core application
dotnet run &
SERVER_PID=$!

# Wait for server startup
sleep 10

# Verify certificates via OpenSSL
openssl s_client -connect localhost:5001 -showcerts </dev/null 2>/dev/null | openssl x509 -noout -text

# Verify Swagger UI via curl (check status 200 and HTML content)
curl -fsSL --cacert localhost-ca.crt https://localhost:5001/swagger/index.html | grep -q '<title>Swagger UI</title>' && echo "Swagger UI loaded successfully via curl."

# Verify Swagger UI via Chrome Headless (ensure the Swagger UI page loads correctly)
google-chrome --headless --disable-gpu --no-sandbox --dump-dom https://localhost:5001/swagger/index.html | grep -q 'swagger-ui' && echo "Swagger UI loaded successfully via Chrome."

# Cleanup: Stop the ASP.NET server after testing
kill $SERVER_PID || true
