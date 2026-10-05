#!/bin/bash
# Setup script to copy icon files to BrandMark imageset.
# Run this once after cloning or before building.

set -e

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
ICON_DIR="$SCRIPT_DIR/Apps/Spike/Sources/Assets.xcassets/AppIcon.appiconset"
BRAND_DIR="$SCRIPT_DIR/Apps/Spike/Sources/Assets.xcassets/BrandMark.imageset"

if [ ! -f "$ICON_DIR/icon-light.png" ]; then
    echo "Error: icon-light.png not found at $ICON_DIR"
    exit 1
fi

if [ ! -f "$ICON_DIR/icon-dark.png" ]; then
    echo "Error: icon-dark.png not found at $ICON_DIR"
    exit 1
fi

echo "Copying icon files to BrandMark imageset..."
cp "$ICON_DIR/icon-light.png" "$BRAND_DIR/icon-light.png"
cp "$ICON_DIR/icon-dark.png" "$BRAND_DIR/icon-dark.png"

echo "✓ Brand assets set up successfully"
