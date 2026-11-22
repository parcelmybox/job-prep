# Alert only if memory stays > 90% for 5+ minutes OR if OOMKills actually occur
(
  avg_over_time(
    (container_memory_working_set_bytes{namespace="ci-runners"} 
     / kube_pod_container_resource_limits{resource="memory"})[5m:]
  ) > 0.90
)
or
(
  increase(kube_pod_container_status_restarts_total{namespace="ci-runners"}[5m]) > 0
)
Here is the complete, unified cheatsheet combining the initial core concepts and the expanded Bazel BUILD/Starlark snippets and hands-on debugging scenarios in a single copy-pasteable Markdown block.
markdown
# Release Engineering, Observability & Build Infrastructure Cheatsheet

---

## 1. Observability, Prometheus, Grafana & Runbooks

| Concept | Core Idea | Key Mechanics / Terms |
| :--- | :--- | :--- |
| **Observability (o11y)** | Inferring internal system state solely from external outputs. | **Three Pillars:** Metrics (aggregatable numbers), Logs (discrete events), Traces (request lifecycle across services). |
| **Prometheus** | Pull-based time-series database (TSDB) & monitoring engine. | Scrapes `/metrics` endpoints via HTTP. Uses **PromQL**. Metric types: `Counter` (monotonic), `Gauge` (up/down), `Histogram` (buckets/quantiles), `Summary`. |
| **Grafana** | Visualization & alerting UI layer. | Connects to Prometheus, Loki (logs), Tempo/Jaeger (traces). Uses variables, templates, and threshold-based alert rules. |
| **Runbooks** | Actionable, step-by-step incident response guides. | Triggered by alerts. Contains: **Symptom**, **Impact**, **Triage Commands**, **Mitigation Steps**, and **Escalation Path**. |

---

## 2. Make → Bazel Migration: Runtime Issues & Solutions

Migrating from imperative `Make` to declarative, sandboxed `Bazel` exposes hidden assumptions in legacy builds.

### A. Object Comparison (Bit-for-Bit Reproducibility)
* **The Issue:** `Make` builds pass locally, `Bazel` builds produce different `.o` or binary hashes, or runtime crashes occur despite identical source code.
* **Root Causes:**
  * Embedded `__DATE__`, `__TIME__`, or `__FILE__` macros (Bazel uses sandbox paths like `/execroot/_main/...`).
  * Unsorted directory wildcard expansions (`$(wildcard *.c)` vs `glob(["*.c"])`).
  * Compiler flags injecting random seeds or local host paths (`-fdebug-prefix-map` missing).
* **Validation Tooling:** Use `objdump -d`, `readelf -a`, `nm`, and `diffoscope` to compare symbol tables, ELF sections, and build IDs between Make and Bazel outputs.

### B. Command Alignment
* **The Issue:** Subtle differences in compiler/linker flag ordering or default flags cause ABI mismatches or undefined symbols at runtime.
* **Fix:** Extract exact compile commands from Make (`make V=1` or `bear -- make`) and compare against Bazel (`bazel aquery 'mnemonic("CppCompile", //target)'`). Align `-isystem` vs `-I`, `-Wl,--as-needed`, and optimization levels.

### C. Environment Hermeticity
* **The Issue:** Make silently inherits `$PATH`, `LD_LIBRARY_PATH`, `/usr/include`, and host Python packages. Bazel strips environment variables to guarantee hermeticity.
* **Fix:**
  * Explicitly declare toolchains (`cc_toolchain`, Nix-provided sysroots/compilers) rather than relying on host `/usr/bin/gcc`.
  * Replace implicit host lookups with explicit `BUILD` dependencies and `ctx.actions.run` environment dictionaries.

### D. Dependency Tracking with `strace` Custom Tooling
* **The Issue:** Legacy Make scripts read/write undeclared headers, config files, or temporary scripts during compilation—breaking Bazel’s sandbox.
* **Custom `strace` Audit Approach:**
  1. Wrap the legacy Make command: `strace -f -e trace=file -o build_trace.log make target`
  2. Parse `openat()`, `stat()`, `execve()` syscalls with a Python script to filter out standard system paths (`/lib`, `/proc`, `/dev`).
  3. Diff the accessed file list against Bazel’s declared `srcs`, `hdrs`, and `data` attributes to catch missing dependencies before sandboxing fails.

---

## 3. Dynamic Validation Pipeline Based on Changeset

Instead of running a monolithic 40-checker pipeline on every commit, inspect `git diff` (or `bazel query rdeps(...)`) to dynamically route jobs.

