#!/bin/bash

set -e

# Explicit Variables
CERT_PASSWORD="yourpassword"
CA_NAME="LocalhostDevelopmentCA"
APP_DIR="my-aspnet-app"

# Check if ASP.NET app already exists, if not, create it
if [ ! -d "$APP_DIR" ]; then
    mkdir -p "$APP_DIR"
    cd "$APP_DIR"
    dotnet new webapi
else
    cd "$APP_DIR"
fi

# Check if Root CA already exists, if not, generate
if [ ! -f localhost-ca.crt ]; then
    openssl req -x509 -newkey rsa:4096 -sha256 -days 3650 -nodes \
      -keyout localhost-ca.key -out localhost-ca.crt \
      -subj "/CN=${CA_NAME}" -addext "basicConstraints=critical,CA:true"

    # Trust CA cert (Linux store)
    sudo cp localhost-ca.crt /usr/local/share/ca-certificates/${CA_NAME}.crt
    sudo update-ca-certificates || true

    # Trust CA cert in Chrome's NSS DB
    mkdir -p $HOME/.pki/nssdb
    certutil -d sql:$HOME/.pki/nssdb -N --empty-password || true

    if ! certutil -d sql:$HOME/.pki/nssdb -L | grep -q ${CA_NAME}; then
        certutil -d sql:$HOME/.pki/nssdb -A -t "CT,C,C" -n "${CA_NAME}" -i localhost-ca.crt
    fi
fi

# Check if localhost cert already exists, if not, generate
if [ ! -f localhost.crt ]; then
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
fi

# Create or update appsettings.json with HTTPS configuration
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

# Check if server is already running, terminate if so
existing_pid=$(lsof -t -i:5001 || true)
if [ -n "$existing_pid" ]; then
    echo "Terminating existing server on port 5001..."
    kill -9 $existing_pid
fi

# Start ASP.NET Core application using configured cert
dotnet run &
SERVER_PID=$!

# Wait for server startup
sleep 10

# Verify (OpenSSL)
openssl s_client -connect localhost:5001 -showcerts </dev/null 2>/dev/null | openssl x509 -noout -text

# Verify HTTPS via curl
curl -vL --cacert localhost-ca.crt https://localhost:5001/swagger

# Verify HTTPS via Chrome Headless
google-chrome --headless --disable-gpu --no-sandbox --dump-dom https://localhost:5001/swagger

# Cleanup: Stop the ASP.NET server after testing
kill $SERVER_PID || true
