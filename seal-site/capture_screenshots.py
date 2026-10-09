#!/usr/bin/env python3
"""
Capture responsive screenshots of the Seal marketing site.
Requires: playwright (pip install playwright)

Usage:
  1. Start a local HTTP server in seal-site/:
     cd seal-site && python3 -m http.server 8000

  2. In another terminal, run this script:
     python3 capture_screenshots.py
"""
import asyncio
import sys
from pathlib import Path


async def capture_screenshots():
    """Capture screenshots at mobile and desktop widths."""
    try:
        from playwright.async_api import async_playwright
    except ImportError:
        print("Error: playwright not installed. Run: pip install playwright")
        sys.exit(1)

    screenshots_dir = Path(__file__).parent / "screenshots"
    screenshots_dir.mkdir(exist_ok=True)

    async with async_playwright() as p:
        browser = await p.chromium.launch()

        # Mobile viewport (iPhone 390px)
        context_mobile = await browser.new_context(
            viewport={"width": 390, "height": 844},
            device_scale_factor=2
        )
        page_mobile = await context_mobile.new_page()

        # Desktop viewport (1440px)
        context_desktop = await browser.new_context(
            viewport={"width": 1440, "height": 900},
            device_scale_factor=1
        )
        page_desktop = await context_desktop.new_page()

        url = "http://localhost:8000"

        try:
            print(f"Loading {url}...")

            # Mobile screenshot
            print("📱 Capturing mobile screenshot (390×844)...")
            await page_mobile.goto(url, wait_until="networkidle")
            await page_mobile.screenshot(path=str(screenshots_dir / "seal-site-mobile-390.png"))
            print(f"   ✓ Saved: screenshots/seal-site-mobile-390.png")

            # Mobile full page
            page_mobile_full = await context_mobile.new_page()
            await page_mobile_full.goto(url, wait_until="networkidle")
            await page_mobile_full.screenshot(
                path=str(screenshots_dir / "seal-site-mobile-fullpage.png"),
                full_page=True
            )
            print(f"   ✓ Saved: screenshots/seal-site-mobile-fullpage.png")

            # Desktop screenshot
            print("🖥️  Capturing desktop screenshot (1440×900)...")
            await page_desktop.goto(url, wait_until="networkidle")
            await page_desktop.screenshot(path=str(screenshots_dir / "seal-site-desktop-1440.png"))
            print(f"   ✓ Saved: screenshots/seal-site-desktop-1440.png")

            # Desktop full page
            page_desktop_full = await context_desktop.new_page()
            await page_desktop_full.goto(url, wait_until="networkidle")
            await page_desktop_full.screenshot(
                path=str(screenshots_dir / "seal-site-desktop-fullpage.png"),
                full_page=True
            )
            print(f"   ✓ Saved: screenshots/seal-site-desktop-fullpage.png")

            print("\n✅ Screenshots captured successfully!")

        except Exception as e:
            print(f"❌ Error capturing screenshots: {e}")
            return False

        finally:
            await browser.close()

    return True


async def main():
    """Main entry point."""
    success = await capture_screenshots()
    sys.exit(0 if success else 1)


if __name__ == "__main__":
    asyncio.run(main())