| Changeset Trigger | Scope / Risk | Dynamic Pipeline Validation Strategy |
| :--- | :--- | :--- |
| **Only `.md` / `.txt` files** | Zero binary impact | Skip compilation & hardware tests. Run **docs linter / spellcheck** only (~30 sec). |
| **SDK Version Change** | High ABI/API & toolchain risk | Trigger **full clean rebuild**, ABI compliance checker (`abi-dumper`), cross-architecture builds, and full hardware-in-the-loop (HIL) regression suite. |
| **New Hardware Defined** | Platform/BSP & driver impact | Register new `platform()` / `constraint_value` in Bazel. Run cross-compilation matrix, device-tree/firmware packaging checks, and hardware emulator tests. |
| **Process Changes (New SDK)** | Workflow & artifact signing risk | Validate updated CI scripts/toolchains in an isolated canary branch, verify artifact provenance/checksums, and run smoke tests on staging runners before rollout. |
| **New Customer Package Added** | Packaging, licensing, & config risk | Run **target-specific** Bazel build (`bazel build //packages/customer_x:...`), license compliance scan, container/RPM structure verification, and customer-specific integration tests. |

---

## 4. Bazel `BUILD` & Starlark Snippets (SDKs, Platforms & Packaging)

### A. Defining Hardware Platforms & Constraints (`platforms/BUILD.bazel`)
Use `constraint_setting` and `platform` to target specific hardware boards or CPU architectures cleanly without brittle `select()` hacks on raw strings.

```python
package(default_visibility = ["//visibility:public"])

# 1. Define custom hardware board constraints
constraint_setting(name = "hardware_board")

constraint_value(
    name = "board_rev_a",
    constraint_setting = ":hardware_board",
)

constraint_value(
    name = "board_rev_b",
    constraint_setting = ":hardware_board",
)

# 2. Define target platforms combining OS, CPU, and Board
platform(
    name = "linux_arm64_rev_b",
    constraint_values = [
        "@platforms//os:linux",
        "@platforms//cpu:aarch64",
        ":board_rev_b",
    ],
)
```

### B. SDK Version & Hardware-Specific Compilation (`src/driver/BUILD.bazel`)
Use `select()` with `config_setting` to switch flags, SDK headers, or source files when a new SDK or hardware revision is introduced.

```python
load("@rules_cc//cc:defs.bzl", "cc_binary", "cc_library")

config_setting(
    name = "sdk_v2_flag",
    flag_values = {"//settings:sdk_version": "2.0"},
)

cc_library(
    name = "sensor_hal",
    srcs = select({
        "//platforms:board_rev_a": ["hal_rev_a.cpp"],
        "//platforms:board_rev_b": ["hal_rev_b.cpp"],
    }),
    hdrs = ["sensor_hal.h"],
    copts = select({
        ":sdk_v2_flag": ["-DUSE_SDK_V2", "-Wall", "-Werror"],
        "//conditions:default": ["-DUSE_SDK_V1"],
    }),
    deps = select({
        ":sdk_v2_flag": ["@sdk_v2//:core_libs"],
        "//conditions:default": ["@sdk_v1//:core_libs"],
    }),
)
```

### C. Custom Starlark Rule for Customer Packaging & Manifests (`rules/customer_pkg.bzl`)
Enforces strict hermetic inputs (`ctx.actions.run`) so undeclared host files cannot leak into customer deliverables.

```python
def _customer_package_impl(ctx):
    out_tar = ctx.actions.declare_file(ctx.attr.customer_id + "_release.tar.gz")
    manifest = ctx.actions.declare_file(ctx.attr.customer_id + "_manifest.json")

    # 1. Generate deterministic JSON manifest
    manifest_content = struct(
        customer = ctx.attr.customer_id,
        sdk_version = ctx.attr.sdk_version,
        artifacts = [f.basename for f in ctx.files.binaries],
    ).to_json()
    ctx.actions.write(output = manifest, content = manifest_content)

    # 2. Hermetically bundle binaries + manifest using tar
    inputs = ctx.files.binaries + [manifest]
    args = ctx.actions.args()
    args.add("-czf", out_tar)
    args.add("--mtime=1970-01-01 00:00:00Z")  # Ensures bit-for-bit reproducibility
    args.add("--sort=name")
    args.add_all(inputs)

    ctx.actions.run(
        inputs = inputs,
        outputs = [out_tar],
        executable = "tar",
        arguments = [args],
        mnemonic = "CustomerPkgTar",
        progress_message = "Packaging release for %s" % ctx.attr.customer_id,
    )

    return [DefaultInfo(files = depset([out_tar]))]

customer_package = rule(
    implementation = _customer_package_impl,
    attrs = {
        "customer_id": attr.string(mandatory = True),
        "sdk_version": attr.string(mandatory = True),
        "binaries": attr.label_list(allow_files = True, mandatory = True),
    },
)
```

