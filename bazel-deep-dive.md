## Deep Dive: `bazel query` vs. `bazel cquery` vs. `bazel aquery`

**`bazel query` inspects the unconfigured target graph (Loading Phase), `bazel cquery` inspects the configured target graph after evaluating `select()` and flags (Analysis Phase), and `bazel aquery` inspects the exact execution actions and command lines (Action Graph).**

---

### 1. Core Comparison

| Command | Build Phase | What It Sees | Speed | Primary Use Cases |
| :--- | :--- | :--- | :--- | :--- |
| **`bazel query`** | **Loading Phase** | Raw targets and dependencies as written in `BUILD` files (macros expanded, but `select()` and `--platforms` **not** evaluated). | Fastest | Finding reverse dependencies (`rdeps`), CI impact analysis, and visualizing target graphs. |
| **`bazel cquery`** | **Analysis Phase** | Configured targets after resolving `select()`, build flags (`--compilation_mode`), and target `--platforms`. | Medium | Debugging `select()` branches, checking which platform/toolchain a target resolved to, and finding actual transitive deps for a specific OS/CPU. |
| **`bazel aquery`** | **Analysis Phase (Action Graph)** | Exact actions (`CppCompile`, `CppLink`), compiler/linker flags, environment variables, and input/output file paths. | Slower | Comparing Make vs. Bazel compiler flags, debugging cache misses, and auditing sandbox inputs/outputs. |

---

### 2. When to Use Each (With CLI Examples)

#### A. `bazel query` — Target Graph & CI Impact Analysis
Use `query` when you care about **structural relationships** across your repository regardless of target OS or compiler flags.
* **Find everything impacted by a changed file (Dynamic CI pipelines):**
  ```bash
  bazel query 'rdeps(//..., //src/driver:sensor_hal.h)'
  ```
* **Find why target A depends on target B (shortest dependency path):**
  ```bash
  bazel query 'somepath(//:hello_world, @platforms//os:linux)'
  ```
* **Visualize dependencies between packages (Graphviz DOT format):**
  ```bash
  bazel query 'deps(//:hello_world)' --output graph
  ```
* **Caveat:** Because `select()` is not evaluated, `bazel query` shows **all** possible branches of a `select()` statement at once.

---

#### B. `bazel cquery` — Resolving `select()`, Flags & Cross-Compilation
Use `cquery` when a `BUILD` file uses `select()` or when cross-compiling (e.g., `--platforms=//:linux_x86_64`) and you need to know **which dependencies actually survived configuration**.
* **Check which branch of `select()` was chosen for Linux:**
  ```bash
  bazel cquery --platforms=//:linux_x86_64 'deps(//:hello_world)'
  ```
* **Inspect the exact output file paths generated for a specific platform:**
  ```bash
  bazel cquery --platforms=//:linux_x86_64 //:hello_world --output=files
  ```
* **Inspect providers or transitions on a configured target:**
  ```bash
  bazel cquery --platforms=//:linux_x86_64 //:hello_world --output=starlark --starlark:expr="providers(target)"
  ```

---

#### C. `bazel aquery` — Auditing Exact Compiler Commands & Cache Keys
Use `aquery` when debugging **Make-to-Bazel command alignment**, compiler flags, or why two builds produced different hashes.
* **Extract the exact `gcc`/`clang` command line used to compile a target:**
  ```bash
  bazel aquery --platforms=//:linux_x86_64 'mnemonic("CppCompile", //:greeter_lib)'
  ```
* **Extract the exact linker command line (`CppLink`):**
  ```bash
  bazel aquery --platforms=//:linux_x86_64 'mnemonic("CppLink", //:hello_world)'
  ```
* **Inspect inputs, outputs, and environment variables of a custom rule action:**
  ```bash
  bazel aquery 'mnemonic("InspectBinaryFormat", //:hello_format)'
  ```

---

### 3. Quick Decision Rule

* *"What targets depend on this file?"* → **`bazel query`**
* *"Which dependencies/sources were selected for ARM64 Linux?"* $\rightarrow$ **`bazel cquery`**
* *"What exact compiler flags and env vars ran during the build?"* $\rightarrow$ **`bazel aquery`**

