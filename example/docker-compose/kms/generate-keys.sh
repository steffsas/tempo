#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# MinIO + KES Dev Certificate Generator
# Creates a CA, signs KES + MinIO certs, and sets up folder structure.
# =============================================================================

# Clean up old certs
rm -rf kes minio
mkdir -p kes/certs kes/keys minio/certs/CAs

echo "✅ Creating a local Certificate Authority (CA)..."
openssl genrsa -out kes/certs/ca.key 4096
openssl req -x509 -new -nodes -key kes/certs/ca.key -sha256 -days 3650 \
  -out kes/certs/ca.crt -subj "/CN=MinIO Dev CA"

# -----------------------------------------------------------------------------
# Create OpenSSL config files for SAN
# -----------------------------------------------------------------------------
cat > kes/openssl-san.cnf <<EOF
[ req ]
default_bits       = 4096
distinguished_name = req_distinguished_name
req_extensions     = v3_req
prompt             = no

[ req_distinguished_name ]
CN = kes

[ v3_req ]
subjectAltName = @alt_names

[ alt_names ]
DNS.1 = kes
IP.1  = 127.0.0.1
EOF

cat > minio/openssl-san.cnf <<EOF
[ req ]
default_bits       = 4096
distinguished_name = req_distinguished_name
req_extensions     = v3_req
prompt             = no

[ req_distinguished_name ]
CN = minio

[ v3_req ]
subjectAltName = @alt_names

[ alt_names ]
DNS.1 = minio
IP.1  = 127.0.0.1
EOF

# -----------------------------------------------------------------------------
# Generate KES certificate
# -----------------------------------------------------------------------------
echo "✅ Generating KES TLS cert..."
openssl genrsa -out kes/certs/kes.key 4096
openssl req -new -key kes/certs/kes.key -out kes/certs/kes.csr -config kes/openssl-san.cnf
openssl x509 -req -in kes/certs/kes.csr \
  -CA kes/certs/ca.crt -CAkey kes/certs/ca.key -CAcreateserial \
  -out kes/certs/kes.crt -days 365 -sha256 \
  -extfile kes/openssl-san.cnf -extensions v3_req

# -----------------------------------------------------------------------------
# Generate MinIO client certificate
# -----------------------------------------------------------------------------
echo "✅ Generating MinIO TLS cert..."
openssl genrsa -out minio/certs/minio.key 4096
openssl req -new -key minio/certs/minio.key -out minio/certs/minio.csr -config minio/openssl-san.cnf
openssl x509 -req -in minio/certs/minio.csr \
  -CA kes/certs/ca.crt -CAkey kes/certs/ca.key -CAcreateserial \
  -out minio/certs/minio.crt -days 365 -sha256 \
  -extfile minio/openssl-san.cnf -extensions v3_req

# -----------------------------------------------------------------------------
# Copy CA to MinIO trust path
# -----------------------------------------------------------------------------
cp kes/certs/ca.crt minio/certs/CAs/kes_ca.crt

# -----------------------------------------------------------------------------
# Permissions (readable by Docker containers)
# -----------------------------------------------------------------------------
chmod 600 kes/certs/kes.key minio/certs/minio.key
chmod 644 kes/certs/*.crt minio/certs/*.crt minio/certs/CAs/*.crt

# -----------------------------------------------------------------------------
# Summary
# -----------------------------------------------------------------------------
echo ""
echo "🎉 Certificates generated successfully!"
echo ""
echo "  ├─ kes/certs/ca.crt ............ Shared CA"
echo "  ├─ kes/certs/kes.crt,key ....... KES server cert/key"
echo "  ├─ minio/certs/minio.crt,key ... MinIO client cert/key"
echo "  └─ minio/certs/CAs/kes_ca.crt .. CA trusted by MinIO"
echo ""
echo "✅ You can now start your stack with:  docker compose up"