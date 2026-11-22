# Bazel Transitions, Starlark Syntax, Packaging & Privilege Handling Answer Sheet

---

## 1. What is a Bazel Transition?

A **Bazel transition** (`transition(...)`) is a mechanism that dynamically changes build configuration flags (such as `--platforms`, `--cpu`, or `--compilation_mode`) for a specific target and its transitive dependencies **mid-build**, without requiring the user to pass CLI flags.

* **Why it exists:** Normally, an entire `bazel build` shares one global configuration. If you are building a multi-architecture product (e.g., an x86_64 host control-plane binary alongside an ARMv7e Broadcom switch ASIC driver), transitions allow a single `bazel build //:release_bundle` command to compile dependencies under **multiple target platforms simultaneously**.
* **Types of Transitions:**
  * **Incoming Edge Transition:** Attached to a `rule(cfg = ...)`—alters the configuration of the target itself when depended upon.
  * **Outgoing Edge Transition:** Attached to an attribute (`attr.label_list(cfg = ...)`), like in your `armv7e_filegroup` snippet—forces all targets passed into `deps` to build under the new platform (`armv7e`).

---

## 2. Line-by-Line Breakdown of Your `broadcom_sdk_modules.bzl` Snippets

### A. The Platform Transition (`_armv7e_platform_transition`)
```python
_armv7e_platform_transition = transition(
    implementation = _armv7e_platform_transition_impl,  # Starlark function returning {"//command_line_option:platforms": "//platforms:armv7e"}
    inputs = [],                                        # CLI flags read before changing config (empty = doesn't depend on current flags)
    outputs = ["//command_line_option:platforms"],      # CLI flags modified by this transition
)
```
* **What it does:** Intercepts dependency resolution and overrides `--platforms` to target the ARMv7e embedded Broadcom architecture.

### B. The Transitioned Filegroup Rule (`armv7e_filegroup`)
```python
def _transitioned_filegroup_impl(ctx):
    # Collects output artifacts from every target in `deps` (which were just compiled for armv7e)
    files = depset(transitive = [dep[DefaultInfo].files for dep in ctx.attr.deps])
    return [
        DefaultInfo(
            files = files,
            runfiles = ctx.runfiles(transitive_files = files),
        ),
    ]

armv7e_filegroup = rule(
    implementation = _transitioned_filegroup_impl,
    attrs = {
        # `cfg = _armv7e_platform_transition` applies the ARMv7e platform switch to everything in `deps`
        "deps": attr.label_list(cfg = _armv7e_platform_transition),
        # Required Bazel security allowlist attribute whenever a custom rule uses a Starlark transition
        "_allowlist_function_transition": attr.label(
            default = "@bazel_tools//tools/allowlists/function_transition_allowlist",
        ),
    },
)
```
* **Why `glob = native.glob` is in `.bzl`:** In `BUILD` files, `glob()` is available globally. Inside `.bzl` files, built-in `BUILD` functions are hidden under the `native` module, so `glob = native.glob` exposes it to macros defined in that `.bzl` file.

# Bazel Multi-Platform Transitions, Release Optimization & CI Query Validation Guide

---

## 1. `hello_cross` vs. `hello_transition_release`: Architectural Comparison

| Dimension | `hello_cross` (CLI-Driven Cross-Compilation) | `hello_transition_release` (Starlark Split Transition) |
| :--- | :--- | :--- |
| **How Target Platform is Chosen** | Externally via CLI flag (`--platforms=//:linux_x86_64`). | Internally inside `transitions.bzl` (`transition(...)` overrides `--platforms` automatically). |
| **Builds per `bazel build` Call** | **1 architecture** per command invocation. | **3 architectures simultaneously** (`macos_arm64`, `linux_x86_64`, `linux_arm64`) in a single build graph. |
| **Starlark Mechanism** | Standard `rule(...)` reading `ctx.file.target_bin` in the host/target config. | **1:N Split Transition** attached to `attr.label(cfg = _multi_platform_transition)` and read via `ctx.split_attr.binary`. |
| **Security Allowlist Needed?** | No. | Yes—requires `_allowlist_function_transition` attribute on the `release_bundle` rule. |
| **Output Artifact** | Single executable (`bazel-bin/hello_world`) + text report (`hello_format_report.txt`). | Single multi-architecture release archive (`bazel-bin/hello_release.tar.gz`) containing all 3 binaries + `MANIFEST.txt`. |
| **Best Use Case** | Fast local iteration & debugging on a single target board/OS. | CI/CD release pipelines, multi-arch packaging, and SDK/appliance distribution. |