* ## Deep Dive: Bazel Query Set Operations & Functions

Bazel's query language operates mathematically on **sets of targets**. You can combine target expressions using set operators and filter or traverse the build graph using built-in functions.

---

### 1. Set Operations

| Operator | Syntax | Meaning | Practical Example |
| :--- | :--- | :--- | :--- |
| **Union (`+` or `union`)** | `A + B` | All targets in `A` **or** `B`. | `bazel query '//app/... + //lib/...'` (Query multiple subtrees together) |
| **Intersection (`^` or `intersect`)** | `A ^ B` | Only targets present in **both** `A` and `B`. | `bazel query 'deps(//app:main) ^ //third_party/...'` (Which third-party deps does `main` actually use?) |
| **Difference (`-` or `except`)** | `A - B` | Targets in `A` that are **not** in `B`. | `bazel query '//app/... - //app/legacy/...'` (Everything in `app` except legacy code) |

---

### 2. Core Graph Traversal & Filtering Functions

#### A. Dependency Traversal (`deps`, `rdeps`, `somepath`, `allpaths`)

| Function | Signature | What It Returns | Example |
| :--- | :--- | :--- | :--- |
| **`deps`** | `deps(x, [depth])` | All transitive dependencies of `x` (downward). Optional `depth` limits hops (`1` = direct deps only). | `bazel query 'deps(//:hello_world, 1)'` |
| **`rdeps`** | `rdeps(universe, x, [depth])` | All targets inside `universe` that depend on `x` (upward). Crucial for CI impact analysis. | `bazel query 'rdeps(//..., //src/driver:hal.h)'` |
| **`somepath`** | `somepath(start, end)` | One dependency chain connecting `start` to `end` (fast way to ask *"Why do I depend on this?"*). | `bazel query 'somepath(//app:main, @openssl//:crypto)'` |
| **`allpaths`** | `allpaths(start, end)` | **Every** dependency path between `start` and `end`. | `bazel query 'allpaths(//app:main, //lib:core)'` |

---

#### B. Filtering by Rule Type, Label, or Attributes (`kind`, `filter`, `attr`)

| Function | Signature | What It Returns | Example |
| :--- | :--- | :--- | :--- |
| **`kind`** | `kind(pattern, set)` | Targets whose rule class (e.g., `cc_test`, `cc_binary`, `source file`) matches the regex `pattern`. | `bazel query 'kind("cc_test", rdeps(//..., //lib:math))'` *(Find all C++ tests affected by `math`)* |
| **`filter`** | `filter(pattern, set)` | Targets whose label string matches the regex `pattern`. | `bazel query 'filter("_test$", //src/...)'` |
| **`attr`** | `attr(name, pattern, set)` | Targets that have a specific attribute matching `pattern` (e.g., `tags`, `copts`, `linkstatic`). | `bazel query 'attr(tags, "manual", //...)'` *(Find all targets tagged `manual`)* |

---

#### C. Build File & Package Inspection (`buildfiles`, `siblings`)

| Function | Signature | What It Returns | Example |
| :--- | :--- | :--- | :--- |
| **`buildfiles`** | `buildfiles(set)` | All `BUILD` and `.bzl` files needed to define the targets in `set` (useful for caching/CI triggers). | `bazel query 'buildfiles(deps(//app:main))'` |
| **`siblings`** | `siblings(target)` | All other targets defined in the same `BUILD` file as `target`. | `bazel query 'siblings(//src/driver:sensor_hal)'` |

---

### 3. Real-World Combined Recipes (CI & Debugging)

1. **Dynamic CI: Run only non-manual tests impacted by a changed file**
   ```bash
   bazel query 'kind(".*_test", rdeps(//..., //src/driver:hal.cpp)) - attr(tags, "manual", //...)'
   ```

2. **Audit: Find all `.bzl` macro/rule files affecting a target**
   ```bash
   bazel query 'filter("\.bzl$", buildfiles(deps(//:hello_world)))'
   ```

