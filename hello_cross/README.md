# Bazel macOS-to-Linux C++ Cross-Compilation Example

## Quick Start on macOS

1. Install Bazelisk:
   ```bash
   brew install bazelisk
   ```

2. Run natively on macOS:
   ```bash
   bazel run //:hello_world
   ```

3. Cross-compile for Linux x86_64:
   ```bash
   bazel build --platforms=//:linux_x86_64 //:hello_world //:hello_format
   cat bazel-bin/hello_format_report.txt
   ```

4. Cross-compile for Linux ARM64:
   ```bash
   bazel build --platforms=//:linux_arm64 //:hello_world //:hello_format
   cat bazel-bin/hello_format_report.txt
   ```