---

## 5. Typical Technical Questions

1. **Prometheus:** *Why is high cardinality (e.g., putting `commit_sha` or `user_id` in a metric label) dangerous in Prometheus?*
   * **Answer:** Every unique label combination creates a new time series in memory/TSDB, causing OOM crashes and slow PromQL queries. Keep high-cardinality IDs in **logs/traces**, not metric labels.
2. **Bazel:** *A Bazel build succeeds locally (`--spawn_strategy=local`) but fails in Remote Execution (RBE) with `No such file or directory`. Why?*
   * **Answer:** An undeclared input file (e.g., a header or script) exists on the local disk and leaked into the local build, whereas RBE only ships explicitly declared `deps`/`data` to the remote worker.
3. **CI Scaling:** *How do you prevent 2,000 concurrent CI jobs from exhausting Kubernetes cluster resources?*
   * **Answer:** Use event-driven ingestion (Kafka/CloudEvents), concurrency semaphores/queues at the workflow controller level, and node taints/tolerations separating lightweight linters from heavy C++ compile pods.

---

## 6. Hands-On Debugging Scenarios & Code Challenges

### Scenario 1: The "Works in Make, Segfaults in Bazel" Binary
* **Symptom:** A C++ binary compiled with Bazel crashes at startup with `SIGSEGV`, while the Make binary runs fine.
* **Diagnosis Steps:**
  1. Run `ldd` on both binaries to check linked shared libraries and load order.
  2. Run `readelf -d <binary> | grep RPATH` to verify `RUNPATH`/`RPATH` differences (Bazel uses `$ORIGIN/_solib_...`).
  3. Check static initialization order (`nm -C <binary> | grep _GLOBAL__sub_I`)—link order differences between Make and Bazel can invert global constructor execution.

### Scenario 2: Non-Deterministic Binary Hashes Between Two Bazel Builds
Use code with caution.
• Symptom: Running bazel clean && bazel build //app:main twice produces different sha256sum values on the output ELF binary, breaking remote cache hits.
• Diagnosis Steps:
	1. Compare ELF sections and symbols with diffoscope:bash
diffoscope bazel-bin/app/main_run1 bazel-bin/app/main_run2
Use code with caution.
	2. Look for differences in .rodata (embedded timestamps like __DATE__/__TIME__) or .debug_str (sandbox path variations).
• Fix:
	• Add -Wno-builtin-macro-redefined -D__DATE__="redacted" -D__TIME__="redacted" to toolchain copts.
	• Ensure -ffile-prefix-map=$PWD=. is enabled in your cc_toolchain so debug symbols don't encode temporary sandbox worker IDs.

Scenario 3: Make Binary Works, Bazel Binary Fails with undefined symbol at Runtime

• Symptom: dlopen() fails at runtime with undefined symbol: _ZN3sdk4InitEv in the Bazel-built shared library, even though compilation succeeded.
• Diagnosis Steps:
	1. Check dynamic symbol table (-D) and needed libraries (-d) on both Make and Bazel .so files:bash
nm -D --defined-only make_out/libsensor.so | grep Init
nm -D --defined-only bazel-bin/src/libsensor.so | grep Init
readelf -d bazel-bin/src/libsensor.so | grep NEEDED
Use code with caution.
	2. Check if Bazel stripped an archive dependency because no symbols were directly referenced by the .so (common with plugin registries).
• Fix:
	• In Bazel, wrap the static library dependency with alwayslink = True on the cc_library rule. This forces the linker to pass --whole-archive so static initializers and plugin symbols aren't dropped.

Scenario 4: Finding Hidden Header/File Dependencies in Legacy Make via strace

• Symptom: A Make target compiles cleanly, but migrating it to Bazel fails with fatal error: generated_version.h: No such file or directory.
• Diagnosis Script (audit_deps.py):
Run strace -f -e trace=openat,execve -o trace.log make target and execute:python
import os
import re

WORKSPACE = os.path.abspath(".")
IGNORED_PREFIXES = ("/usr", "/lib", "/etc", "/proc", "/dev", "/sys")
opened = set()

regex = re.compile(r'openat\([^,]+,\s*"([^"]+)"')
with open("trace.log", "r", encoding="utf-8", errors="ignore") as f:
    for line in f:
        if "ENOENT" in line or "O_WRONLY" in line or "O_CREAT" in line:
            continue
        m = regex.search(line)
        if m:
            filepath = os.path.abspath(m.group(1))
            if not filepath.startswith(IGNORED_PREFIXES) and os.path.isfile(filepath):
                opened.add(os.path.relpath(filepath, WORKSPACE))

for item in sorted(opened):
    print(item)
