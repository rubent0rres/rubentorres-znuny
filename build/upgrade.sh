#!/bin/bash
# Znuny Upgrade Script
# Automatically upgrades Znuny when container version changes

set -e

ZNUNY_HOME="${ZNUNY_HOME:-/opt/znuny}"
VERSION_FILE="${ZNUNY_HOME}/var/.znuny_version"
INSTALLED_FLAG="${ZNUNY_HOME}/var/.znuny_installed"
CURRENT_VERSION="${ZNUNY_VERSION}"

# Logging function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [UPGRADE] $1" >&2
}

log_error() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [UPGRADE] ERROR: $1" >&2
}

# Check if Znuny is installed
if [ ! -f "$INSTALLED_FLAG" ]; then
    log "Znuny is not installed yet. Skipping upgrade check."
    exit 0
fi

# Check if version file exists
if [ ! -f "$VERSION_FILE" ]; then
    log "Version file not found. Assuming upgrade is needed to $CURRENT_VERSION"
    INSTALLED_VERSION="unknown"
else
    # Read installed version
    INSTALLED_VERSION=$(cat "$VERSION_FILE")
fi

log "Installed version: $INSTALLED_VERSION"
log "Container version: $CURRENT_VERSION"

# Compare versions
if [ "$INSTALLED_VERSION" = "$CURRENT_VERSION" ]; then
    log "Versions match. No upgrade needed."
    exit 0
fi

log "=== Starting Znuny Upgrade from $INSTALLED_VERSION to $CURRENT_VERSION ==="

# Check if migration script exists for this version
MAJOR_MINOR=$(echo "$CURRENT_VERSION" | sed 's/\.[^.]*$//' | sed 's/\./\_/')
MIGRATION_SCRIPT="/opt/znuny-dist/scripts/MigrateToZnuny${MAJOR_MINOR}.pl"

if [ ! -f "$MIGRATION_SCRIPT" ]; then
    log_error "Migration script not found: $MIGRATION_SCRIPT"
    log_error "Manual migration may be required"
    exit 1
fi

log "Found migration script: $MIGRATION_SCRIPT"

# Sync new application files from dist, preserving user data
log "Syncing application files from /opt/znuny-dist/ to ${ZNUNY_HOME}..."
rsync -a --delete \
    --exclude='Kernel/Config.pm' \
    --exclude='Kernel/Config/' \
    --exclude='var/article/' \
    --exclude='var/log/' \
    --exclude='var/spool/' \
    --exclude='var/tmp/' \
    --exclude='var/.znuny_installed' \
    --exclude='var/.znuny_version' \
    --exclude='Custom/' \
    /opt/znuny-dist/ "${ZNUNY_HOME}/"
chown -R znuny:www-data "${ZNUNY_HOME}"
chmod -R go-w "${ZNUNY_HOME}"
find "${ZNUNY_HOME}" -type f -name "*.pl" -exec chmod +x {} \;
find "${ZNUNY_HOME}" -type f -name "*.sh" -exec chmod +x {} \;
log "Application files synced successfully"

# Backup database (optional warning)
log "WARNING: It's highly recommended to backup your database before upgrading!"
log "Proceeding with migration in 5 seconds... (Ctrl+C to cancel)"
sleep 5

# Stop Znuny Daemon
log "Stopping Znuny Daemon..."
if su - znuny -c "${ZNUNY_HOME}/bin/otrs.Console.pl Maint::Daemon::Stop --force" 2>&1; then
    log "Znuny Daemon stopped"
else
    log "Warning: Could not stop Znuny Daemon (may not be running)"
fi

# Run migration script
log "Running migration script: $MIGRATION_SCRIPT"
if su - znuny -c "cd ${ZNUNY_HOME} && perl -I ${ZNUNY_HOME} $MIGRATION_SCRIPT" 2>&1; then
    log "Migration completed successfully"
else
    log_error "Migration failed!"
    exit 1
fi

# Reinstall all packages
log "Reinstalling all packages..."
if su - znuny -c "${ZNUNY_HOME}/bin/otrs.Console.pl Admin::Package::ReinstallAll" 2>&1; then
    log "Packages reinstalled successfully"
else
    log "Warning: Failed to reinstall packages"
fi

# Rebuild configuration
log "Rebuilding configuration..."
if su - znuny -c "${ZNUNY_HOME}/bin/otrs.Console.pl Maint::Config::Rebuild" 2>&1; then
    log "Configuration rebuilt successfully"
else
    log "Warning: Failed to rebuild configuration"
fi

# Delete cache
log "Deleting cache..."
if su - znuny -c "${ZNUNY_HOME}/bin/otrs.Console.pl Maint::Cache::Delete" 2>&1; then
    log "Cache deleted successfully"
else
    log "Warning: Failed to delete cache"
fi

# Update version file
log "Updating version file to $CURRENT_VERSION"
echo "$CURRENT_VERSION" > "$VERSION_FILE"
chown znuny:www-data "$VERSION_FILE"

log "=== Znuny Upgrade Completed Successfully ==="
log "Upgraded from $INSTALLED_VERSION to $CURRENT_VERSION"
log ""

exit 0
