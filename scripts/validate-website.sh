#!/bin/bash
# Validate the Seal landing page for structure, accessibility, and correctness.
# Run from the repo root: scripts/validate-website.sh

set -e

SITE_DIR="website"
ERRORS=0
WARNINGS=0

# Color output
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

echo "Validating Seal landing page..."

if [ ! -f "$SITE_DIR/index.html" ]; then
  echo -e "${RED}✗ Error: $SITE_DIR/index.html not found${NC}"
  exit 1
fi

# Check for required HTML structure
echo ""
echo "Checking HTML structure..."

# Must have exactly one <h1>
h1_count=$(grep -o '<h1' "$SITE_DIR/index.html" | wc -l)
if [ "$h1_count" -ne 1 ]; then
  echo -e "${RED}✗ Error: Expected 1 <h1>, found $h1_count${NC}"
  ((ERRORS++))
fi

# Must have <header>, <main>, <footer>
for tag in header main footer; do
  if ! grep -q "<$tag" "$SITE_DIR/index.html"; then
    echo -e "${RED}✗ Error: Missing <$tag> tag${NC}"
    ((ERRORS++))
  fi
done

# Must have at least one <section>
if ! grep -q '<section' "$SITE_DIR/index.html"; then
  echo -e "${RED}✗ Error: No <section> tags found${NC}"
  ((ERRORS++))
fi

echo -e "${GREEN}✓ HTML structure OK${NC}"

# Check for missing alt text
echo ""
echo "Checking alt text on images..."

# Extract all img tags and check for alt attribute
img_count=$(grep -o '<img' "$SITE_DIR/index.html" | wc -l)
alt_count=$(grep -o '<img[^>]*alt="[^"]*"' "$SITE_DIR/index.html" | wc -l)

if [ "$img_count" -ne "$alt_count" ]; then
  echo -e "${RED}✗ Error: $((img_count - alt_count)) image(s) missing alt text${NC}"
  echo "Images without alt:"
  grep '<img' "$SITE_DIR/index.html" | grep -v 'alt="' || true
  ((ERRORS++))
else
  echo -e "${GREEN}✓ All $img_count image(s) have alt text${NC}"
fi

# Check for empty alt text (alt="" is usually a mistake)
if grep -q 'alt=""' "$SITE_DIR/index.html"; then
  echo -e "${YELLOW}⚠ Warning: Empty alt text found (alt=\"\"). These should describe the image or be omitted for decorative images.${NC}"
  ((WARNINGS++))
fi

# Check for accessible heading hierarchy (no h2 before h1, etc.)
echo ""
echo "Checking heading hierarchy..."

# Extract all heading tags in order
headings=$(grep -oE '<h[1-6]' "$SITE_DIR/index.html")
prev_level=0
hierarchy_ok=1

while IFS= read -r heading; do
  level="${heading:2:1}"
  # Allow h1 at start, and h-level <= prev_level + 1 for valid hierarchy
  if [ "$prev_level" -gt 0 ] && [ "$level" -gt "$((prev_level + 1))" ]; then
    echo -e "${YELLOW}⚠ Warning: Heading hierarchy issue: $heading (expected h$prev_level or h$((prev_level + 1)) next)${NC}"
    ((WARNINGS++))
    hierarchy_ok=0
  fi
  prev_level="$level"
done <<< "$headings"

if [ "$hierarchy_ok" -eq 1 ]; then
  echo -e "${GREEN}✓ Heading hierarchy OK${NC}"
fi

# Check for basic link integrity (internal anchors)
echo ""
echo "Checking link integrity..."

# Extract all href="#something" and verify anchor exists
links=$(grep -oE 'href="#[^"]*"' "$SITE_DIR/index.html" | grep -v 'href="#' | sort -u)
broken_anchors=0

while IFS= read -r link; do
  anchor="${link#href=\"#}"
  anchor="${anchor%\"}"

  # Skip common "coming soon" or placeholder anchors
  if [ "$anchor" = "testflight" ] || [ "$anchor" = "app-store" ] || [ "$anchor" = "privacy" ] || [ "$anchor" = "support" ]; then
    continue
  fi

  if ! grep -q "id=\"$anchor\"" "$SITE_DIR/index.html"; then
    echo -e "${YELLOW}⚠ Warning: Anchor #$anchor not found in page${NC}"
    ((WARNINGS++))
    ((broken_anchors++))
  fi
done <<< "$links"

if [ "$broken_anchors" -eq 0 ]; then
  echo -e "${GREEN}✓ Internal link anchors OK (note: TestFlight, App Store, privacy, and support links are placeholders)${NC}"
fi

# Check for CSS file
echo ""
echo "Checking assets..."

if [ ! -f "$SITE_DIR/styles.css" ]; then
  echo -e "${YELLOW}⚠ Warning: $SITE_DIR/styles.css not found${NC}"
  ((WARNINGS++))
else
  echo -e "${GREEN}✓ styles.css found${NC}"
fi

# Check for doctype
if ! grep -q '<!DOCTYPE html>' "$SITE_DIR/index.html"; then
  echo -e "${RED}✗ Error: Missing <!DOCTYPE html> declaration${NC}"
  ((ERRORS++))
fi

# Check for meta charset
if ! grep -q '<meta charset="UTF-8">' "$SITE_DIR/index.html"; then
  echo -e "${RED}✗ Error: Missing <meta charset=\"UTF-8\">; ensure UTF-8 encoding${NC}"
  ((ERRORS++))
fi

# Check for viewport meta tag (mobile responsiveness)
if ! grep -q '<meta name="viewport"' "$SITE_DIR/index.html"; then
  echo -e "${RED}✗ Error: Missing <meta name=\"viewport\"> tag; mobile responsiveness required${NC}"
  ((ERRORS++))
else
  echo -e "${GREEN}✓ Viewport meta tag present${NC}"
fi

# Check for lang attribute on html tag
if ! grep -q '<html lang=' "$SITE_DIR/index.html"; then
  echo -e "${YELLOW}⚠ Warning: Missing lang attribute on <html> tag${NC}"
  ((WARNINGS++))
fi

# Summary
echo ""
echo "========================================"
if [ "$ERRORS" -eq 0 ]; then
  echo -e "${GREEN}✓ Validation passed${NC}"
  if [ "$WARNINGS" -eq 0 ]; then
    echo "No warnings."
  else
    echo -e "${YELLOW}$WARNINGS warning(s) found; see above.${NC}"
  fi
  exit 0
else
  echo -e "${RED}✗ Validation failed: $ERRORS error(s), $WARNINGS warning(s)${NC}"
  exit 1
fi