Use code with caution.
• Fix: Compare the printed file list against bazel query 'deps(//target)'. Any file printed by audit_deps.py that is missing from Bazel's dependency graph must be added to hdrs, srcs, or data.

Scenario 5: Prometheus Alert Fatigue on Ephemeral CI Runners

• Symptom: HighMemoryUsage alert fires constantly when K8s CI pods spin up heavy C++ linkers (ld / lld), then resolves 45 seconds later.
• Broken PromQL:promql
(container_memory_working_set_bytes{namespace="ci-runners"} / kube_pod_container_resource_limits{resource="memory"}) > 0.85
Use code with caution.
• Root Cause: Instantaneous spikes during linking are normal; alerting without time-smoothing or checking OOMKills creates noise.
• Fixed PromQL (Sustained Saturation + Actual OOM Check):promql
# Alert only if memory stays > 90% for 5+ minutes OR if OOMKills actually occur
(
  avg_over_time(
    (container_memory_working_set_bytes{namespace="ci-runners"} 
     / kube_pod_container_resource_limits{resource="memory"})[5m:]
  ) > 0.90
)
or
(
  increase(kube_pod_container_status_restarts_total{namespace="ci-runners"}[5m]) > 0
)
Use code with caution.

Scenario 6: Dynamic Pipeline Script (Routing CI Checks by Changeset)

• Scenario: Given git diff --name-only origin/main...HEAD, determine which validation tier to execute.bash
#!/usr/bin/env bash
set -euo pipefail

CHANGED_FILES=$(git diff --name-only origin/main...HEAD)

if [[ -z "$CHANGED_FILES" ]]; then
    echo "No changes detected."
    exit 0
fi

# 1. Docs-only check
if ! echo "$CHANGED_FILES" | grep -qvE '\.(md|txt|rst)$'; then
    echo "TIER=DOCS_ONLY"
    exit 0
fi

# 2. SDK or Toolchain version bump
if echo "$CHANGED_FILES" | grep -qE '^(WORKSPACE|MODULE\.bazel|toolchains/|sdk_version\.bzl)'; then
    echo "TIER=FULL_SDK_REGRESSION"
    exit 0
fi

# 3. New Hardware Platform definition
if echo "$CHANGED_FILES" | grep -qE '^platforms/'; then
    echo "TIER=HARDWARE_MATRIX_VALIDATION"
    exit 0
fi

# 4. Customer Package addition/modification
if echo "$CHANGED_FILES" | grep -qE '^packages/customers/'; then
    echo "TIER=CUSTOMER_PACKAGE_AUDIT"
    exit 0
fi

# 5. Default: Impacted Bazel targets only
echo "TIER=IMPACTED_TARGETS"
Use code with caution.

---



## Deep Dive: PromQL CAS Cache Hit Ratio Query

### The Query
```promql
sum(rate(rbe_cas_operations_total{result="hit"}[5m]))
/
sum(rate(rbe_cas_operations_total[5m]))
```

---

### 1. Step-by-Step Execution Breakdown

Prometheus evaluates this expression from the inside out:

1. **Metric & Label Filtering (`rbe_cas_operations_total{result="hit"}`)**
   * `rbe_cas_operations_total` is a **Counter** metric (a monotonically increasing number that only goes up or resets to `0` on pod restart).
   * `{result="hit"}` filters the time series down to only successful cache lookups (e.g., `FindMissingBlobs` or `GetActionResult` calls where the digest already existed in CAS).
   * The denominator omits `{result="hit"}` so it selects **all** operations (`result="hit"` + `result="miss"` + any `result="error"`).

2. **Range Vector Selection (`[5m]`)**
   * Appending `[5m]` converts an instant vector (a single point in time) into a **range vector**—a sliding window containing all raw counter samples collected over the last 5 minutes.
   * *Rule of thumb:* Always make the range window at least **$4\times$ your Prometheus `scrape_interval`** (e.g., if `scrape_interval` is `15s` or `30s`, `[5m]` gives 10–20 data points per series, smoothing out single-scrape jitter).

3. **Per-Second Rate Calculation (`rate(...[5m])`)**
   * Because `rbe_cas_operations_total` is a cumulative counter (e.g., `10,450,200` total hits since startup), raw numbers are meaningless for current health.
   * `rate()` calculates the **average per-second increase** over the 5-minute window and automatically handles **counter resets** (if a CAS server pod restarts and its counter drops back to `0`, `rate()` detects the drop and prevents false negative spikes).

4. **Cluster-Wide Aggregation (`sum(...)`)**
   * In a distributed RBE setup, you run multiple CAS storage pods/replicas (each with its own `instance` or `pod` label).
   * `rate()` produces one per-second rate per pod.
   * `sum()` aggregates those individual pod rates into a single cluster-wide number (total hits/sec across all pods divided by total requests/sec across all pods).

