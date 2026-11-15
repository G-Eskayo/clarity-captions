# MARVIN Site Actions Deploy Pattern

**Source:** [marvin#1122/PR #1126](https://github.com/G-Eskayo/marvin/pull/1126)

**What we took:** The build/deploy split pattern for GitHub Actions workflows: a separate `build` job that runs checks and creates an artifact, and a `deploy` job that only runs on push to main and deploys the artifact. The CNAME-from-config pattern: deriving the custom domain from a central ORIGIN constant, generating the CNAME file automatically, and managing the domain as code rather than a GitHub Pages setting.

**Confidence:** Ours — we built and shipped this pattern in the MARVIN project, so we understand its trade-offs and operation.

**Drives:** This ticket (#279) — automating Seal Speak's site deployment to GitHub Actions, with the custom domain managed as code.

**Public use:** Internal — this is a deployment pattern shared between two private and one public repo.
