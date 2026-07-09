#!/bin/bash
# Znuny Auto-Installation Script
# Automatically installs Znuny based on environment variables

set -e

ZNUNY_HOME="${ZNUNY_HOME:-/opt/znuny}"
CONFIG_FILE="${ZNUNY_HOME}/Kernel/Config.pm"
INSTALLED_FLAG="${ZNUNY_HOME}/var/.znuny_installed"
VERSION_FILE="${ZNUNY_HOME}/var/.znuny_version"
CURRENT_VERSION="${ZNUNY_VERSION}"

# Logging function - outputs to stdout immediately without buffering
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [AUTOINSTALL] $1" >&2
}

log_error() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [AUTOINSTALL] ERROR: $1" >&2
}

# Check if already installed
if [ -f "$INSTALLED_FLAG" ]; then
    log "Znuny already installed. Skipping auto-installation."
    exit 0
fi

log "=== Starting Znuny Auto-Installation ==="

# Validate required environment variables
if [ -z "$ZNUNY_DB_HOST" ] || [ -z "$ZNUNY_DB_NAME" ] || [ -z "$ZNUNY_DB_USER" ] || [ -z "$ZNUNY_DB_PASSWORD" ]; then
    log_error "Missing required database environment variables"
    log_error "Required: ZNUNY_DB_HOST, ZNUNY_DB_NAME, ZNUNY_DB_USER, ZNUNY_DB_PASSWORD"
    exit 1
fi

# Set defaults
DB_TYPE="${ZNUNY_DB_TYPE:-mysql}"
DB_HOST="${ZNUNY_DB_HOST}"
DB_NAME="${ZNUNY_DB_NAME}"
DB_USER="${ZNUNY_DB_USER}"
DB_PASSWORD="${ZNUNY_DB_PASSWORD}"
ZNUNY_ROOT_PASSWORD="${ZNUNY_ROOT_PASSWORD:-rot}"
SYSTEM_ID="${ZNUNY_SYSTEM_ID:-10}"
FQDN="${ZNUNY_FQDN:-localhost}"
ADMIN_EMAIL="${ZNUNY_ADMIN_EMAIL:-root@localhost}"
ORGANIZATION="${ZNUNY_ORGANIZATION:-Example Company}"

if [ "$DB_TYPE" = "postgresql" ]; then
    DB_PORT="${ZNUNY_DB_PORT:-5432}"
    DB_DSN="DBI:Pg:dbname=${DB_NAME};host=${DB_HOST};port=${DB_PORT};"
    DB_TYPE_NAME="postgresql"
else
    DB_PORT="${ZNUNY_DB_PORT:-3306}"
    DB_DSN="DBI:mysql:database=${DB_NAME};host=${DB_HOST};port=${DB_PORT};"
    DB_TYPE_NAME="mysql"
fi

log "Configuration:"
log "  Database Type: $DB_TYPE"
log "  Database Host: $DB_HOST:$DB_PORT"
log "  Database Name: $DB_NAME"
log "  Database User: $DB_USER"
log "  FQDN: $FQDN"
log "  System ID: $SYSTEM_ID"

# Wait for database to be ready
log "Waiting for database to be ready..."

# Wait for database connection to be ready
# Note: In Docker Swarm overlay networks, DNS works but getent/nslookup may fail
# We test actual connection instead of DNS resolution
MAX_RETRIES=60
RETRY_COUNT=0