5. **Ratio Division (`/`)**
   * Divides total cluster hits/sec by total cluster requests/sec, yielding a decimal between `0.0` (0% hit rate) and `1.0` (100% hit rate). Multiply by `100` in Grafana if displaying as a `0–100%` percentage gauge.

---

### 2. Why Order of Operations Matters (`sum(rate(...))` vs `rate(sum(...))`)

A classic Prometheus interview question and production bug is reversing `sum` and `rate`:

* **Correct:** `sum(rate(metric[5m]))`
  * Calculates the per-second rate and handles counter resets **per pod first**, then adds the rates together.
* **Broken:** `rate(sum(metric)[5m])`
  * Sums raw counters across pods first. If **one** CAS pod restarts, the combined sum drops sharply, tricking `rate()` into thinking the entire cluster reset and causing massive artificial spikes in your dashboard.

---

### 3. Production Caveats & Refinements

| Edge Case | What Happens with the Base Query | How to Fix It |
| :--- | :--- | :--- |
| **Idle CI Cluster (Zero Traffic)** | During nights/weekends when `0` builds run, the denominator is `0`, resulting in `NaN` (0/0), which can break Grafana panels or trigger false alerts. | Append `or vector(1)` or guard alerts with `and sum(rate(rbe_cas_operations_total[5m])) > 10` so alerts only fire under active build load. |
| **Action Cache (AC) vs. CAS Mixing** | `FindMissingBlobs` (CAS) naturally has many "misses" during normal incremental builds (new `.o` files), whereas `GetActionResult` (AC) should stay high (`>85%`). | Filter by RPC method explicitly: `{method="FindMissingBlobs", result="hit"}` vs `{method="GetActionResult", result="hit"}`. |
| **Per-Repository / Per-Team Breakdown** | A single global number hides if one specific team's `BUILD` rules are non-hermetic. | Add `by (instance_name)` or `by (repo)`: `sum by (repo) (rate(...{result="hit"}[5m])) / sum by (repo) (rate(...[5m]))`. |

---

### 4. Production-Ready Alert Rule Example (Prometheus YAML)

```yaml
groups:
  - name: rbe-cas-alerts
    rules:
      - alert: RbeActionCacheHitRateLow
        expr: |
          (
            sum(rate(rbe_cas_operations_total{method="GetActionResult", result="hit"}[15m]))
            /
            sum(rate(rbe_cas_operations_total{method="GetActionResult"}[15m]))
          ) < 0.70
          and
          sum(rate(rbe_cas_operations_total{method="GetActionResult"}[15m])) > 5
        for: 15m
        labels:
          severity: warning
        annotations:
          summary: "RBE Action Cache hit rate dropped below 70% (current: {{ \$value | humanizePercentage }})"
          description: "Sustained cache misses indicate likely non-hermetic build inputs (e.g., timestamps, leaked env vars, or SDK toolchain drift)."
```


## Deep Dive: Kubernetes Node Taints & Tolerations + Prometheus TSDB Time Series

---

## Part 1: Kubernetes Node Taints & Tolerations

### 1. Core Concept
* **Taint (Applied to a Node):** A "repellent" label placed on a Kubernetes node that **prevents** pods from scheduling onto it unless the pod explicitly declares permission.
* **Toleration (Applied to a Pod):** A "pass" declared in a pod's spec allowing (but not forcing) it to be scheduled onto a node with a matching taint.
* **Why It Matters in CI / RBE:** Isolates heavyweight C++ compile/link workers or GPU/HIL test runners from lightweight system pods (Prometheus, CoreDNS, Argo controllers) so heavy builds don't starve critical control-plane services of CPU/RAM.

---

### 2. Taint Effects

| Effect | Behavior on New Pods | Behavior on Already-Running Pods |
| :--- | :--- | :--- |
| **`NoSchedule`** | Hard block: Pod will **not** be scheduled onto the node without a matching toleration. | Existing pods stay running undisturbed. |
| **`PreferNoSchedule`** | Soft block: Scheduler tries to avoid the node, but places the pod there if the cluster has no other capacity. | Existing pods stay running undisturbed. |
| **`NoExecute`** | Hard block: Pod will not be scheduled onto the node. | **Evicts** any existing pod on the node that lacks a matching toleration (or exceeds `tolerationSeconds`). |

---

### 3. Practical CI / RBE Example

#### Step A: Taint Dedicated High-CPU Build Nodes
```bash
# Repel general workloads from heavy Bazel RBE worker nodes
kubectl taint nodes rbe-worker-01 workload=heavy-build:NoSchedule
```

