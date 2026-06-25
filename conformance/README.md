# GK1 conformance vectors

`gk1_vectors.json` is the single, language-neutral anti-drift contract for the GK1
wire codec. Dart, TypeScript, C#, Swift, Kotlin and the Python backend must all
encode and decode these vectors identically. If two ports disagree on a byte, one
of them is wrong.

## Canonical sha256

```
8064704da42255c923cd0a041f2b9eff265a9339e059bbc997354e43ed81cbe6  gk1_vectors.json
```

Every vendored copy must hash to exactly this. Each port's conformance test asserts
it, and `verify.py` re-checks it across the repo.

## What GK1 is

Obfuscation plus a stable, versioned envelope. NOT encryption (HTTPS does transit
security; host-pinned URLs stop tap redirects). The codec only keeps payloads from
sitting as clear-text JSON at a URL and versions the format so it can evolve.

```
blob = "GK1." + base64url( XOR(utf8(json), key) )
key  = "pink-rorqual//golden-krill//v1"   (UTF-8, cycled over the bytes)
XOR is its own inverse, so one routine both encodes and decodes.
base64url INCLUDES "=" padding.
```

GK1 is **frozen / eternal**: its layout never changes and the server serves it for
as long as any shipped binary is in the field. New layouts get a new tag (GK2, ...);
the `GK1` tag is never repurposed. So these vectors are effectively immutable.

## Why canonical + vendored copies + a checksum

Every port's toolchain container mounts only that port's package dir, and the SDK
and the `golden-krill` backend are **separate repos**, so a port cannot read this sibling
`conformance/` dir at test time. Therefore each port **vendors a byte copy** of
`gk1_vectors.json` into its own test tree.

Vendoring alone would lose the single source of truth (a port could vendor a copy
that matches its own bug, or someone could hand-edit a copy to turn a red test
green). So the copy is **guarded by the canonical sha256 above**: each port's test
fails loudly if its copy's hash does not match.

## Authority + regeneration

The canonical file is **generated from the authoritative server codec**
`golden-krill/web/apps/catalog/gk1.py`, so it agrees with the server by construction:

```
python3 conformance/generate_vectors.py     # writes gk1_vectors.json, prints sha256
```

(Host python3, stdlib only. Set `GK1_CODEC=/path/to/gk1.py` if your checkout is not
the sibling `mobile/{golden-krill,golden-krill-sdk}` layout.) After regenerating (only ever
needed if the case list changes, never the frozen codec): update the sha256 above,
re-vendor the per-port copies, and run `verify.py`.

## Using it in a port

Each port vendors a copy and, for every case, asserts:

1. `decode(case.gk1) == case.json`  (byte-exact string)
2. `encode(case.json) == case.gk1`  (byte-exact string)
3. `parse(decode(case.gk1)) == case.decoded`  (struct-level)
4. `sha256(vendored copy) == canonical sha256`  (anti-tamper / anti-drift)

Vendored copies:

- Flutter: `flutter/test/gk1_vectors.json` (read by `flutter/test/gk1_conformance_test.dart`).
- React Native, Unity, Swift, Kotlin: copy alongside their codec tests the same way.

## verify.py

`python3 conformance/verify.py` recomputes the canonical sha256 and diffs every
known vendored copy against canonical, exiting non-zero on any mismatch. Run it in
CI (or locally) whenever the SDK repo is checked out; it needs no other repo.
