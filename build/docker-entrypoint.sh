#!/bin/bash
set -e

# Redirect all output to stderr to avoid buffering issues in Docker logs
exec 2>&1

ZNUNY_HOME="${ZNUNY_HOME:-/opt/znuny}"
ZNUNY_DIST="/opt/znuny-dist"

# Copy Znuny installation to volume on first run
if [ ! -f "${ZNUNY_HOME}/bin/otrs.SetPermissions.pl" ]; then
    echo "First run detected - copying Znuny installation to volume..."
    if [ -d "$ZNUNY_DIST" ]; then
        cp -a "${ZNUNY_DIST}/." "${ZNUNY_HOME}/"
        echo "Znuny installation copied successfully"
    else
        echo "ERROR: Distribution directory ${ZNUNY_DIST} not found!"
        exit 1
    fi
fi

# Set permissions (ignore errors with /dev/stdout symlinks)
echo "Setting permissions..."
chown -R znuny:www-data ${ZNUNY_HOME}
chmod -R g+w ${ZNUNY_HOME}
${ZNUNY_HOME}/bin/otrs.SetPermissions.pl 2>&1 | grep -v "is encountered a second time" || true

# Run auto-installation if enabled
if [ "${ZNUNY_AUTO_INSTALL:-true}" = "true" ] && [ -n "$ZNUNY_DB_HOST" ]; then
    echo "Running Znuny auto-installation..."
    /usr/local/bin/autoinstall.sh
    
    echo "Checking for version upgrades..."
    /usr/local/bin/upgrade.sh
fi

# Setup cron jobs for znuny user
echo "Setting up Znuny cron jobs..."
su - znuny -c "${ZNUNY_HOME}/bin/Cron.sh start" || echo "Warning: Could not setup cron jobs"

# Execute the command (supervisord)
exec "$@" &
SUPERVISORD_PID=$!

# Wait for supervisord to start
sleep 2

# Start Znuny Daemon after autoinstall is complete
if [ -f "${ZNUNY_HOME}/Kernel/Config.pm" ]; then
    echo "Starting Znuny Daemon..."
    supervisorctl start znuny-daemon
fi

# Wait for supervisord process
wait $SUPERVISORD_PID
