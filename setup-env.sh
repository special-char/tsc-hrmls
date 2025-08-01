#!/bin/bash

echo "Setting up ERPNext Production Environment Variables..."

# Generate secure passwords
DB_ROOT_PASSWORD=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-25)
DB_PASSWORD=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-25)
ADMIN_PASSWORD=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-25)
ENCRYPTION_KEY=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-32)

# Create .env file
cat > .env <<EOF
# Database Configuration
DB_ROOT_PASSWORD=${DB_ROOT_PASSWORD}
DB_NAME=erpnext
DB_USER=erpnext
DB_PASSWORD=${DB_PASSWORD}

# Site Configuration
SITE_NAME=erpnext.local
ADMIN_PASSWORD=${ADMIN_PASSWORD}

# Security
ENCRYPTION_KEY=${ENCRYPTION_KEY}

# Port Configuration
APP_PORT=8000
SOCKETIO_PORT=9000
NGINX_PORT=80
NGINX_SSL_PORT=443
EOF

echo "Environment file created: .env"
echo "Please review and modify the .env file if needed before running docker-compose"
echo ""
echo "Generated passwords:"
echo "DB_ROOT_PASSWORD: ${DB_ROOT_PASSWORD}"
echo "DB_PASSWORD: ${DB_PASSWORD}"
echo "ADMIN_PASSWORD: ${ADMIN_PASSWORD}"
echo "ENCRYPTION_KEY: ${ENCRYPTION_KEY}"
echo ""
echo "To start the production environment:"
echo "docker-compose -f docker-compose.prod.yml up -d" 