---

## 2. Enforcing `--compilation_mode=opt` Inside `_multi_platform_transition_impl`

In production release pipelines, you don't want engineers or CI runners to forget `-c opt` (`--compilation_mode=opt`). You can lock release optimization flags directly into your Starlark transition so every split branch compiles with `-O2`/`-DNDEBUG` automatically—even if the user runs a plain `bazel build //:hello_release`.

### Updated `transitions.bzl` Snippet
```python
def _multi_platform_transition_impl(settings, attr):
    """1:N Split Transition with enforced Release Optimization (-c opt).
    Overrides BOTH `--platforms` and `--compilation_mode` for every target
    entering through `release_bundle(binary = ...)`.
    """
    return {
        "macos_arm64": {
            "//command_line_option:platforms": str(attr.macos_platform),
            "//command_line_option:compilation_mode": "opt",
        },
        "linux_x86_64": {
            "//command_line_option:platforms": str(attr.linux_x86_64_platform),
            "//command_line_option:compilation_mode": "opt",
        },
        "linux_arm64": {
            "//command_line_option:platforms": str(attr.linux_arm64_platform),
            "//command_line_option:compilation_mode": "opt",
        },
    }

_multi_platform_transition = transition(
    implementation = _multi_platform_transition_impl,
    inputs = [],
    # Every flag returned in the dictionary MUST be listed in `outputs`
    outputs = [
        "//command_line_option:platforms",
        "//command_line_option:compilation_mode",
    ],
)
```
* **Key Rule:** Any `"//command_line_option:<flag>"` modified in the return dictionary **must** be explicitly declared in the `outputs = [...]` list of `transition(...)`, or Bazel will fail during the Analysis Phase.

---

## 3. CI Validation Process Using `query`, `cquery`, and `aquery` Based on Changesets

When a Pull Request arrives, your CI orchestrator inspects `git diff --name-only` and uses the right query layer depending on **what changed**:

### Scenario A: Source Code / Header Change (`platform_info.cpp` or `.h`)
**Goal:** Find all impacted test targets and check whether the multi-platform release bundle is affected.
* **Tool:** `bazel query` (fast Loading Phase graph traversal).
```bash
# 1. Find all tests impacted by the changed C++ file (excluding manual hardware tests)
bazel query 'kind(".*_test", rdeps(//..., //:platform_info.cpp)) - attr(tags, "manual", //...)'

# 2. Check if the release tarball target is impacted by this change
bazel query 'rdeps(//:hello_release, //:platform_info.cpp)'
```

---

### Scenario B: New Hardware / Platform or `select()` Change (`BUILD.bazel` / `platforms/`)
**Goal:** Verify that the 1:N split transition forks into all expected configurations and resolves the right platform-specific dependencies without actually compiling yet.
* **Tool:** `bazel cquery` (evaluates `select()`, transitions, and `--platforms`).
```bash
# 1. Verify `hello_release` forks `:hello_world` into 3 distinct configuration hashes
bazel cquery 'deps(//:hello_release)' | grep '//:hello_world'
# Expected output shows 3 distinct config hashes, e.g.:
# //:hello_world (a1b2c3d)
# //:hello_world (e4f5g6h)
# //:hello_world (9i0j1k2)

# 2. Inspect exact output artifact paths per transitioned platform
bazel cquery 'deps(//:hello_release)' --output=files | grep 'hello_world$'
```

---

### Scenario C: SDK Version Bump or Compiler Flag / Transition Change (`MODULE.bazel` / `transitions.bzl`)
**Goal:** Audit the exact compiler flags (`-O2`, `-DNDEBUG`, target triples, sysroot paths) and linker flags across each transitioned architecture **before** running expensive hardware-in-the-loop (HIL) tests.
* **Tool:** `bazel aquery` (inspects the Action Graph command lines).
```bash
# 1. Verify that `--compilation_mode=opt` (-O2 / -DNDEBUG) was applied to CppCompile actions
bazel aquery 'mnemonic("CppCompile", deps(//:hello_release))' \

  | grep -E '(Command Line:|TARGET_CPU|-O2|-DNDEBUG|--target=)'

# 2. Verify the exact packaging command & inputs for the final release tarball
bazel aquery 'mnemonic("PackageReleaseTarball", //:hello_release)'
```

---

### Summary CI Decision Matrix