#### Step B: Pod Spec with Matching Toleration + Node Affinity
*Note:* A **toleration** only permits scheduling on the tainted node—it does not guarantee the pod lands there. Pair it with **`nodeAffinity`** to lock heavy build pods onto those nodes.

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: bazel-rbe-executor
  namespace: ci-runners
spec:
  # 1. Allows this pod onto nodes tainted with workload=heavy-build:NoSchedule
  tolerations:
    - key: "workload"
      operator: "Equal"
      value: "heavy-build"
      effect: "NoSchedule"

  # 2. Forces this pod to ONLY run on nodes labeled workload=heavy-build
  affinity:
    nodeAffinity:
      requiredDuringSchedulingIgnoredDuringExecution:
        nodeSelectorTerms:
          - matchExpressions:
              - key: workload
                operator: In
                values: ["heavy-build"]

  containers:
    - name: rbe-worker
      image: buildbarn/bb-worker:latest
      resources:
        requests:
          cpu: "16"
          memory: "64Gi"
```

---

## Part 2: New Time Series in Prometheus Memory & TSDB

### 1. What Defines a Unique Time Series?
In Prometheus, a **time series** is uniquely identified by its **metric name + exact set of key-value labels**:

\[\text{Unique Time Series} = \text{Metric Name} + \{\text{label}_1=\text{val}_1, \text{label}_2=\text{val}_2, \dots\}\]

Whenever a scrape introduces a **never-before-seen label value**, Prometheus treats it as a brand-new time series—even if the metric name is identical.

---

### 2. Concrete Example: Low vs. High Cardinality

#### Low Cardinality (Healthy)
```text
rbe_cas_operations_total{method="FindMissingBlobs", result="hit"}   -> Series #1
rbe_cas_operations_total{method="FindMissingBlobs", result="miss"}  -> Series #2
rbe_cas_operations_total{method="BatchReadBlobs",   result="hit"}   -> Series #3
rbe_cas_operations_total{method="BatchReadBlobs",   result="miss"}  -> Series #4
```
* **Total Series:** \(2 \text{ methods} \times 2 \text{ results} = \mathbf{4 \text{ time series}}\) (constant over time).

#### High Cardinality (Dangerous — "Cardinality Explosion")
Adding unbounded labels like `commit_sha` or `build_id`:
```text
rbe_cas_operations_total{method="FindMissingBlobs", commit_sha="a1b2c3d"} -> Series #1
rbe_cas_operations_total{method="FindMissingBlobs", commit_sha="e4f5g6h"} -> Series #2
# ... after 10,000 CI builds in a week:
rbe_cas_operations_total{method="FindMissingBlobs", commit_sha="z9y8x7w"} -> Series #10,000
```
* **Total Series:** Grows infinitely with every commit, causing **series churn**.

---

### 3. What Happens Inside Prometheus Memory & TSDB?

1. **In-Memory Head Block (RAM):**
   * Prometheus keeps the active 2-hour window ("Head Block") completely in **RAM** for fast ingestion and querying.
   * Every active time series requires ~**2–4 KB of RAM** for its metadata, inverted index postings, and sample chunks.
   * *Math:* $1,000,000 \text{ active series} \times 3\text{ KB} \approx \mathbf{3\text{ GB of RAM}}$ just for the head block (before query evaluation buffers).
2. **Inverted Index Bloat (Disk TSDB):**
   * Every 2 hours, Prometheus flushes the Head Block to an immutable on-disk **TSDB block** containing an **inverted index** mapping every `label="value"` pair to its series IDs.
   * Unbounded labels (`commit_sha`, `pod_uid`, `user_email`) bloat the index size on disk, slow down regex/label lookups (`{commit_sha=~"..."}`), and trigger **OOMKilled** crashes during compaction or wide range queries (`[7d]`).

---

### 4. Quick Checklist to Prevent Cardinality Explosions
* **Never** put `commit_sha`, `build_uuid`, `pod_name` (if ephemeral), `user_id`, or full file paths in Prometheus metric labels.
* **Keep high-cardinality metadata in Logs (Loki) or Traces (Tempo/Jaeger)**—use Prometheus strictly for aggregated service/subsystem health (`method`, `status_code`, `queue_name`, `hardware_tier`).
* **Inspect Top Series in Prometheus:** Run this PromQL query to find which metric is consuming the most TSDB series:
  ```promql
  topk(10, count by (__name__)({__name__=~".+"}))
  ```

# Bazel Rules vs. Macros & Cross-Compilation Guide (macOS → Linux)

---

## 1. Bazel Macro vs. Bazel Rule

| Feature | Bazel Macro | Bazel Rule |
| :--- | :--- | :--- |
| **Definition** | A standard Python-like Starlark function (`def my_macro(...):`). | Created via `rule(implementation = _impl, attrs = {...})`. |
| **Execution Phase** | **Loading Phase** (expands into underlying rules before the build graph is finalized). | **Analysis Phase** (registers actions like `ctx.actions.run` and returns providers like `DefaultInfo`). |
| **What It Does** | Wraps, configures, or chains existing rules (e.g., calling `cc_binary` + `genrule` together) to reduce boilerplate. | Invokes compilers, linkers, or custom tools directly on input `File` objects to produce output `File` artifacts. |
| **Visibility in `bazel query`** | Invisible—`bazel query` only sees the underlying rules the macro generated. | First-class target—visible by its own rule class in `bazel query`. |
| **When to Use** | Standardizing flags, `deps`, or multi-step target patterns across many `BUILD` files. | Adding support for a new language, compiler, or custom file-transformation step. |

---

## 2. Full Cross-Compilation Example (macOS Host → Linux Target)

On macOS, Bazel's default auto-detected C++ toolchain targets Darwin (`macos`). To cross-compile a Linux ELF binary from a MacBook, you register a cross-compiler toolchain (such as [`hermetic_cc_toolchain`](https://github.com)) and bind it to a Linux `platform()`.

### Project Layout
```text
hello_cross/
├── MODULE.bazel      # External dependencies & cross-toolchain registration
├── BUILD.bazel       # Platform constants, targets, srcs, and deps
├── defs.bzl          # Macro vs. Custom Rule definitions
├── greeter.h         # Header file (demonstrating deps)
├── greeter.cpp       # Library source file
└── main.cpp          # Binary entry point
```

---

### Step 1: `MODULE.bazel` (Registering the Cross-Toolchain)
```python
module(
    name = "hello_cross",
    version = "1.0.0",
)

