#!/usr/bin/env python3
"""Generate favicon and app icon files for the Seal marketing site from the 1024px source."""
from PIL import Image
import os

src_icon = "design/icon/seal-icon-1024.png"
assets_dir = "site/assets"

# Ensure assets directory exists
os.makedirs(assets_dir, exist_ok=True)

# Open the source image
img = Image.open(src_icon)

# Generate sizes
sizes = {
    "seal-icon-128.png": (128, 128),
    "favicon-32.png": (32, 32),
    "favicon-192.png": (192, 192),
}

for filename, size in sizes.items():
    resized = img.resize(size, Image.Resampling.LANCZOS)
    output_path = os.path.join(assets_dir, filename)
    resized.save(output_path)
    print(f"Generated {output_path}")

print("Done!")
