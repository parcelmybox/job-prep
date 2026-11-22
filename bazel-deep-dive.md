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