# Standard C++ rules (provides cc_library, cc_binary)
bazel_dep(name = "rules_cc", version = "0.0.17")

# Standard OS & CPU constraint constants (@platforms//os:linux, @platforms//cpu:x86_64, etc.)
bazel_dep(name = "platforms", version = "0.0.11")

# Open-source Zig-based hermetic C/C++ cross-compiler (runs natively on macOS Intel & Apple Silicon)
bazel_dep(name = "hermetic_cc_toolchain", version = "3.1.1")

toolchains = use_extension("@hermetic_cc_toolchain//toolchain:ext.bzl", "toolchains")
use_repo(toolchains, "zig_sdk")

# Register both Linux targets and native macOS host targets so Bazel can resolve either platform
register_toolchains(
    "@zig_sdk//toolchain:linux_amd64_gnu.2.28",
    "@zig_sdk//toolchain:linux_arm64_gnu.2.28",
    "@zig_sdk//toolchain:darwin_arm64",
    "@zig_sdk//toolchain:darwin_amd64",
)
```

---

### Step 2: C++ Source & Header Files

#### `greeter.h`
```cpp
#pragma once
#include <string>

std::string get_platform_greeting();
```

#### `greeter.cpp`
```cpp
#include "greeter.h"

std::string get_platform_greeting() {
#if defined(__linux__)
    return "Hello from Linux ELF binary (cross-compiled on macOS)!";
#elif defined(__APPLE__)
    return "Hello from native macOS Mach-O binary!";
#else
    return "Hello from unknown OS!";
#endif
}
```

#### `main.cpp`
```cpp
#include <iostream>
#include "greeter.h"

int main() {
    std::cout << get_platform_greeting() << std::endl;
    return 0;
}
```

---

### Step 3: `defs.bzl` (Commented Macro vs. Custom Rule)
```python
load("@rules_cc//cc:defs.bzl", "cc_binary")

# ==============================================================================
# 1. BAZEL MACRO (Loading Phase)
#    - Just a Starlark helper function that stamps out a `cc_binary` target.
#    - Does NOT create build actions itself; delegates to `cc_binary`.
# ==============================================================================
def strict_cc_binary(name, srcs, deps = [], **kwargs):
    """Macro that enforces C++20 and strict compiler warnings on any binary."""
    default_copts = ["-std=c++20", "-Wall", "-Wextra", "-O2"]
    user_copts = kwargs.pop("copts", [])

    # Expands into a standard cc_binary rule during the Loading Phase
    cc_binary(
        name = name,
        srcs = srcs,                    # Passed directly to cc_binary
        deps = deps,                    # Passed directly to cc_binary
        copts = default_copts + user_copts,
        **kwargs
    )


