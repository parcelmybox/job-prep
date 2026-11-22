# Bazel Split Transition Example: Multi-Platform Release Tarball

This project demonstrates a **Bazel 1:N Split Transition** (`transitions.bzl`) that compiles a single C++ target (`//:hello_world`) for **macOS arm64**, **Linux x86_64**, and **Linux arm64** simultaneously and packages all three executables into one release tarball (`hello_release.tar.gz`).

## How to Run on macOS

1. **Build the complete multi-architecture tarball in one command (no `--platforms` flag needed!):**
   ```bash
   bazel build //:hello_release
   ```

2. **Inspect the generated release tarball:**
   ```bash
   tar -tzvf bazel-bin/hello_release.tar.gz
   ```

3. **Extract and verify all three binaries with `file`:**
   ```bash
   mkdir -p /tmp/release_check
   tar -xzf bazel-bin/hello_release.tar.gz -C /tmp/release_check

   cat /tmp/release_check/MANIFEST.txt
   file /tmp/release_check/macos_arm64/hello_world
   file /tmp/release_check/linux_x86_64/hello_world
   file /tmp/release_check/linux_arm64/hello_world

   # Run the native macOS binary directly:
   /tmp/release_check/macos_arm64/hello_world
   ```
