#!/usr/bin/env python3
"""Verify every vendored GK1 vector copy matches the canonical file byte-for-byte,
and that the sha256 recorded in README.md is current.

    python3 conformance/verify.py

Host python3, stdlib only. Needs only the golden-krill-sdk checkout (the vendored
copies all live inside this repo). Exits non-zero on any mismatch, so it doubles as
a CI gate.
"""
import hashlib
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, ".."))
CANON = os.path.join(HERE, "gk1_vectors.json")

# Every port that vendors a byte copy of the canonical vector. Add rn/unity/... here
# as those ports land.
VENDORED = [
    "flutter/test/gk1_vectors.json",
]


def sha(path):
    with open(path, "rb") as f:
        return hashlib.sha256(f.read()).hexdigest()


def recorded_sha():
    with open(os.path.join(HERE, "README.md"), encoding="utf-8") as f:
        m = re.search(r"\b([0-9a-f]{64})\b", f.read())
    return m.group(1) if m else None


def main():
    canon = sha(CANON)
    print(f"canonical {canon}  conformance/gk1_vectors.json")
    ok = True

    rec = recorded_sha()
    if rec != canon:
        print(f"FAIL      README.md records {rec}, expected {canon} (rerun generate_vectors.py / update README)")
        ok = False

    for rel in VENDORED:
        p = os.path.join(ROOT, rel)
        if not os.path.exists(p):
            print(f"MISSING   {rel}")
            ok = False
            continue
        h = sha(p)
        if h != canon:
            print(f"DIFF      {h}  {rel}")
            ok = False
        else:
            print(f"ok        {h}  {rel}")

    if not ok:
        print("FAIL: vendored copies / recorded hash are not all in sync with canonical")
        sys.exit(1)
    print("OK: canonical, README hash, and all vendored copies agree")


if __name__ == "__main__":
    main()