3. **Dependency Cleanup: Find external repositories used by `//app:main` excluding test targets**
   ```bash
   bazel query 'deps(//app:main - kind(".*_test", //app/...)) ^ @*//...'
   ```

4. **Output Formatting Flags (Combine with any query above)**
   * `--output label_kind` → Prints rule type alongside target label (e.g., `cc_library rule //:greeter_lib`).
   * `--output build` → Prints the exact expanded `BUILD` definition after all macros have run (great for debugging macros!).
   * `--output graph` → Outputs Graphviz DOT syntax (`bazel query '...' --output graph | dot -Tpng > graph.png`).

## 1. Dynamic CI Script: `git diff` + `bazel query` Impacted Test Runner

Instead of running `bazel test //...` on every Pull Request, this script maps changed files to Bazel labels, traverses reverse dependencies (`rdeps`), excludes `manual` tests, and falls back safely if core workspace files change.

```bash
#!/usr/bin/env bash
set -euo pipefail

BASE_BRANCH="${1:-origin/main}"
MERGE_BASE=$(git merge-base "$BASE_BRANCH" HEAD)

# 1. Get all modified/added/deleted files relative to repo root
CHANGED_FILES=$(git diff --name-only "$MERGE_BASE"...HEAD)

if [[ -z "$CHANGED_FILES" ]]; then
    echo "No changed files detected. Skipping tests."
    exit 0
fi

echo "=== Changed Files ==="
echo "$CHANGED_FILES"

# 2. If global build configs changed, run full test suite
if echo "$CHANGED_FILES" | grep -qE '^(MODULE\.bazel|WORKSPACE|\.bazelrc|toolchains/)'; then
    echo "Global build configuration changed -> Running ALL tests"
    bazel test //...
    exit 0
fi

# 3. Map each changed file to its Bazel file label (e.g., src/foo.cpp -> //src:foo.cpp)
BAZEL_LABELS=()
while IFS= read -r file; do
    # Skip non-existent (deleted) files; instead, include their parent package's BUILD file
    if [[ ! -f "$file" ]]; then
        pkg_dir=$(dirname "$file")
        while [[ "$pkg_dir" != "." && ! -f "$pkg_dir/BUILD" && ! -f "$pkg_dir/BUILD.bazel" ]]; do
            pkg_dir=$(dirname "$pkg_dir")
        done
        if [[ -f "$pkg_dir/BUILD.bazel" ]]; then
            file="$pkg_dir/BUILD.bazel"
        elif [[ -f "$pkg_dir/BUILD" ]]; then
            file="$pkg_dir/BUILD"
        else
            continue
        fi
    fi

    # Query Bazel for the exact label owning this file (suppress errors for untracked/non-Bazel files)
    label=$(bazel query "$file" 2>/dev/null || true)
    if [[ -n "$label" ]]; then
        BAZEL_LABELS+=("$label")
    fi
done <<< "$CHANGED_FILES"

if [[ ${#BAZEL_LABELS[@]} -eq 0 ]]; then
    echo "No Bazel-tracked files modified (e.g., docs/README only). Skipping tests."
    exit 0
fi

# 4. Build a `set(...)` union of all changed labels and find impacted non-manual tests
TARGET_SET="set(${BAZEL_LABELS[*]})"
IMPACTED_TESTS=$(bazel query \
    --keep_going \
    --noshow_progress \
    "kind('.*_test', rdeps(//..., $TARGET_SET)) - attr(tags, 'manual', //...)")

if [[ -z "$IMPACTED_TESTS" ]]; then
    echo "No test targets impacted by changes."
    exit 0
fi

echo "=== Impacted Test Targets ==="
echo "$IMPACTED_TESTS"

# 5. Execute only the impacted tests
echo "$IMPACTED_TESTS" | xargs bazel test --test_output=errors
```

