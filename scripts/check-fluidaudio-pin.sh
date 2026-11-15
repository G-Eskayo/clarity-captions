#!/bin/bash
# Verify FluidAudio pin consistency across packages and at build time.
#
# Always runs: checks that every Package.swift that uses FluidAudio pins the same version (static check),
# and that every Package.resolved that exists agrees with the pinned version.
#
# Optional --app-resolved mode (called by CI after xcodebuild succeeds):
#   scripts/check-fluidaudio-pin.sh --app-resolved <path> --app-name <name>
#
# Finds workspace-state.json (DerivedData) and verifies the build resolved the pinned version.
# Failure messages always include: "own PR, scored by the #273 replay".
set -eu

# ANSI color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

# Allow ROOT to be overridden for testing
ROOT="${SCRIPT_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
cd "$ROOT"

# Parse static pins from Package.swift files (requires exact: pinning)
# Exits 0 with version on stdout if exact: pin found
# Exits 1 with error on stderr if FluidAudio found but not pinned with exact:
# Exits 2 silently if no FluidAudio dependency at all
get_static_pin() {
    local file="$1"
    python3 -I - "$file" <<'PY'
import sys, re
with open(sys.argv[1]) as f:
    content = f.read()
# Check if FluidAudio appears at all
if 'FluidAudio' not in content:
    sys.exit(2)
# If it does appear, it must use exact: pinning
pin_match = re.search(r'FluidAudio\.git["\']?,\s*exact:\s*["\']([0-9.]+)["\']', content)
if pin_match:
    print(pin_match.group(1))
    sys.exit(0)
# FluidAudio found but not with exact:
sys.stderr.write(f"FluidAudio found in {sys.argv[1]} but not pinned with exact:\n")
sys.exit(1)
PY
}

# Parse resolved pins from Package.resolved (supports both old and new Xcode formats)
# Exits 0 with version on stdout if FluidAudio pin found
# Exits 1 with error on stderr if parse error (malformed JSON, missing fields)
# Exits 2 silently if no FluidAudio pin found
get_resolved_pin() {
    local file="$1"
    python3 -I - "$file" <<'PY'
import json, sys
try:
    d = json.load(open(sys.argv[1]))
    # Handle both formats: v1 (with "pins" key) and v2 (with "object.dependencies")
    pins = d.get("pins")
    if pins:
        # v1 format: pins is an array directly
        for p in pins:
            if (p.get("identity") or p.get("package", "")).lower() == "fluidaudio":
                version = p.get("state", {}).get("version")
                if not version:
                    sys.stderr.write(f"parse error: FluidAudio entry missing state.version in {sys.argv[1]}\n")
                    sys.exit(1)
                print(version)
                sys.exit(0)
    else:
        # v2 format: pins are under object.dependencies
        deps = d.get("object", {}).get("dependencies", [])
        for dep in deps:
            identity = dep.get("packageRef", {}).get("identity", "").lower()
            if "fluidaudio" in identity:
                version = dep.get("state", {}).get("checkoutState", {}).get("version")
                if not version:
                    sys.stderr.write(f"parse error: FluidAudio entry missing state.checkoutState.version in {sys.argv[1]}\n")
                    sys.exit(1)
                print(version)
                sys.exit(0)
    # No FluidAudio found
    sys.exit(2)
except json.JSONDecodeError as e:
    sys.stderr.write(f"parse error: malformed JSON in {sys.argv[1]}: {e}\n")
    sys.exit(1)
except Exception as e:
    sys.stderr.write(f"parse error: unexpected error in {sys.argv[1]}: {e}\n")
    sys.exit(1)
PY
}

static_pin=""
all_static_agree=true
while IFS= read -r package_swift; do
    [ -f "$package_swift" ] || continue
    # get_static_pin exits: 0 (pin found), 1 (FluidAudio without exact:), 2 (no FluidAudio)
    pin=$(get_static_pin "$package_swift" 2>&1)
    status=$?

    if [ "$status" -eq 2 ]; then
        # No FluidAudio in this package, skip
        continue
    elif [ "$status" -eq 1 ]; then
        # FluidAudio found but not pinned with exact:
        echo -e "${RED}error: FluidAudio in $package_swift must use exact: pinning${NC}"
        echo "  $pin"
        echo "  own PR, scored by the #273 replay"
        all_static_agree=false
        continue
    fi

    # status == 0, pin has the version
    if [ -z "$static_pin" ]; then
        static_pin="$pin"
    elif [ "$pin" != "$static_pin" ]; then
        echo -e "${RED}error: FluidAudio pin mismatch${NC}"
        echo "  $package_swift pins $pin, but $static_pin is the required pin"
        echo "  own PR, scored by the #273 replay"
        all_static_agree=false
    fi