while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
    if [ "$DB_TYPE" = "postgresql" ]; then
        ERROR_OUTPUT=$(PGPASSWORD="$DB_PASSWORD" psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d postgres -c '\q' 2>&1)
        RESULT=$?
        if [ $RESULT -eq 0 ]; then
            log "PostgreSQL is ready"
            break
        else
            log "Connection failed: $ERROR_OUTPUT"
        fi
    else
        ERROR_OUTPUT=$(mysqladmin ping -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" --password="$DB_PASSWORD" --silent 2>&1)
        RESULT=$?
        if [ $RESULT -eq 0 ]; then
            log "MySQL is ready"
            break
        else
            log "Connection failed: $ERROR_OUTPUT"
        fi
    fi
    
    RETRY_COUNT=$((RETRY_COUNT + 1))
    if [ $RETRY_COUNT -eq $MAX_RETRIES ]; then
        log_error "Database is not ready after $MAX_RETRIES attempts ($(($MAX_RETRIES * 2 / 60)) minutes)"
        log_error "Last error: $ERROR_OUTPUT"
        log_error "Check: 1) Database service is running, 2) Network connectivity, 3) Credentials match"
        exit 1
    fi
    log "Database not ready, attempt $RETRY_COUNT/$MAX_RETRIES - waiting 2s..."
    sleep 2
done

# Check if database already has Znuny schema
log "Checking if database schema exists..."
if [ "$DB_TYPE" = "postgresql" ]; then
    TABLE_COUNT=$(PGPASSWORD=$DB_PASSWORD psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -t -c "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='public' AND table_name='users';" 2>/dev/null | xargs)
else
    TABLE_COUNT=$(mysql -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" -p"$DB_PASSWORD" "$DB_NAME" -sN -e "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='$DB_NAME' AND table_name='users';" 2>/dev/null)
fi

if [ "$TABLE_COUNT" != "0" ]; then
    log "Database schema already exists (users table found)"
    SCHEMA_EXISTS=true
else
    log "Database is empty, will install schema"
    SCHEMA_EXISTS=false
fi

# Create minimal Kernel/Config.pm
log "Creating minimal Kernel/Config.pm..."

# Ensure the directory exists
mkdir -p "$(dirname "$CONFIG_FILE")"

cat > "$CONFIG_FILE" <<EOF
# OTRS config file (automatically created by auto-installer)
# VERSION:2.0
package Kernel::Config;

use strict;
use warnings;
use utf8;

sub Load {
    my \$Self = shift;

    # ---------------------------------------------------- #
    # database settings                                     #
    # ---------------------------------------------------- #
    \$Self->{DatabaseHost} = '$DB_HOST';
    \$Self->{Database} = '$DB_NAME';
    \$Self->{DatabaseUser} = '$DB_USER';
    \$Self->{DatabasePw} = '$DB_PASSWORD';
    \$Self->{DatabaseDSN} = '$DB_DSN';

    # ---------------------------------------------------- #
    # fs root directory
    # ---------------------------------------------------- #
    \$Self->{Home} = '$ZNUNY_HOME';

    # ---------------------------------------------------- #
    # system data (minimal required)
    # ---------------------------------------------------- #
    \$Self->{SystemID} = '$SYSTEM_ID';

    return 1;
}

# ---------------------------------------------------- #
# needed system stuff (don't edit this)               #
# ---------------------------------------------------- #

use Kernel::Config::Defaults; # import Translatable()
use parent qw(Kernel::Config::Defaults);

# -----------------------------------------------------#

1;
EOF

chown znuny:www-data "$CONFIG_FILE"
chmod 660 "$CONFIG_FILE"

log "Minimal Kernel/Config.pm created successfully"

# Install database schema if needed
if [ "$SCHEMA_EXISTS" = false ]; then
    log "Installing database schema..."
    
    if [ "$DB_TYPE" = "postgresql" ]; then
        log "Installing PostgreSQL schema..."
        if PGPASSWORD=$DB_PASSWORD psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" < "${ZNUNY_HOME}/scripts/database/schema.postgresql.sql" 2>&1; then
            log "PostgreSQL schema installed successfully"
        else
            log_error "Failed to install PostgreSQL schema"
            exit 1
        fi
        
        log "Inserting initial data..."
        if PGPASSWORD=$DB_PASSWORD psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" < "${ZNUNY_HOME}/scripts/database/initial_insert.postgresql.sql" 2>&1; then
            log "Initial data inserted successfully"
        else
            log_error "Failed to insert initial data"
            exit 1
        fi
        
        log "Applying schema post-processing (FK constraints)..."
        if PGPASSWORD=$DB_PASSWORD psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" < "${ZNUNY_HOME}/scripts/database/schema-post.postgresql.sql" 2>&1; then
            log "Schema post-processing completed"
        else
            log_error "Failed to apply schema post-processing"
            exit 1
        fi
    else
        log "Installing MySQL schema..."
        if mysql -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" -p"$DB_PASSWORD" "$DB_NAME" < "${ZNUNY_HOME}/scripts/database/schema.mysql.sql" 2>&1; then
            log "MySQL schema installed successfully"
        else
            log_error "Failed to install MySQL schema"
            exit 1
        fi
        
        log "Inserting initial data..."
        if mysql -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" -p"$DB_PASSWORD" "$DB_NAME" < "${ZNUNY_HOME}/scripts/database/initial_insert.mysql.sql" 2>&1; then
            log "Initial data inserted successfully"
        else
            log_error "Failed to insert initial data"
            exit 1
        fi
        
        log "Applying schema post-processing (FK constraints)..."
        if mysql -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" -p"$DB_PASSWORD" "$DB_NAME" < "${ZNUNY_HOME}/scripts/database/schema-post.mysql.sql" 2>&1; then
            log "Schema post-processing completed"
        else
            log_error "Failed to apply schema post-processing"
            exit 1
        fi
    fi
else
    log "Skipping schema installation (already exists)"
fi

# Set root@localhost password using SQL
log "Setting root@localhost password to: $ZNUNY_ROOT_PASSWORD..."

# Generate Znuny-compatible password hash using Perl
PASSWORD_HASH=$(su - znuny -c "perl -e 'use Digest::SHA; print Digest::SHA::sha256_hex(\"$ZNUNY_ROOT_PASSWORD\");'" 2>/dev/null)

if [ -z "$PASSWORD_HASH" ]; then
    log_error "Failed to generate password hash"
    PASSWORD_HASH="roK20XGbWEsSM"  # fallback to 'root' password
    log "Warning: Using default password hash (root)"
fi

log "Generated password hash: $PASSWORD_HASH"

# Update password in database
if [ "$DB_TYPE" = "postgresql" ]; then
    if PGPASSWORD=$DB_PASSWORD psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -c "UPDATE users SET pw = '$PASSWORD_HASH' WHERE login = 'root@localhost';" 2>&1; then
        log "root@localhost password updated successfully"
    else
        log "Warning: Failed to update root@localhost password"
    fi
else
    if mysql -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" -p"$DB_PASSWORD" "$DB_NAME" -e "UPDATE users SET pw = '$PASSWORD_HASH' WHERE login = 'root@localhost';" 2>&1; then
        log "root@localhost password updated successfully"
    else
        log "Warning: Failed to update root@localhost password"
    fi
fi

# Rebuild config
log "Rebuilding configuration..."
if su - znuny -c "${ZNUNY_HOME}/bin/otrs.Console.pl Maint::Config::Rebuild" 2>&1; then
    log "Configuration rebuilt successfully"
else
    log "Warning: Failed to rebuild configuration"
fi

# Configure system settings via Console
log "Configuring system settings via Console..."

# Set FQDN
if su - znuny -c "${ZNUNY_HOME}/bin/otrs.Console.pl Admin::Config::Update --setting-name FQDN --value '$FQDN'" 2>&1; then
    log "FQDN set to: $FQDN"
else
    log "Warning: Failed to set FQDN"
fi

# Set AdminEmail
if su - znuny -c "${ZNUNY_HOME}/bin/otrs.Console.pl Admin::Config::Update --setting-name AdminEmail --value '$ADMIN_EMAIL'" 2>&1; then
    log "AdminEmail set to: $ADMIN_EMAIL"
else
    log "Warning: Failed to set AdminEmail"
fi

# Set Organization
if su - znuny -c "${ZNUNY_HOME}/bin/otrs.Console.pl Admin::Config::Update --setting-name Organization --value '$ORGANIZATION'" 2>&1; then
    log "Organization set to: $ORGANIZATION"
else
    log "Warning: Failed to set Organization"
fi

# Set SecureMode
if su - znuny -c "${ZNUNY_HOME}/bin/otrs.Console.pl Admin::Config::Update --setting-name SecureMode --value 1" 2>&1; then
    log "SecureMode enabled"
else
    log "Warning: Failed to enable SecureMode"
fi

# Set LogModule to File (store logs in /opt/znuny/var/log)
if su - znuny -c "${ZNUNY_HOME}/bin/otrs.Console.pl Admin::Config::Update --setting-name LogModule --value 'Kernel::System::Log::File'" 2>&1; then
    log "LogModule set to File"
else
    log "Warning: Failed to set LogModule"
fi

# Set log file location
if su - znuny -c "${ZNUNY_HOME}/bin/otrs.Console.pl Admin::Config::Update --setting-name 'LogModule::LogFile' --value '${ZNUNY_HOME}/var/log/znuny.log'" 2>&1; then
    log "Log file location set to: ${ZNUNY_HOME}/var/log/znuny.log"
else
    log "Warning: Failed to set log file location"
fi

# Set Article storage to filesystem
if su - znuny -c "${ZNUNY_HOME}/bin/otrs.Console.pl Admin::Config::Update --setting-name 'Ticket::Article::Backend::MIMEBase::ArticleStorage' --value 'Kernel::System::Ticket::Article::Backend::MIMEBase::ArticleStorageFS'" 2>&1; then
    log "Article storage set to filesystem"
else
    log "Warning: Failed to set article storage"
fi

# Delete cache
log "Deleting cache..."
if su - znuny -c "${ZNUNY_HOME}/bin/otrs.Console.pl Maint::Cache::Delete" 2>&1; then
    log "Cache deleted successfully"
else
    log "Warning: Failed to delete cache"
fi

# Create installed flag
touch "$INSTALLED_FLAG"
chown znuny:www-data "$INSTALLED_FLAG"

# Save installed version
log "Saving installed version: $CURRENT_VERSION"
echo "$CURRENT_VERSION" > "$VERSION_FILE"
chown znuny:www-data "$VERSION_FILE"

log "=== Znuny Auto-Installation Completed Successfully ==="
log "You can now access Znuny at http://${FQDN}/"
log "Default credentials: root@localhost / ${ZNUNY_ROOT_PASSWORD}"
log ""

exit 0
