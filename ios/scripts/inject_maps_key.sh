#!/bin/sh
# Writes the Google Maps API key into the built app's Info.plist.
#
# Why this exists rather than a $(MAPS_API_KEY) placeholder in Info.plist:
# the flavoured build configurations (Debug-dev, Release-prod, ...) use the
# CocoaPods xcconfig as their base configuration, not Flutter/Debug.xcconfig.
# A variable defined in Debug.xcconfig therefore never reaches a flavoured
# build, and the placeholder expands to nothing. Injecting after the build
# sidesteps the whole xcconfig inheritance question.
#
# The key lives in ios/Flutter/Maps.xcconfig, which git ignores.
set -e

MAPS_FILE="${SRCROOT}/Flutter/Maps.xcconfig"
BUILT_PLIST="${BUILT_PRODUCTS_DIR}/${INFOPLIST_PATH}"

if [ ! -f "$MAPS_FILE" ]; then
  echo "warning: ios/Flutter/Maps.xcconfig is missing - the Map tab will crash on open. See MAP_SETUP.md"
  exit 0
fi

MAPS_KEY=$(grep -E '^[[:space:]]*MAPS_API_KEY[[:space:]]*=' "$MAPS_FILE" | head -1 | sed 's/.*=//' | tr -d '[:space:]')

if [ -z "$MAPS_KEY" ]; then
  echo "warning: MAPS_API_KEY is empty in Maps.xcconfig - the Map tab will crash on open. See MAP_SETUP.md"
  exit 0
fi

/usr/libexec/PlistBuddy -c "Set :MapsApiKey $MAPS_KEY" "$BUILT_PLIST" 2>/dev/null \
  || /usr/libexec/PlistBuddy -c "Add :MapsApiKey string $MAPS_KEY" "$BUILT_PLIST"

echo "Google Maps key injected into $BUILT_PLIST"