done < <(find Packages -name Package.swift)

if [ "$all_static_agree" = false ]; then
    exit 1
fi

if [ -z "$static_pin" ]; then
    echo -e "${RED}error: no FluidAudio pin found in any Package.swift${NC}"
    echo "  own PR, scored by the #273 replay"
    exit 1
fi

# Verify Package.resolved files (when they exist) match the static pin
resolved_agree=true
while IFS= read -r package_resolved; do
    [ -f "$package_resolved" ] || continue
    # get_resolved_pin exits: 0 (pin found), 1 (parse error), 2 (no FluidAudio)
    resolved_pin=$(get_resolved_pin "$package_resolved" 2>&1)
    status=$?

    if [ "$status" -eq 2 ]; then
        # No FluidAudio pin in this resolved file, OK
        continue
    elif [ "$status" -eq 1 ]; then
        # Parse error
        echo -e "${RED}error: could not parse $package_resolved${NC}"
        echo "  $resolved_pin"
        echo "  own PR, scored by the #273 replay"
        resolved_agree=false
        continue
    fi

    # status == 0, resolved_pin has the version
    if [ "$resolved_pin" != "$static_pin" ]; then
        echo -e "${RED}error: FluidAudio resolved version mismatch${NC}"
        echo "  $package_resolved resolved $resolved_pin, but Package.swift pins $static_pin"
        echo "  own PR, scored by the #273 replay"
        resolved_agree=false
    fi
done < <(find Packages -name Package.resolved)

if [ "$resolved_agree" = false ]; then
    exit 1
fi

echo -e "${GREEN}✓ static check: all packages pin FluidAudio $static_pin${NC}"

# Optional: check app-resolved at build time
app_resolved=""
app_name=""
app_resolved_given=false
app_name_given=false
while [ $# -gt 0 ]; do
    case "$1" in
        --app-resolved) app_resolved="$2"; app_resolved_given=true; shift 2 ;;
        --app-name) app_name="$2"; app_name_given=true; shift 2 ;;
        *) echo "unknown option: $1" >&2; exit 2 ;;
    esac
done

if [ "$app_resolved_given" = true ] && [ "$app_name_given" = true ]; then
    if [ -z "$app_resolved" ] || [ ! -f "$app_resolved" ]; then
        echo -e "${RED}error: workspace-state.json path not found or empty (${app_name})${NC}"
        echo "  expected path: $app_resolved"
        echo "  own PR, scored by the #273 replay"
        exit 1
    fi

    resolved_pin=$(get_resolved_pin "$app_resolved" 2>&1)
    status=$?

    if [ "$status" -eq 2 ]; then
        echo -e "${RED}error: FluidAudio not found in $app_resolved (${app_name})${NC}"
        echo "  own PR, scored by the #273 replay"
        exit 1
    elif [ "$status" -eq 1 ]; then
        echo -e "${RED}error: could not parse $app_resolved (${app_name})${NC}"
        echo "  $resolved_pin"
        echo "  own PR, scored by the #273 replay"
        exit 1
    fi

    if [ "$resolved_pin" != "$static_pin" ]; then
        echo -e "${RED}error: app-resolved mismatch (${app_name})${NC}"
        echo "  Package.swift pins $static_pin, but $app_resolved resolved $resolved_pin"
        echo "  own PR, scored by the #273 replay"
        exit 1
    fi

    echo -e "${GREEN}✓ build check ($app_name): resolved FluidAudio $resolved_pin (matches pin)${NC}"
fi

# Note about transitive dependencies
echo -e "${YELLOW}note: FluidAudio's own transitive dependencies are not separately pinned by this check${NC}"
exit 0
