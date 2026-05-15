#!/bin/bash
# ═══════════════════════════════════════════════════════════════
# SRIHER Display App - Chrome Launcher
# Starts the CORS proxy + Flutter app in Chrome automatically
# Usage: ./run_chrome.sh
# ═══════════════════════════════════════════════════════════════

cd "$(dirname "$0")"

echo "═══════════════════════════════════════════════════"
echo "  Starting CORS Proxy on port 8888..."
echo "═══════════════════════════════════════════════════"

# Start CORS proxy in background
dart run cors_proxy.dart &
PROXY_PID=$!

# Give proxy a moment to start
sleep 2

echo "═══════════════════════════════════════════════════"
echo "  Starting Flutter app in Chrome..."
echo "═══════════════════════════════════════════════════"

# Run Flutter on Chrome
flutter run -d chrome

# When Flutter exits, kill the proxy
echo "Shutting down CORS proxy..."
kill $PROXY_PID 2>/dev/null
echo "Done."
