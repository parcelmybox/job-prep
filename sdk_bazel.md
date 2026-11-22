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
