#!/bin/bash

set -e

# Explicit Variables
CERT_PASSWORD="yourpassword"
CA_NAME="LocalhostDevelopmentCA"

# Explicitly create directories and project
mkdir -p my-aspnet-app
cd my-aspnet-app
dotnet new webapi

# Clean existing certs
rm -rf ~/.aspnet/https/* ~/.dotnet/corefx/cryptography/x509stores/*
dotnet dev-certs https --clean

# Explicitly generate Root CA
openssl req -x509 -newkey rsa:4096 -sha256 -days 3650 -nodes \
  -keyout localhost-ca.key -out localhost-ca.crt \
  -subj "/CN=${CA_NAME}" -addext "basicConstraints=critical,CA:true"

# Explicitly trust CA cert (Linux store)
sudo cp localhost-ca.crt /usr/local/share/ca-certificates/${CA_NAME}.crt
sudo update-ca-certificates || true

# Explicitly trust CA cert in Chrome's NSS DB
mkdir -p $HOME/.pki/nssdb
certutil -d sql:$HOME/.pki/nssdb -N --empty-password || true
certutil -d sql:$HOME/.pki/nssdb -A -t "CT,C,C" -n "${CA_NAME}" -i localhost-ca.crt
certutil -d sql:$HOME/.pki/nssdb -L | grep ${CA_NAME}

# Explicitly generate localhost cert signed by CA
openssl req -newkey rsa:4096 -nodes \
  -keyout localhost.key -out localhost.csr \
  -subj "/CN=localhost"

openssl x509 -req -in localhost.csr -CA localhost-ca.crt -CAkey localhost-ca.key \
  -CAcreateserial -out localhost.crt -days 3650 -sha256 \
  -extfile <(echo "subjectAltName=DNS:localhost")

# Explicitly create localhost PFX
openssl pkcs12 -export -out localhost.pfx -inkey localhost.key \
  -in localhost.crt -passout pass:"${CERT_PASSWORD}"

# Convert to PEM explicitly for curl
openssl pkcs12 -in localhost.pfx -out localhost.pem -nodes -passin pass:"${CERT_PASSWORD}"

# Start ASP.NET Core explicitly with your own cert
dotnet run --urls "https://localhost:5001" \
  --Kestrel:Certificates:Default:Path=localhost.pfx \
  --Kestrel:Certificates:Default:Password="${CERT_PASSWORD}" &

# Explicit wait for server startup
sleep 10

# Explicit verification (OpenSSL)
openssl s_client -connect localhost:5001 -showcerts </dev/null 2>/dev/null | openssl x509 -noout -text

# Explicitly verify HTTPS via curl
curl -vL --cacert localhost-ca.crt https://localhost:5001/swagger

# Explicitly verify HTTPS via Chrome Headless
google-chrome --headless --disable-gpu --no-sandbox --dump-dom https://localhost:5001/swagger

# Explicit cleanup
kill %1
