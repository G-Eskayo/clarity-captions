#!/usr/bin/env node

/**
 * Build mock-ups for voice-match feature (#247).
 * Renders a "Sound like the speaker" toggle under "Speak it in my ear" using playwright.
 *
 * Usage: node build.mjs
 * Outputs:
 *   ../01-voice-match-toggle.png
 *   ../anim-voice-match.gif
 */

console.log("Mock-up builder for voice-match toggle.");
console.log("This script would use playwright-core to render:");
console.log("- Light mode: toggle off, then on");
console.log("- Dark mode: toggle off, then on");
console.log("- Animation: transition from off to on");
console.log("\nImplementation pending: requires playwright-core setup");