| Changeset Trigger | Query Tool | CI Validation Action |
| :--- | :--- | :--- |
| **Docs / `.md` only** | None (`git diff`) | Skip Bazel entirely; run markdown/spell linter. |
| **`.cpp` / `.h` edit** | `bazel query` | Run `rdeps` to test only impacted `*_test` targets. |
| **`BUILD.bazel` / `platforms/` edit** | `bazel cquery` | Verify `select()` branches and transition configuration splits resolve cleanly. |
| **`MODULE.bazel` / `transitions.bzl` / SDK bump** | `bazel aquery` | Audit exact compiler/linker flags (`-O2`, target triples) and run full `bazel build //:hello_release`. |


### C. RPM Packaging Snippet (`rpms.cp`)
```python
rpms.cp(
    src = "//platform/dc3/stats_client/nx:libstatcl_nx.so",  # Bazel target output artifact to copy
    dest = "/lc/isan/lib/libstatcl_nx.so",                    # Destination path inside the generated RPM filesystem
    file_attr = file_attrs.new(
        owner = "root",                                       # Metadata recorded in RPM header (no root needed at build time!)
        perm = 755,                                           # File permissions (rwxr-xr-x) recorded in RPM cpio archive
    ),
)
```
* **Key insight:** `rpms.cp` writes file ownership (`root`) and permissions (`755`) purely as **archive metadata** inside the `.rpm` header—it does **not** actually `chown` files on the build host.

---

## 3. When Do We Use `()`, `{}`, and `[]` in Starlark / Bazel?

| Symbol | Starlark Type | When to Use It | Bazel Examples |
| :--- | :--- | :--- | :--- |
| **`()`** | **Function / Rule Call** or **Tuple** | 1. Calling rules, macros, or functions.<br>2. Grouping multi-line boolean expressions or immutable tuples. | `cc_library(name = "foo")`<br>`transition(implementation = ...)`<br>`file_attrs.new(owner = "root")` |
| **`[]`** | **List** | Ordered collections of items—used for attributes expecting multiple values (`srcs`, `deps`, `copts`, `outputs`) and list comprehensions. | `srcs = ["a.cpp", "b.cpp"]`<br>`outputs = ["//command_line_option:platforms"]`<br>`[dep[DefaultInfo].files for dep in ...]` |
| **`{}`** | **Dictionary (`dict`)** | Key-value mappings—used for rule `attrs` definitions, `select()` condition branches, `env` variables, and transition return values. | `attrs = {"deps": attr.label_list(...)}`<br>`select({":arm": [...], "//conditions:default": [...]})`<br>`{"//command_line_option:platforms": "//:armv7e"}` |

load("@rules_cc//cc:defs.bzl", "cc_binary", "cc_library")

# ==============================================================================
# 1. DEFINE CONFIG_SETTING CONDITIONS
#    A `config_setting` acts as a named boolean condition that `select()` can match.
# ==============================================================================

# Condition A: Matches when target OS is Linux AND CPU is ARM64
config_setting(
    name = "is_linux_arm64",
    constraint_values = [
        "@platforms//os:linux",
        "@platforms//cpu:aarch64",
    ],
)

# Condition B: Matches when building in release optimization mode (`-c opt`)
config_setting(
    name = "is_opt_build",
    values = {
        "compilation_mode": "opt",
    },
)

# ==============================================================================
# 2. USE `select()` IN `cc_library`
#    Note: You can match directly against `@platforms//os:linux` OR a custom
#    `config_setting` like `:is_linux_arm64`.
# ==============================================================================
cc_library(
    name = "hardware_driver",
    hdrs = ["driver.h"],

    # 1. Choose platform-specific source files via `select()`
    srcs = select({
        "@platforms//os:linux": ["driver_linux.cpp"],
        "@platforms//os:macos": ["driver_macos.cpp"],
        # Always include `//conditions:default` as a fallback so builds don't fail
        # on unexpected platforms (e.g., Windows or BSD).
        "//conditions:default": ["driver_stub.cpp"],
    }),

    # 2. Combine common flags (`[...]`) with conditional flags (`+ select({...})`)
    copts = [
        "-std=c++20",
        "-Wall",
    ] + select({
        ":is_opt_build": ["-O3", "-DNDEBUG"],
        "//conditions:default": ["-O0", "-g"],
    }),

    # 3. Inject preprocessor macros (`-D...`) based on CPU architecture
    defines = select({
        ":is_linux_arm64": ["ARCH_ARM64_EMBEDDED=1"],
        "@platforms//cpu:x86_64": ["ARCH_X86_64=1"],
        "//conditions:default": ["ARCH_GENERIC=1"],
    }),

    # 4. Conditionally link platform-specific libraries
    linkopts = select({
        "@platforms//os:linux": ["-lpthread", "-ldl"],
        "@platforms//os:macos": ["-framework", "CoreFoundation"],
        "//conditions:default": [],
    }),
)

