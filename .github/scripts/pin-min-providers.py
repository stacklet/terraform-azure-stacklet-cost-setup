#!/usr/bin/env python3
"""Emit a Terraform override file pinning every provider to its declared minimum.

CI resolves the newest version that satisfies a constraint, so the floor a module
advertises is never exercised unless something forces it. This reads the `>= X`
lower bound out of each required_providers entry and pins that exact version, so
a second validate run proves the advertised floor still works.

The output belongs in an override file that CI generates and never commits:
committing it would pin consumers of this module to the floor as well.
"""

import re
import sys

BLOCK = re.compile(r"(\w+)\s*=\s*\{(.*?)\}", re.S)
SOURCE = re.compile(r'source\s*=\s*"([^"]+)"')
MINIMUM = re.compile(r'version\s*=\s*"[^"]*?>=\s*([0-9][^,"\s]*)')


def main() -> int:
    text = open(sys.argv[1] if len(sys.argv) > 1 else "provider.tf").read()
    required = re.search(r"required_providers\s*\{(.*)\n  \}", text, re.S)
    if not required:
        print("no required_providers block found", file=sys.stderr)
        return 1

    pinned = []
    for name, body in BLOCK.findall(required.group(1)):
        source, minimum = SOURCE.search(body), MINIMUM.search(body)
        if not source or not minimum:
            print(f"{name}: no source or no '>=' lower bound", file=sys.stderr)
            return 1
        pinned.append((name, source.group(1), minimum.group(1)))

    if not pinned:
        print("no providers parsed out of required_providers", file=sys.stderr)
        return 1

    print("terraform {")
    print("  required_providers {")
    for name, source, minimum in pinned:
        print(f"    {name} = {{")
        print(f'      source  = "{source}"')
        print(f'      version = "{minimum}"')
        print("    }")
    print("  }")
    print("}")

    for name, _, minimum in pinned:
        print(f"pinned {name} to {minimum}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
