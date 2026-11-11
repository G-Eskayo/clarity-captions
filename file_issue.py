#!/usr/bin/env python3
import subprocess
import json
import sys

def run_gh(*args):
    """Run a gh command and return the result."""
    cmd = ['gh'] + list(args)
    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0:
        print(f"Error: {result.stderr}", file=sys.stderr)
        return None
    return result.stdout

def main():
    # Create the GitHub issue
    print("Creating GitHub issue...")
    with open('issue_body.md', 'r') as f:
        body = f.read()

    result = subprocess.run([
        'gh', 'issue', 'create',
        '--repo', 'G-Eskayo/clarity-captions',
        '--title', 'Spec: From/Into behavior in every case (#256 + #252)',
        '--label', 'needs-info,feature:translation',
        '--body', body
    ], capture_output=True, text=True)

    if result.returncode != 0:
        print(f"Failed to create issue: {result.stderr}", file=sys.stderr)
        sys.exit(1)

    # Extract the issue number from the output
    output = result.stdout.strip()
    # Output is like "https://github.com/G-Eskayo/clarity-captions/issues/XXXX"
    issue_num = output.split('/')[-1]
    print(f"Created issue #{issue_num}")
    print(f"URL: {output}")

    # Reply to PR #256 with decisions-addressed marker
    print("\nReplying to PR #256...")
    reply_body = f"""<!-- marvin:decisions-addressed -->

This decision (`spec`) has been acted on: spec documented as a separate ticket #{ issue_num } for your approval.

No Swift code changed (this decision produces a GitHub issue for your approval, not app behavior). No test run or screenshot capture needed.

Linked: #{ issue_num } (the spec ticket), #252 (parent: From/Into behavior), #251 (readiness design).
"""

    result = subprocess.run([
        'gh', 'pr', 'comment',
        '256',
        '--repo', 'G-Eskayo/clarity-captions',
        '--body', reply_body
    ], capture_output=True, text=True)

    if result.returncode != 0:
        print(f"Failed to comment on PR: {result.stderr}", file=sys.stderr)
        sys.exit(1)

    print("Reply posted to PR #256")
    print(f"\nSummary:")
    print(f"- New issue filed: #{issue_num}")
    print(f"- PR #256 comment posted")

if __name__ == '__main__':
    main()
