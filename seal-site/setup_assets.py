#!/usr/bin/env python3
"""
Set up assets for the Seal website by copying approved icons from design/icon/.
Run this once before deploying the site.
"""
import shutil
import os
from pathlib import Path

def setup_assets():
    """Copy required assets from design/icon/ to assets/."""
    assets_dir = Path(__file__).parent / "assets"
    assets_dir.mkdir(exist_ok=True)

    # Copy the main icon
    source_icon = Path(__file__).parent.parent / "design" / "icon" / "seal-icon-1024.png"
    dest_icon = assets_dir / "seal-icon.png"

    if source_icon.exists():
        shutil.copy2(source_icon, dest_icon)
        print(f"✓ Copied {source_icon.name} to assets/seal-icon.png")
    else:
        print(f"✗ Error: {source_icon} not found")
        return False

    # Copy dark variant (optional)
    source_dark = Path(__file__).parent.parent / "design" / "icon" / "seal-icon-1024-dark.png"
    dest_dark = assets_dir / "seal-icon-dark.png"

    if source_dark.exists():
        shutil.copy2(source_dark, dest_dark)
        print(f"✓ Copied seal-icon-1024-dark.png to assets/seal-icon-dark.png")

    # List assets
    print(f"\nAssets in {assets_dir}:")
    for item in sorted(assets_dir.iterdir()):
        if item.is_file():
            size_mb = item.stat().st_size / (1024 * 1024)
            print(f"  {item.name}: {size_mb:.2f} MB")

    return True

if __name__ == "__main__":
    import sys
    success = setup_assets()
    sys.exit(0 if success else 1)