cc_binary(
    name = "app",
    srcs = ["main.cpp"],
    deps = [":hardware_driver"],
)

---

## 4. What Are `tags` in Bazel?

`tags = [...]` is a universal list-of-strings attribute supported on **every** Bazel rule (`cc_library`, `cc_test`, `genrule`, etc.) used to attach metadata that alters how Bazel executes, caches, or queries a target.

### Common Built-In Bazel Tags

| Tag | Effect on Bazel Execution |
| :--- | :--- |
| **`"manual"`** | Excludes the target from wildcard builds (`bazel build //...` or `bazel test //...`). It only builds when explicitly named or depended upon (ideal for hardware-only tests or cross-compiled targets). |
| **`"no-sandbox"`** | Runs the action directly on the host filesystem without Linux/macOS sandboxing (used when legacy vendor SDKs hardcode absolute paths). |
| **`"no-remote"`** / **`"local"`** | Forces the action to execute locally on the worker and prevents Remote Build Execution (RBE) or remote caching. |
| **`"no-cache"`** | Disables both local and remote caching for the action (forces re-execution every time). |
| **`"requires-network"`** | Grants network access inside the sandbox (by default, Bazel blocks internet access during build/test actions). |
| **`"exclusive"`** | Runs a test target by itself with no other tests running concurrently on the same machine (used for hardware/port-binding tests). |

---

## 5. `BUILD` vs. `BUILD.bazel` vs. `defs.bzl`

| File Name | Role | Rules & Restrictions |
| :--- | :--- | :--- |
| **`BUILD` / `BUILD.bazel`** | **Package Definition File** | Marks a directory as a Bazel package and instantiates targets (`cc_library`, `armv7e_filegroup`). **Cannot** define `def` functions, `for` loops, or `if` statements (use `select()` instead).<br>*Note:* `BUILD.bazel` takes precedence over `BUILD` if both exist (preferred on macOS/Windows case-insensitive filesystems where a folder named `build/` would collide with `BUILD`). |
| **`defs.bzl`** *(or any `*.bzl`)* | **Starlark Extension File** | Contains programming logic: custom `rule()` definitions, macros (`def ...`), transitions, and constants. Never directly builds anything until loaded into a `BUILD.bazel` file via `load(":defs.bzl", ...)`. |

---

## 6. How to Handle Commands Requiring Limited Privileges or `sudo` Access

Bazel runs actions inside an **unprivileged sandbox** as a non-root user—calling `sudo` inside a `genrule` or `ctx.actions.run` will fail (and breaks hermeticity/RBE). Use these four standard patterns instead:

1. **Packaging / Ownership (`chown` / `chmod` for `.rpm`, `.deb`, `.tar`):**
   * **Never** use `sudo chown root:root` in a build action.
   * Use declarative packaging rules like **`rules_pkg`** (`pkg_tar`, `pkg_rpm`) or your `rpms.cp(..., file_attr = file_attrs.new(owner = "root", perm = 755))`. These set `uid=0`/`gid=0` metadata directly in the archive header as an unprivileged user.
2. **Filesystem / Loopback / Rootfs Image Creation (`mkfs`, `mount`):**
   * **Never** run `sudo mount -o loop` during a build.
   * Use userspace image builders such as **`genext2fs`**, **`mke2fs -d <dir>`** (populates ext4 images from a directory without root), **`guestfish`**, or **`fakeroot`** (`fakeroot tar ...`) inside `ctx.actions.run`.
3. **Privileged Integration Tests (e.g., Network Namespaces, Hardware Devices, Kernel Modules):**
   * Separate **building** (unprivileged) from **test execution**.
   * Tag the test with `tags = ["local", "requires-root", "exclusive"]` and run it only on dedicated self-hosted CI runners configured with passwordless `sudo` for that specific test runner wrapper, or run inside a privileged container in CI (`docker run --privileged ...`).
4. **Vendor SDK Installers Trying to Write to `/opt` or `/usr`:**
   * If a legacy Broadcom/vendor installer expects root to write into `/opt/sdk`, wrap it in a repository rule or `genrule` using **`fakeroot`** + `--prefix=\$OUT_DIR` (or `chroot`/`proot`) so all writes stay inside Bazel's output directory.
