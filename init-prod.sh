#!/bin/bash

set -e

echo "Starting ERPNext Production Setup..."

# Set environment variables with defaults
DB_HOST=${DB_HOST:-mariadb}
DB_PORT=${DB_PORT:-3306}
DB_NAME=${DB_NAME:-erpnext}
DB_USER=${DB_USER:-erpnext}
DB_PASSWORD=${DB_PASSWORD}
DB_ROOT_PASSWORD=${DB_ROOT_PASSWORD}
SITE_NAME=${SITE_NAME:-erpnext.local}
ADMIN_PASSWORD=${ADMIN_PASSWORD:-admin}
REDIS_CACHE_HOST=${REDIS_CACHE_HOST:-redis://redis:6379/0}
REDIS_QUEUE_HOST=${REDIS_QUEUE_HOST:-redis://redis:6379/1}
REDIS_SOCKETIO_HOST=${REDIS_SOCKETIO_HOST:-redis://redis:6379/2}

# Set up permissions if running as root
if [ "$(id -u)" = "0" ]; then
    echo "Setting up permissions..."
    mkdir -p /home/frappe/frappe-bench/logs
    mkdir -p /home/frappe/frappe-bench/sites
    mkdir -p /home/frappe/frappe-bench/sites/assets
    chown -R frappe:frappe /home/frappe/frappe-bench
    chmod -R 755 /home/frappe/frappe-bench
    
    # Switch to frappe user for the rest of the script
    exec gosu frappe "$0" "$@"
fi

# Wait for database to be ready
echo "Waiting for MariaDB to be ready..."
while ! mysqladmin ping -h"$DB_HOST" -P"$DB_PORT" -uroot -p"$DB_ROOT_PASSWORD" --silent; do
    echo "Waiting for MariaDB..."
    sleep 5
done

# Wait for Redis to be ready
echo "Waiting for Redis to be ready..."
while ! redis-cli -u "$REDIS_CACHE_HOST" ping > /dev/null 2>&1; do
    echo "Waiting for Redis..."
    sleep 2
done

# Set Node.js path
export PATH="${NVM_DIR}/versions/node/v${NODE_VERSION_DEVELOP}/bin/:${PATH}"

# Check if bench already exists and has proper configuration
if [ -d "/home/frappe/frappe-bench" ] && [ -f "/home/frappe/frappe-bench/sites/${SITE_NAME}/site_config.json" ]; then
    echo "Bench and site already exist, starting services..."
    cd /home/frappe/frappe-bench
    
    # Update Redis configuration to ensure it's correct
    bench set-redis-cache-host "$REDIS_CACHE_HOST"
    bench set-redis-queue-host "$REDIS_QUEUE_HOST"
    bench set-redis-socketio-host "$REDIS_SOCKETIO_HOST"
    
    # Set as default site
    bench use "$SITE_NAME"
else
    echo "Setting up bench instance..."
    cd /home/frappe
    
    # Check if bench exists but needs configuration
    if [ -d "frappe-bench" ]; then
        echo "Using existing bench directory..."
        cd frappe-bench
    else
        echo "Initializing new bench..."
        bench init --skip-redis-config-generation --python python3 frappe-bench
        cd frappe-bench
    fi
    
    # Configure database and Redis hosts
    bench set-mariadb-host "$DB_HOST"
    bench set-redis-cache-host "$REDIS_CACHE_HOST"
    bench set-redis-queue-host "$REDIS_QUEUE_HOST"
    bench set-redis-socketio-host "$REDIS_SOCKETIO_HOST"
    
    # Get required apps if they don't exist
    if [ ! -d "apps/erpnext" ]; then
        echo "Getting ERPNext app..."
        bench get-app erpnext
    fi
    
    if [ ! -d "apps/hrms" ]; then
        echo "Getting HRMS app..."
        bench get-app hrms
    fi
    
    # Create database user if it doesn't exist
    mysql -h"$DB_HOST" -P"$DB_PORT" -uroot -p"$DB_ROOT_PASSWORD" -e "CREATE USER IF NOT EXISTS '${DB_USER}'@'%' IDENTIFIED BY '${DB_PASSWORD}';"
    mysql -h"$DB_HOST" -P"$DB_PORT" -uroot -p"$DB_ROOT_PASSWORD" -e "GRANT ALL PRIVILEGES ON \`${DB_NAME}\`.* TO '${DB_USER}'@'%'; FLUSH PRIVILEGES;"
    
    # Create new site
    echo "Creating new site: $SITE_NAME"
    bench new-site "$SITE_NAME" \
        --force \
        --mariadb-root-password "$DB_ROOT_PASSWORD" \
        --admin-password "$ADMIN_PASSWORD" \
        --no-mariadb-socket \
        --db-name "$DB_NAME" \
        --db-user "$DB_USER" \
        --db-password "$DB_PASSWORD"
    
    # Install apps
    echo "Installing ERPNext..."
    bench --site "$SITE_NAME" install-app erpnext
    
    echo "Installing HRMS..."
    bench --site "$SITE_NAME" install-app hrms
    
    # Production configurations
    bench --site "$SITE_NAME" set-config developer_mode 0
    bench --site "$SITE_NAME" set-config allow_tests 0
    bench --site "$SITE_NAME" set-config server_script_enabled 0
    bench --site "$SITE_NAME" set-config disable_website_cache 0
    
    # Set encryption key if provided
    if [ ! -z "$ENCRYPTION_KEY" ]; then
        bench --site "$SITE_NAME" set-config encryption_key "$ENCRYPTION_KEY"
    fi
    
    # Enable scheduler
    bench --site "$SITE_NAME" enable-scheduler
    
    # Set as default site
    bench use "$SITE_NAME"
    
    # Build assets for production
    echo "Building assets for production..."
    bench build --production
    
    # Clear cache
    bench --site "$SITE_NAME" clear-cache
    bench --site "$SITE_NAME" clear-website-cache
fi

# Create production Procfile
cat > Procfile <<EOF
web: bench serve --port 8000
socketio: /home/frappe/.nvm/versions/node/v\${NODE_VERSION_DEVELOP}/bin/node apps/frappe/socketio.js
worker_short: bench worker --queue short
worker_default: bench worker --queue default  
worker_long: bench worker --queue long
schedule: bench schedule
EOF

echo "Starting ERPNext in production mode..."
exec bench start