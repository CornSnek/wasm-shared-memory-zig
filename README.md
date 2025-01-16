# Testing Shared Memory with WebAssembly (compiled with Zig 0.13.0)
The purpose of this project was to test WebAssembly shared memory functionality and SharedArrayBuffer functionality.

Functions/Modules used:

- Atomics module from Javascript and atomics opcodes in Zig to Wasm
- Exporting enums defined in Zig to be exported to Javascript (In an output file "wasm_enums.js")
- Using Workers to read/write data from the shared WebAssembly memory object.

## Zig Build
This project currently uses Zig 0.13.0 to build the project.

In order to build the website and/or the wasm binary: `zig build wasm -Doptimize=...`

Python 3 is also used to build the server with the appropriate headers (COOP and COEP) to test the website: `zig build server`

## Bugs
- Using \@trap() in the Wasm file doesn't sync printing correctly before calling \@trap().
Refreshing the page shows the messages sometimes.
It's probably best to just print/log synchronously without using Threads/Workers.

## Projects used

- **coi-serviceworker** (https://github.com/gzuidhof/coi-serviceworker) was added to this project to enable COOP and COEP headers for Github Pages. This is required for SharedArrayBuffer functionality to work.