### Key Edge Cases Handled
* **Deleted Files:** `bazel query path/to/deleted.cpp` fails because the file no longer exists on disk. The script walks up to the owning `BUILD` file so reverse dependencies of that package are still re-tested.
* **`.bzl` Macro/Rule Edits:** Because `bazel query` tracks `buildfiles()` edges automatically, changing `defs.bzl` returns `//defs.bzl`, and `rdeps(//..., //defs.bzl)` finds every target using that macro.
* **Large-Scale Alternative:** For monorepos with 10,000+ targets where `bazel query` on `.bzl` edits becomes too broad, use **[bazel-diff](https://github.com/Tinder/bazel-diff "Tinder bazel-diff GitHub")** (which hashes target attributes into a Merkle tree between two Git commits).

---

## 2. Generating `compile_commands.json` Without a Local Build (Static Analysis)

Tools like **`clang-tidy`**, **`clangd` (IDE autocomplete)**, **SonarQube**, and **CodeChecker** require a `compile_commands.json` database. Because `bazel aquery` resolves all compiler flags, include paths (`-I`, `-isystem`), and `-D` defines during the **Analysis Phase**, you can extract the entire compilation database in seconds **without compiling a single `.cpp` file**.

### Option A: Zero-Dependency Python Script via `bazel aquery --output=jsonproto`

Save this as `tools/gen_compile_commands.py` and run it directly:

```python
#!/usr/bin/env python3
import json
import os
import subprocess
import sys

TARGET_PATTERN = sys.argv[1] if len(sys.argv) > 1 else "//..."

# 1. Ask Bazel for the Action Graph in JSON format (Analysis Phase only — no compilation!)
cmd = [
    "bazel",
    "aquery",
    f'mnemonic("CppCompile", {TARGET_PATTERN})',
    "--output=jsonproto",
    "--noshow_progress",
]
print(f"Running: {' '.join(cmd)}", file=sys.stderr)
raw_json = subprocess.check_output(cmd, text=True)
action_graph = json.loads(raw_json)

# 2. Get workspace execution root (working directory where compiler paths resolve)
execroot = subprocess.check_output(["bazel", "info", "execution_root"], text=True).strip()

compile_commands = []
source_exts = (".c", ".cc", ".cpp", ".cxx", ".mm")

for action in action_graph.get("actions", []):
    args = action.get("arguments", [])
    if not args:
        continue

    # Identify the source file being compiled from the compiler argument list
    src_file = next(
        (arg for arg in args[1:] if arg.endswith(source_exts) and not arg.startswith("-")),
        None,
    )
    if not src_file:
        continue

    compile_commands.append({
        "directory": execroot,
        "file": os.path.join(execroot, src_file),
        "arguments": args,
    })

out_path = "compile_commands.json"
with open(out_path, "w", encoding="utf-8") as f:
    json.dump(compile_commands, f, indent=2)

print(f"Generated {out_path} with {len(compile_commands)} entries (no build executed).")
```

#### Usage for Static Analysis (`clang-tidy`)
```bash
# 1. Generate compile_commands.json in ~2 seconds without compiling
python3 tools/gen_compile_commands.py //src/...

# 2. Run clang-tidy static analysis using the extracted flags
clang-tidy -p . src/driver/hal_rev_a.cpp
```

---

### Option B: Ready-Made Open-Source Bazel Extractors

If your repository uses generated headers (`genrule` / Protobuf) or external dependencies (`@boost`, `@abseil`) that need virtual include symlinks materialized for `clangd`, use one of these standard `aquery`-based modules in `MODULE.bazel`:

1. **[hedron_compile_commands](https://github.com/hedronvision/bazel-compile-commands-extractor "hedronvision bazel-compile-commands-extractor GitHub")**
   * **How it works:** Runs `bazel aquery` under the hood, rewrites `execroot` paths so `clangd` works cleanly across editor restarts, and maps header files to compile flags without building binaries.
   * **Run command:** `bazel run @hedron_compile_commands//:refresh_all`
2. **[wolfd/bazel-compile-commands](https://github.com/wolfd/bazel-compile-commands "wolfd bazel-compile-commands GitHub")**
   * **How it works:** Lightweight `aquery` extractor that filters `CppCompile` actions and maps `strip_include_prefix` targets.
   * **Run command:** `bazel run @wolfd_bazel_compile_commands//:generate_compile_commands`

