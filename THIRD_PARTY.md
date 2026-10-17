# Attribution

The domain code in this repository was implemented for this project with AI coding assistance. Shared JSON-value/CLI scaffolding is used across the October projects; it is infrastructure rather than nine independent domain algorithms.

## Design references

- [https://ninja-build.org/manual.html](https://ninja-build.org/manual.html) — build model reference: declared inputs and outputs, dependency-ordered execution, output verification before reuse.
- [https://nodejs.org/api/child_process.html](https://nodejs.org/api/child_process.html) — process spawning, timeouts and signals in the executor.
- [https://nodejs.org/api/crypto.html](https://nodejs.org/api/crypto.html) — SHA-256 digests of declared files, programs and environment values in the executor.
- [https://csrc.nist.gov/publications/detail/fips/180/4/final](https://csrc.nist.gov/publications/detail/fips/180/4/final) — FIPS 180-4, the specification followed by the package's own SHA-256 implementation (`sha256.mbt`), verified against its test vectors and Python's `hashlib`.

References inform formats and algorithms; they are not claims of interoperability with every feature of the referenced systems. MoonBit core is a toolchain dependency. Python standard-library and Node built-in APIs are used by the executor, scenario runners and test oracles; no third-party packages are required. Scenario inputs and tool scripts under `examples/` and generated oracle data are synthetic. No prior September project implementation was copied into this domain core.