# ==============================================================================
# 2. BAZEL RULE (Analysis Phase)
#    - Low-level primitive that defines inputs, outputs, and shell/binary actions.
# ==============================================================================
def _binary_info_impl(ctx):
    # `ctx.file.<attr_name>` accesses the single File artifact passed to `target_bin`
    binary = ctx.file.target_bin

    # Declare the output file that this rule promises to produce during execution
    out_report = ctx.actions.declare_file(ctx.label.name + "_report.txt")

    # Register an action in the build graph (runs `file` utility on the compiled binary)
    ctx.actions.run_shell(
        inputs = [binary],              # Sandbox ONLY mounts declared inputs
        outputs = [out_report],         # Sandbox ONLY extracts declared outputs
        command = "file -b '%s' > '%s'" % (binary.path, out_report.path),
        mnemonic = "InspectBinaryFormat",
        progress_message = "Inspecting binary format for %s" % binary.short_path,
    )

    # Return DefaultInfo provider so downstream targets or `bazel build` know what files were built
    return [DefaultInfo(files = depset([out_report]))]

verify_binary_format = rule(
    implementation = _binary_info_impl,
    attrs = {
        # Defines the `target_bin` attribute accepted in BUILD.bazel
        "target_bin": attr.label(
            allow_single_file = True,   # Restricts input to a single File artifact
            mandatory = True,           # Fails analysis if omitted in BUILD.bazel
        ),
    },
)
```

---

### Step 4: `BUILD.bazel` (Explaining Constants, `srcs`, and `deps`)
```python
load("@rules_cc//cc:defs.bzl", "cc_library")
load(":defs.bzl", "strict_cc_binary", "verify_binary_format")

# ==============================================================================
# 1. PLATFORM & CONSTRAINT CONSTANTS
#    - Instead of brittle string flags like `--cpu=k8`, Bazel uses typed
#      `constraint_value` constants from `@platforms` to match toolchains.
# ==============================================================================
platform(
    name = "linux_x86_64",
    constraint_values = [
        "@platforms//os:linux",     # Built-in constant: Target Operating System = Linux
        "@platforms//cpu:x86_64",   # Built-in constant: Target CPU Architecture = x86_64
    ],
)

platform(
    name = "linux_arm64",
    constraint_values = [
        "@platforms//os:linux",     # Built-in constant: Target Operating System = Linux
        "@platforms//cpu:aarch64",  # Built-in constant: Target CPU Architecture = ARM64
    ],
)

# ==============================================================================
# 2. LIBRARY TARGET (`srcs` vs `hdrs`)
# ==============================================================================
cc_library(
    name = "greeter_lib",
    # `srcs`: Implementation files (.cpp, .c) compiled into object files (.o / .a)
    #         Private to this target; NOT exposed directly to downstream consumers.
    srcs = ["greeter.cpp"],

    # `hdrs`: Public header files (.h, .hpp) exposed to any target that lists
    #         `:greeter_lib` in its `deps`. Bazel enforces strict header inclusion.
    hdrs = ["greeter.h"],
)

# ==============================================================================
# 3. BINARY TARGET VIA MACRO (`srcs` + `deps`)
# ==============================================================================
strict_cc_binary(
    name = "hello_world",
    # `srcs`: Source files needed to compile and link this specific executable.
    srcs = ["main.cpp"],

    # `deps`: Other Bazel library targets (in the same package `:greeter_lib` or
    #         another package `//path/to/pkg:lib`) whose headers and compiled
    #         archives must be linked into `:hello_world`.
    deps = [":greeter_lib"],
)

# ==============================================================================
# 4. CUSTOM RULE TARGET
# ==============================================================================
verify_binary_format(
    name = "hello_format",
    # Passes the output binary of `:hello_world` as an input File to our custom rule
    target_bin = ":hello_world",
)
```

---

### Step 5: Build & Verify Commands on macOS

```bash
# 1. Cross-compile for Linux x86_64 from your MacBook
bazel build --platforms=//:linux_x86_64 //:hello_world //:hello_format

# 2. Verify the output report generated by the custom rule
cat bazel-bin/hello_format_report.txt
# Output:
# ELF 64-bit LSB executable, x86-64, version 1 (SYSV), dynamically linked...

# 3. Cross-compile for Linux ARM64 (e.g., AWS Graviton / Raspberry Pi)
bazel build --platforms=//:linux_arm64 //:hello_world
file bazel-bin/hello_world
# Output:
# bazel-bin/hello_world: ELF 64-bit LSB executable, ARM aarch64, version 1 (SYSV)...

# 4. Build natively for macOS (no --platforms flag needed)
bazel build //:hello_world
file bazel-bin/hello_world
# Output:
# bazel-bin/hello_world: Mach-O 64-bit executable arm64
```

---

## 3. Simplest Open-Source Reference Repositories

If you want clean, minimal open-source repositories to clone and study directly:

1. **`bazelbuild/examples` (Official Bazel Examples Repo)**
   * **URL:** `https://github.com`

