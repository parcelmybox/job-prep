# ScaleUp DevOps Technical Screening -- Experience-Based Cheat Sheet

**Purpose:** Prepare to discuss your actual experience against ScaleUp's
DevOps role.\
**Positioning:** Platform Engineering / CI Infrastructure Architect with
deep experience in distributed native builds, CI/CD, build performance,
Linux infrastructure, and release automation.

> **Interview rule:** Separate what you have implemented from what you
> understand conceptually and what you would propose. Do not claim
> direct SAI, RoCE, DPDK, hardware-in-the-loop, or AI-networking
> implementation unless you have actually done it.

------------------------------------------------------------------------

## 1. Your 60--90 second positioning statement

I have 23+ years of experience in software engineering, build
infrastructure, CI/CD platforms, and developer productivity. At Cisco, I
provide technical leadership across build infrastructure, GitHub
workflows, and CI/CD, leading a 10-member engineering team.

A major accomplishment was delivering a production-grade Bazel Remote
Build Execution platform using BuildBarn in approximately 10 weeks. The
platform scaled to 1,600 CPU cores across 60+ nodes, with 20 TB of
storage, supporting more than 1,000 daily builds. I also worked on
migrating Broadcom SDK build infrastructure from Make to Bazel,
integrating Bazel with Jenkins, and improving build performance through
remote caching, dependency-graph tuning, and parallel execution.

More recently, I have been driving Kubernetes-native build execution
using Podman and Argo Workflows. A significant challenge was discovering
dependencies spread across more than 100 mounted filesystems and tool
locations, then standardizing toolchains and separating container images
from toolchain storage.

ScaleUp interests me because its challenges combine native SDK builds,
multi-repository dependencies, simulation, CI reliability, and release
engineering. Those are closely related to the platform problems I have
been solving.

------------------------------------------------------------------------

## 2. Match the role to your experience

  ------------------------------------------------------------------------
  ScaleUp area            Evidence from your      Interview emphasis
                          experience              
  ----------------------- ----------------------- ------------------------
  CI/CD ownership         Jenkins, GitHub         Explain end-to-end
                          workflows, Argo         pipeline ownership, not
                          Workflows; technical    just job maintenance
                          leadership of build/CI  
                          platforms               

  Multi-repository builds 40+ components          Dependency graphs,
                          integrated into Emulex  version compatibility,
                          nightly pipelines;      change impact
                          Broadcom SDK migration  

  Large C/C++ builds      Bazel, Make, native     Compile/link flow,
                          builds,                 toolchain consistency,
                          cross-compilation, Wind reproducibility
                          River toolchains        

  Build caching           Bazel RBE, remote-cache Cache keys, hit rate,
                          optimization            correctness,
                                                  invalidation

  Shared runners/build    BuildBarn, 60+ nodes,   Worker lifecycle,
  farms                   distributed execution   scheduling, capacity,
                                                  isolation

  Linux infrastructure    Linux, Kubernetes,      Debugging, resource
                          rootless Podman         limits, mounts,
                                                  permissions

  Python/Bash automation  Python, Perl, Bash,     Operational automation,
                          Flask, shell automation diagnostics, APIs

  Build performance       Up to 3x improvement    Measure queue time,
                          through profiling,      execution time, cache
                          cache optimization,     hit rate
                          dependency tuning and   
                          parallelism             

  Quality gates           Coverity static         Fast PR gates, deeper
                          analysis and compliance nightly gates,
                          automation              actionable failures

  Observability           Prometheus, Grafana,    Metrics, dashboards,
                          Splunk                  alerting, runbooks

  Artifact management     Distributed             Be ready to explain
                          build/storage           artifact lifecycle; do
                          architecture; release   not overstate registry
                          automation experience   expertise

  Release promotion       Oracle, Intuit and      Immutable artifacts,
                          Emulex release          release branches,
                          automation; 60+ stable  approvals, rollback
                          releases at Oracle      

  Jira integration        Jira and Perforce       Issue/PR/build/release
                          integrations; Jira      traceability
                          listed in skills        
  ------------------------------------------------------------------------

### Resume facts to remember

-   23+ years in software engineering and platform/build infrastructure.
-   Cisco: April 2014--present; Senior DevOps Lead.
-   Leads a 10-member team across build infrastructure, GitHub and
    CI/CD.
-   BuildBarn RBE: 1,600 CPU cores, 60+ nodes, 20 TB storage, 1,000+
    daily builds.
-   RBE platform delivered in approximately 10 weeks.
-   Build performance improved by up to 3x.
-   Broadcom SDK build infrastructure migrated from Make to Bazel.
-   Hybrid Bazel/Make environments and cross-compilation, including Wind
    River toolchains.
-   Dependency discovery across 100+ mounted filesystems and tool
    locations.
-   Toolchain standardization: Perl, Python and compiler versions.
-   Rootless Podman and Kubernetes-native build execution; Argo
    Workflows.
-   Prometheus/Grafana observability.
-   Coverity automation reduced security turnaround time by 80%.
-   Emulex: 40+ software components integrated into nightly build
    pipelines.
-   Oracle: release orchestration framework; 60+ stable software
    releases.

Use the exact scope and metrics you can confidently explain. Be ready to
describe how each number was measured.

------------------------------------------------------------------------

# 3. CI/CD ownership

## What it means

CI/CD ownership means designing, operating, improving and supporting the
full software delivery path:

1.  Source change and pull request.
2.  Dependency resolution.
3.  Build and compilation.
4.  Unit tests and static analysis.
5.  Integration/model tests.
6.  Artifact creation and publication.
7.  Release approval and promotion.
8.  Monitoring, failure analysis and continuous improvement.

## Your experience connection

-   Jenkins CI/CD integration with Bazel.
-   GitHub workflows and source-control processes.
-   Argo Workflows for Kubernetes-native pipelines.
-   Build infrastructure and RBE platform architecture.
-   Technical leadership across build infrastructure, GitHub and CI/CD.

## Knowledge base

### CI pipeline vs CD pipeline

-   **Continuous Integration (CI):** Frequently integrate code and
    validate changes automatically.
-   **Continuous Delivery:** Keep validated software in a releasable
    state; deployment/release may require approval.
-   **Continuous Deployment:** Automatically deploy every change that
    passes the required checks.

### PR, nightly and release pipelines

  -----------------------------------------------------------------------
  Pipeline                Typical purpose         Typical gates
  ----------------------- ----------------------- -----------------------
  PR/commit               Fast developer feedback Compile affected
                                                  targets, lint, unit
                                                  tests, smoke tests

  Nightly                 Broader validation      Full build, regression,
                                                  integration, model
                                                  tests, coverage, longer
                                                  tests

  Release candidate       Establish release       Pinned dependencies,
                          confidence              full regression,
                                                  artifact verification,
                                                  approvals

  Release promotion       Promote an already      Signature/checksum
                          validated build         verification, metadata,
                                                  approval, publication
  -----------------------------------------------------------------------

### Jenkins knowledge

Know these concepts:

-   Controller and agent architecture.
-   Declarative vs scripted pipelines.
-   Pipeline stages, steps and post actions.
-   Shared libraries for reusable pipeline logic.
-   Agent labels and node allocation.
-   Credentials store and secret injection.
-   Pipeline parameters and environment variables.
-   Parallel stages and matrix builds.
-   Build retention, artifacts and test reports.
-   Restart/retry behavior and pipeline durability.

**Example Jenkinsfile**

``` groovy
pipeline {
  agent { label 'linux-cpp' }

  stages {
    stage('Checkout') {
      steps { checkout scm }
    }

    stage('Build') {
      steps { sh 'cmake -S . -B build && cmake --build build -j' }
    }

    stage('Unit Tests') {
      steps { sh 'ctest --test-dir build --output-on-failure' }
    }

    stage('Publish') {
      when { branch 'main' }
      steps { archiveArtifacts artifacts: 'build/**', fingerprint: true }
    }
  }

  post {
    always {
      junit allowEmptyResults: true, testResults: '**/test-results/*.xml'
    }
  }
}
```

This is an illustrative example, not a claim that this exact pipeline is
used at Cisco.

### GitHub Actions knowledge

Understand:

-   Workflow YAML and event triggers (`pull_request`, `push`,
    `workflow_dispatch`, `schedule`).
-   Jobs, steps, runners and job dependencies (`needs`).
-   Reusable workflows (`workflow_call`).
-   Composite actions.
-   Matrix builds.
-   Concurrency groups and cancellation.
-   Job permissions and least privilege.
-   Environments and required reviewers.
-   Secrets and OIDC-based cloud authentication.
-   Self-hosted runner groups and labels.
-   Required status checks and branch protection/rulesets.

**Example GitHub Actions workflow**

``` yaml
name: native-sdk-ci

on:
  pull_request:
  push:
    branches: [main]

permissions:
  contents: read

jobs:
  build-test:
    runs-on: [self-hosted, linux, cpp]
    steps:
      - uses: actions/checkout@v4

      - name: Configure
        run: cmake -S . -B build

      - name: Build
        run: cmake --build build --parallel 8

      - name: Test
        run: ctest --test-dir build --output-on-failure
```

### Argo Workflows knowledge

-   Kubernetes-native workflow engine.
-   Workflow consists of templates and tasks/steps.
-   DAG templates express dependencies and parallelism.
-   Each task can run in a container.
-   Artifacts and parameters pass data between tasks.
-   Retry strategies, timeouts and exit handlers support failure
    handling.
-   Workflow pods use Kubernetes scheduling, resource requests/limits
    and service accounts.

### Common interview questions

**Q: How do you design a reliable CI pipeline?**

Answer structure: 1. Define fast feedback requirements. 2. Separate PR,
nightly and release validation. 3. Make build environments reproducible.
4. Pin dependencies and toolchain versions. 5. Parallelize independent
tasks. 6. Cache only deterministic outputs with correct keys. 7. Publish
test results and logs even on failure. 8. Track duration, queue time,
failure rate and flaky tests. 9. Make release artifacts immutable and
traceable.

**Q: What is your CI ownership philosophy?**

A strong answer: "CI is a developer-facing product. Its users need
predictable feedback, understandable failures and trustworthy gates. I
measure not only whether jobs run, but queue time, commit-to-green time,
reliability, cache efficiency and how quickly engineers can diagnose
failures."

------------------------------------------------------------------------

# 4. Multi-repository builds and dependency management

## Your experience connection

-   Integrated 40+ software components into automated nightly pipelines
    at Emulex.
-   Worked on Broadcom SDK build infrastructure migration from Make to
    Bazel.
-   Built hybrid Bazel/Make workflows.
-   Investigated dependencies across 100+ mounted filesystems and tool
    locations.

## Knowledge base

### Why multi-repo builds are difficult

-   Repositories can evolve at different speeds.
-   A change in one library can break downstream consumers.
-   Branches may depend on incompatible versions.
-   CI must identify which components are affected.
-   A release must reproduce the exact dependency combination.

### Useful strategies

1.  **Manifest/lock file:** Record exact repository revisions and
    dependency versions.
2.  **Version pinning:** Avoid silently consuming moving branches.
3.  **Dependency graph:** Model upstream/downstream relationships.
4.  **Change-impact analysis:** Build and test affected dependents.
5.  **Compatibility matrix:** Validate supported SDK/adapter/framework
    combinations.
6.  **Reproducible checkout:** Use a known manifest for every build.
7.  **Release manifest:** Record exact source revisions, toolchain and
    artifact versions.

Example manifest concept:

``` yaml
release: sdk-5.2-rc1

components:
  switch-sdk:
    repository: sdk
    revision: 8f31abc
  sai-adapter:
    repository: sai-adapter
    revision: 4c19def
  test-framework:
    repository: switch-tests
    revision: 9a12bcd
```

### Interview question

**Q: How would you prevent incompatible versions across SDK, SAI and
test repositories?**

Answer: "I would use a versioned manifest that pins each repository to a
known commit or release tag. CI would build and test the combination
defined by that manifest. Changes to a shared component would trigger
validation of its affected dependents. A release candidate would retain
the manifest so the exact source combination is reproducible."

------------------------------------------------------------------------

# 5. Large C/C++ builds, Make, CMake and Bazel

## Your experience connection

-   Broadcom SDK migration from Make to Bazel.
-   Bazel/Make hybrid environments.
-   Native and cross-compilation.
-   Wind River toolchains.
-   Hermetic build environments.
-   Toolchain consolidation and dependency discovery.

## C/C++ compilation flow

``` text
Source (.c / .cpp)
       |
       v
Preprocessor
       |
       v
Compiler
       |
       v
Assembly
       |
       v
Object Files (.o)
       |
       v
Linker
       |
       v
Executable / Shared Library
```

### Make vs CMake vs Bazel

  -----------------------------------------------------------------------
  Tool                    Role                    Key idea
  ----------------------- ----------------------- -----------------------
  Make                    Build executor          Executes rules based on
                                                  dependencies and
                                                  timestamps

  CMake                   Build-system generator  Generates native build
                                                  files such as Makefiles
                                                  or Ninja

  Bazel                   Build and test system   Explicit dependency
                                                  graph, action model,
                                                  caching and remote
                                                  execution
  -----------------------------------------------------------------------

### Important C/C++ concepts

-   Header files and include paths.
-   Preprocessor definitions (`-D`).
-   Compiler flags and optimization levels.
-   Object files and static libraries.
-   Shared libraries and dynamic linking.
-   ABI compatibility.
-   Cross-compilation: building on one architecture for another target.
-   Sysroot: target headers and libraries used during cross-compilation.
-   Debug vs release builds.
-   Compiler/toolchain version compatibility.

### Shared library debugging

Commands to know:

``` bash
ldd ./application
readelf -d ./application
nm -D libexample.so
objdump -p ./application
echo "$LD_LIBRARY_PATH"
```

Key concepts:

-   `DT_NEEDED`: shared-library dependencies recorded in ELF metadata.
-   RPATH/RUNPATH: runtime library search paths recorded in an ELF
    binary.
-   `LD_LIBRARY_PATH`: environment variable that can influence
    dynamic-loader lookup.
-   ABI mismatch: binary interface incompatibility between compiled
    components.

**Q: An application builds successfully but fails with "cannot open
shared object file." What do you do?**

1.  Identify the missing library from the error.
2.  Inspect dependencies using `ldd` and `readelf`.
3.  Check whether the library exists on the system.
4.  Check RPATH/RUNPATH and loader configuration.
5.  Check environment variables and container mount paths.
6.  Verify architecture and ABI compatibility.
7.  Fix the packaging or runtime environment rather than applying an
    unexplained temporary workaround.

------------------------------------------------------------------------

# 6. Bazel Remote Build Execution and caching

## Your strongest differentiator

You designed and delivered a BuildBarn-based RBE platform with: - 1,600
CPU cores. - 60+ nodes. - 20 TB storage. - 1,000+ daily builds. -
Approximately 10-week implementation.

## Understand the architecture

``` text
Developer / CI Client
        |
        v
      Bazel
        |
        +--------------------+
        |                    |
        v                    v
   Remote Cache        Remote Execution
        |                    |
        v                    v
  Cache Lookup          Scheduler
                             |
                             v
                       Worker Pool
                             |
                             v
                      Build Actions
                             |
                             v
                       Action Result
                             |
                             v
                      Remote Cache
```

### Remote cache vs remote execution

-   **Remote cache:** Reuses a previously computed action result when
    the action key matches.
-   **Remote execution:** Sends build actions to remote workers for
    execution.
-   They can be used independently or together.

### Important terms

-   **Action:** A build operation with declared inputs, command and
    outputs.
-   **Action key:** Identity derived from action properties and inputs.
-   **CAS (Content Addressable Storage):** Stores content identified by
    its digest.
-   **AC (Action Cache):** Maps an action key to its result.
-   **Cache hit:** A valid result is found and reused.
-   **Cache miss:** The action must execute.
-   **Hermeticity:** The action depends only on declared inputs and
    controlled environment.
-   **Remote worker:** Executes an action on behalf of the client.
-   **Scheduler:** Assigns actions to available execution capacity.

### Cache correctness

A cache is trustworthy only if the action key represents all inputs that
can affect the output.

Potential causes of incorrect cache behavior: - Undeclared input
files. - Different compiler/toolchain versions. - Environment variables
not captured. - Non-deterministic build actions. - Inconsistent platform
properties. - Incorrectly shared cache namespaces.

### Useful metrics

  Metric                  Meaning
  ----------------------- ------------------------------------------------
  Cache hit rate          Fraction of eligible lookups served from cache
  Action execution time   Time spent running build actions
  Queue time              Delay before an action starts
  Worker utilization      How much available execution capacity is used
  CAS storage growth      Content storage consumption
  AC lookup latency       Time to retrieve action-cache entries
  Failed action rate      Fraction of actions that fail

**Q: How would you improve a low remote-cache hit rate?**

1.  Break down hit/miss metrics by target and action type.
2.  Check toolchain and platform consistency.
3.  Look for undeclared inputs and non-hermetic actions.
4.  Compare action keys across supposedly equivalent builds.
5.  Check cache eviction and retention.
6.  Identify workloads that cannot safely share cache entries.
7.  Measure improvement after each change.

**Interview story:** Explain how profiling, cache optimization,
dependency graph tuning and parallel execution contributed to the
up-to-3x build improvement. Be clear about which metric improved and how
it was measured.

------------------------------------------------------------------------

# 7. Shared runners, build farms and capacity management

## Your experience connection

BuildBarn, distributed workers, Linux build infrastructure, rootless
execution and Kubernetes-native transformation.

## Knowledge base

### Runner architecture

A shared runner platform needs: - Registration and discovery. -
Labels/capabilities. - Job queue and scheduling. - CPU, memory and disk
resource management. - Isolation between builds. - Workspace cleanup. -
Worker health checks. - Logs and metrics. - Failure recovery and
autoscaling.

### Important design decisions

  -----------------------------------------------------------------------
  Area                                Design question
  ----------------------------------- -----------------------------------
  Isolation                           Can one job access another job's
                                      files or secrets?

  Scheduling                          How are PR jobs prioritized over
                                      nightly jobs?

  Capacity                            How many concurrent builds can each
                                      worker support?

  Resource limits                     What prevents memory/disk
                                      exhaustion?

  Lifecycle                           How are stale or unhealthy workers
                                      replaced?

  Reproducibility                     Are workers using consistent
                                      toolchains and images?

  Security                            Are jobs unprivileged and secrets
                                      scoped narrowly?
  -----------------------------------------------------------------------

### Capacity estimation

A simple first approximation:

``` text
Required concurrent workers
    = Peak job arrival rate × Average job duration
```

Example: - 12 jobs arrive per minute. - Average execution duration is 5
minutes. - Approximate concurrency required = 60 jobs.

This is a simplified estimate. Real capacity planning must account for
burstiness, queue targets, job-size variation, CPU/memory constraints
and utilization headroom.

### Linux commands

``` bash
uptime
top
free -h
df -h
du -sh *
iostat -xz 1
vmstat 1
ps -ef
journalctl -u <service>
dmesg -T
```

### Interview question

**Q: Developers report long CI queue times. What do you investigate?**

-   Queue time by job class.
-   Runner availability and health.
-   CPU, memory and disk saturation.
-   Jobs waiting for specialized toolchains.
-   Long-running jobs holding scarce workers.
-   Scheduling priority and concurrency limits.
-   Cache misses increasing execution duration.
-   Whether nightly workloads are starving PR builds.

------------------------------------------------------------------------

# 8. Linux, Kubernetes and rootless Podman

## Your experience connection

-   Linux build infrastructure.
-   Kubernetes-native build transformation.
-   Rootless Podman.
-   Argo Workflows.
-   Containerized, reproducible build environments.
-   Toolchain/image separation.

## Knowledge base

### Containers

Understand: - Image vs container. - Image layers and registries. - Bind
mounts and volumes. - Environment variables. - User and group IDs. -
Namespaces and cgroups. - Capabilities and privilege boundaries. - Image
tagging and digest pinning.

### Rootless Podman

Rootless containers run without requiring the container engine to run as
root.

Benefits: - Reduced host privilege exposure. - Better isolation
boundaries. - Useful for shared build infrastructure.

Potential operational issues: - UID/GID mapping. - File ownership on
mounted volumes. - Storage-driver behavior. - Networking
configuration. - Resource limits and host configuration.

### Kubernetes

Know these objects: - Pod. - Deployment. - Job. - PersistentVolume and
PersistentVolumeClaim. - ConfigMap. - Secret. - ServiceAccount. -
Resource requests and limits. - Node selectors, affinity and
tolerations.

Useful debugging:

``` bash
kubectl get pods -A
kubectl describe pod <pod>
kubectl logs <pod>
kubectl logs <pod> --previous
kubectl get events --sort-by=.lastTimestamp
kubectl describe node <node>
kubectl get pvc
```

### Interview question

**Q: A build pod is stuck in Pending. What do you check?**

1.  `kubectl describe pod` and events.
2.  CPU and memory requests versus available node capacity.
3.  PVC binding and storage availability.
4.  Node selectors, affinity and taints/tolerations.
5.  Image pull and service-account configuration where relevant.
6.  Scheduler and cluster-level constraints.

### Your toolchain/container architecture story

Explain: - Tool dependencies were spread across more than 100 mounted
filesystems and locations. - You identified and standardized hidden
dependencies. - You consolidated Perl, Python and compiler versions. -
You separated container images from toolchain storage to avoid oversized
images while retaining consistent environments. - You validated build
execution in Kubernetes.

------------------------------------------------------------------------

# 9. Python, Bash and automation

## Your experience connection

Python, Perl, Bash, Flask, REST APIs, worker automation and release
automation.

## Knowledge base

### Python topics

Be ready to discuss: - Functions, classes and modules. - Exception
handling. - Logging. - Subprocess execution. - File and directory
operations. - JSON/YAML parsing. - REST APIs and HTTP status codes. -
Timeouts and retries. - Parallelism and concurrency. - Unit testing with
pytest.

Example: safe command execution.

``` python
import subprocess

def run_build(command):
    result = subprocess.run(
        command,
        check=False,
        capture_output=True,
        text=True,
        timeout=1800
    )

    if result.returncode != 0:
        raise RuntimeError(
            f"Build failed ({result.returncode}): {result.stderr}"
        )

    return result.stdout
```

### Bash topics

Know: - Exit codes (`$?`). - `set -euo pipefail`. - Pipes and
redirection. - Quoting and variable expansion. - Traps and cleanup. -
Process management. - Signal handling. - `grep`, `awk`, `sed`, `find`,
`xargs`. - Idempotent scripts.

Example:

``` bash
#!/usr/bin/env bash
set -euo pipefail

LOG_DIR="${LOG_DIR:-./logs}"
mkdir -p "$LOG_DIR"

if ! cmake --build build --parallel 8 \
    >"$LOG_DIR/build.log" 2>&1; then
  echo "Build failed; see $LOG_DIR/build.log" >&2
  exit 1
fi

echo "Build completed successfully"
```

### Interview question

**Q: How do you make automation reliable?**

-   Validate inputs.
-   Use explicit timeouts.
-   Check exit codes.
-   Log enough context to debug.
-   Handle exceptions and signals.
-   Make operations idempotent.
-   Avoid hard-coded credentials.
-   Retry only transient failures.
-   Return meaningful failure codes.

------------------------------------------------------------------------

# 10. Build performance and optimization

## Your experience connection

Up to 3x build performance improvement through: - Build profiling. -
Remote-cache optimization. - Dependency graph tuning. - Parallel
execution.

## Knowledge base

### First principle: Measure before optimizing

Break total CI duration into:

``` text
Total CI Duration
  = Queue Time
  + Checkout / Setup
  + Dependency Resolution
  + Build Time
  + Test Time
  + Artifact Publication
```

These are separate bottlenecks. More workers will not necessarily fix a
slow compiler, cache misses or serial dependencies.

### Optimization techniques

  -----------------------------------------------------------------------
  Problem                             Potential solution
  ----------------------------------- -----------------------------------
  Long queue                          Add capacity, improve scheduling,
                                      prioritize PR jobs

  Repeated compilation                Remote/local cache, incremental
                                      builds

  Slow dependency setup               Prebuilt toolchain images,
                                      dependency caching

  Serial build stages                 Parallelize independent targets

  Oversized build graph               Refine dependencies and target
                                      boundaries

  Cache misses                        Fix non-hermetic actions and
                                      inconsistent inputs

  Slow tests                          Parallel execution, test selection,
                                      test profiling

  Disk bottlenecks                    Storage profiling, cleanup and I/O
                                      optimization
  -----------------------------------------------------------------------

### Metrics to report

-   Commit-to-green time.
-   Median and p95 pipeline duration.
-   Queue time.
-   Build duration.
-   Cache hit rate.
-   Worker utilization.
-   Failure rate.
-   Flaky-test rate.
-   Build throughput per day.

**Q: How did you achieve 3x improvement?**

Use a structured response: 1. Establish baseline. 2. Profile where time
was spent. 3. Identify cache and dependency bottlenecks. 4. Tune
execution and parallelism. 5. Validate with representative workloads. 6.
Compare before/after measurements. 7. Monitor for regressions.

Only describe the specific changes you personally worked on and the
measured results you can substantiate.

------------------------------------------------------------------------

# 11. Quality gates, Coverity and test strategy

## Your experience connection

Your resume states that you automated Coverity static analysis and
compliance workflows, reducing security turnaround time by 80%.

## Knowledge base

### Test levels

  -----------------------------------------------------------------------
  Test type               What it validates       Typical CI placement
  ----------------------- ----------------------- -----------------------
  Compile/build           Source compiles and     Every PR
                          links                   

  Lint                    Coding/style/static     Every PR
                          rules                   

  Unit test               Individual              Every PR
                          functions/components    

  Static analysis         Potential               PR or scheduled
                          defects/security issues 

  Model smoke             Basic behavior on       PR where feasible
                          switch model            

  Integration             Component interaction   PR/nightly

  Regression              Existing functionality  Nightly/release

  Soak                    Long-running stability  Nightly/release

  Hardware test           Actual hardware         Lab/release gate
                          behavior                
  -----------------------------------------------------------------------

### Quality gate principles

-   Fast, high-signal checks should run early.
-   Expensive tests should run at the right stage.
-   Failures should be reproducible and actionable.
-   Test reports should be retained.
-   Flaky tests must have owners.
-   A skipped or quarantined test must remain visible.
-   Release gates should be stricter than early developer feedback.

### Coverity concepts

-   Static analysis examines code without executing it.
-   Findings can include memory-safety issues, resource leaks and
    defects.
-   Triage distinguishes real defects from false positives.
-   Baselines help avoid overwhelming teams with existing findings.
-   CI can fail based on new or policy-violating findings.

### Interview question

**Q: How would you introduce quality gates without slowing developers?**

Answer: "I would use a tiered approach. Fast compile, lint and unit
checks run on every PR. Targeted model smoke tests run where practical.
Broader regression, coverage and soak tests run nightly or at
release-candidate stage. I would track flakiness and test duration so
that gates remain high-signal rather than becoming a source of noise."

------------------------------------------------------------------------

# 12. Observability and CI operations

## Your experience connection

Prometheus, Grafana, Splunk and Flask-based developer tools for build
visibility and diagnostics.

## Knowledge base

### Four useful categories of CI observability

1.  **Availability:** Are CI services, schedulers and workers healthy?
2.  **Performance:** Queue time, build time, cache latency and
    throughput.
3.  **Reliability:** Failure rates, worker errors, flaky tests and
    retries.
4.  **Capacity:** CPU, memory, disk, storage growth and worker
    utilization.

### Prometheus concepts

-   Metrics and time series.
-   Labels.
-   Counters, gauges and histograms.
-   Scraping and exporters.
-   PromQL.
-   Alert rules.

Examples of useful metric names (illustrative):

``` text
ci_job_duration_seconds
ci_job_queue_duration_seconds
ci_job_failures_total
rbe_worker_utilization
rbe_cache_hits_total
rbe_cache_misses_total
```

### Example PromQL concepts

``` promql
rate(ci_job_failures_total[5m])
```

Failure counter increase per second over a five-minute window.

``` promql
histogram_quantile(
  0.95,
  sum(rate(ci_job_duration_seconds_bucket[5m])) by (le)
)
```

Illustrative p95 duration calculation, assuming the metric is exported
as a Prometheus histogram.

### Grafana dashboards

Useful panels: - Build throughput per hour/day. - Queue time p50/p95. -
Build duration p50/p95. - Cache hit/miss ratio. - Worker CPU/memory
utilization. - Failed jobs by reason. - Top slow targets. - Storage
consumption and growth.

### Incident response

A good runbook should include: - Symptom and impact. -
Detection/alert. - First diagnostic commands. - Known failure
patterns. - Mitigation steps. - Escalation owner. - Recovery
verification. - Postmortem and follow-up actions.

------------------------------------------------------------------------

# 13. Artifact management and storage

## Your experience connection

Your resume supports distributed build infrastructure and storage
architecture. It does not explicitly detail ownership of a dedicated
artifact registry or complete artifact-retention policy. Prepare this
area as knowledge to demonstrate, not as an established accomplishment.

## Knowledge base

### Distinguish the storage types

  -----------------------------------------------------------------------
  Storage                             Purpose
  ----------------------------------- -----------------------------------
  Source control                      Source code and version history

  Build cache                         Reuse build action outputs

  CI artifacts                        Logs, test reports, packages and
                                      intermediate outputs

  Artifact repository                 Versioned deliverables for
                                      downstream consumers

  Object storage                      Durable storage for large
                                      artifacts, logs and datasets
  -----------------------------------------------------------------------

### Artifact lifecycle

``` text
Build
  |
  v
Package
  |
  v
Generate Metadata
  |
  v
Checksum / Verify
  |
  v
Publish Immutable Artifact
  |
  v
Test / Approve
  |
  v
Promote Same Artifact
  |
  v
Retain / Archive
```

### Key practices

-   Unique version identifiers.
-   Immutable release artifacts.
-   Checksums and integrity verification.
-   Metadata linking artifact to source revision.
-   Retention by artifact type and release status.
-   Access controls.
-   Replication/backup strategy.
-   Lifecycle cleanup.
-   Artifact download verification.

### Interview question

**Q: How would you ensure the artifact tested by QA is the artifact
released to customers?**

Answer: "Build once and promote the same immutable artifact. Record its
version, checksum, source commits, dependency manifest and build
metadata. QA validates that artifact. Release promotion verifies the
checksum and approval state rather than rebuilding from source."

### Useful terms

-   OCI registry.
-   Artifact repository.
-   Content digest.
-   Checksum.
-   Provenance.
-   SBOM.
-   Digital signature.
-   Retention policy.
-   Promotion.
-   Reproducible build.

------------------------------------------------------------------------

# 14. Release promotion and release engineering

## Your experience connection

-   Oracle: Perl-based automated release orchestration framework.
-   Oracle: 60+ stable releases through automated build/release
    workflows.
-   Intuit: automated source promotion and release management.
-   Emulex: Python/Perl release automation and 40+ component nightly
    builds.

## Knowledge base

### Release lifecycle

``` text
Development Branch
       |
       v
Pull Request Validation
       |
       v
Integration Branch
       |
       v
Nightly Regression
       |
       v
Release Branch
       |
       v
Release Candidate
       |
       v
QA Approval
       |
       v
Artifact Promotion
       |
       v
Final Release
```

### Key release concepts

-   Semantic versioning: major.minor.patch.
-   Release branches.
-   Tags.
-   Backports and cherry-picks.
-   Release candidates.
-   Change logs.
-   Build manifests.
-   Artifact immutability.
-   Approval gates.
-   Rollback.
-   Release traceability.

### Pre-gate vs post-gate

**Pre-gate:** Validation required before a change or artifact can
proceed.

Examples: - Compilation. - Unit tests. - Lint. - Static analysis. -
Required reviews.

**Post-gate:** Validation after a stage, often before promotion or
broader deployment.

Examples: - Full integration. - Regression. - Soak. - Release
approval. - Artifact signing and publication checks.

Exact gate placement depends on the team's release policy.

### Interview question

**Q: How do you prevent a release from being different from the tested
build?**

Answer: "Use immutable artifacts and explicit promotion. Each artifact
should carry its source revision, dependency manifest, toolchain
identity and checksum. Test and approve the artifact once, then promote
that same artifact through release stages. Do not silently rebuild
during promotion."

------------------------------------------------------------------------

# 15. Jira, GitHub and engineering traceability

## Your experience connection

-   Jira and Perforce listed in your technical skills.
-   Jira/Perforce integrations at InnoMinds.
-   Release and source promotion experience at Intuit and Oracle.

Your resume supports Jira familiarity and integration experience. If
asked about advanced Jira administration, boards or automation rules,
describe only the functions you have personally used.

## Knowledge base

### Useful Jira concepts

-   Project and issue types.
-   Epic, story, task, bug and sub-task.
-   Workflow statuses and transitions.
-   Components and labels.
-   Fix Version and Affects Version.
-   Sprint and backlog.
-   Boards and filters.
-   Dashboards.
-   Automation rules.
-   Issue links and dependencies.

### Traceability chain

``` text
Jira Issue
    |
    v
Git Branch / Commit
    |
    v
Pull Request
    |
    v
CI Build
    |
    v
Test Results
    |
    v
Release Version
    |
    v
Published Artifact
```

### Interview question

**Q: How do you improve engineering traceability?**

Answer: "Establish a consistent issue key in branch names and PRs, link
PRs and builds to Jira issues, associate release versions with the
relevant fixes, and make CI failures visible to the owning team. The
objective is to trace a customer-facing release back to the exact source
changes and validation evidence."

------------------------------------------------------------------------

# 16. ScaleUp domain knowledge: what to learn beyond your direct experience

This section is domain preparation, not a claim of previous hands-on
implementation.

## Switch SDK

An SDK provides software libraries, APIs and tools to configure, program
and interact with a switch ASIC.

CI implications: - Native compilation. - Toolchain compatibility. - API
and ABI validation. - Unit tests. - Model-based testing. - Versioned SDK
artifacts.

## SAI

Switch Abstraction Interface: a standardized API layer between a network
operating system and vendor-specific switch implementation.

``` text
Network Operating System
          |
          v
         SAI
          |
          v
   Vendor Adapter / SDK
          |
          v
       Switch ASIC
```

CI implications: - API compatibility. - Adapter compilation. -
Configuration tests. - Model behavior validation. - Regression across
supported versions.

## DPDK

Data Plane Development Kit: a set of libraries and drivers for
high-performance packet processing, often in user space.

Learn: - Poll-mode drivers. - Hugepages. - CPU pinning. - NUMA
awareness. - Packet buffers and queues.

## RoCE / RDMA

-   RDMA: Remote Direct Memory Access.
-   RoCE: RDMA over Converged Ethernet.
-   Used for low-latency, high-throughput communication between servers.
-   Relevant to distributed AI workloads and GPU clusters.

Learn: - Congestion control. - Lossless/loss-managed Ethernet
concepts. - QoS and priority. - Queue management. - Telemetry.

## Simulation and hardware-in-the-loop

  -----------------------------------------------------------------------
  Validation                          Meaning
  ----------------------------------- -----------------------------------
  Unit test                           Tests an individual function or
                                      component

  Switch model simulation             Runs software against a model of
                                      switch behavior

  Hardware-in-the-loop                Tests software against actual
                                      physical hardware

  Soak test                           Long-duration test to detect
                                      stability issues
  -----------------------------------------------------------------------

Your CI design contribution is to make each stage reproducible,
observable, appropriately gated and integrated with release evidence.

------------------------------------------------------------------------

# 17. Interview question bank

Practice answering each question aloud in 2--4 minutes.

## CI/CD architecture

1.  Design CI/CD for an SDK with multiple repositories.
2.  How do you divide PR, nightly and release pipelines?
3.  Jenkins vs GitHub Actions: how do you choose?
4.  How do reusable workflows and shared libraries help?
5.  How do you secure self-hosted runners?
6.  How do you prevent one pipeline from consuming all shared capacity?

## Multi-repo and native builds

7.  How do you manage version compatibility across repositories?
8.  How do you troubleshoot a C++ linker error?
9.  Explain static vs dynamic linking.
10. What is a hermetic build?
11. How does Bazel decide whether to rebuild a target?
12. How do you manage cross-compilation toolchains?

## RBE and performance

13. Explain remote cache vs remote execution.
14. What are CAS and AC?
15. What causes cache misses?
16. How do you investigate a low cache hit rate?
17. How do you size a distributed build farm?
18. How do you measure commit-to-green time?

## Linux and containers

19. How do you diagnose a memory leak or OOM kill?
20. How do you debug a missing shared library?
21. What are namespaces and cgroups?
22. What is the benefit of rootless Podman?
23. How do you debug a Pending Kubernetes pod?
24. How do you make containerized builds reproducible?

## Quality and reliability

25. How do you reduce flaky tests?
26. How do you design high-signal quality gates?
27. When should tests be quarantined?
28. What should be included in a CI dashboard?
29. How do you handle a widespread CI outage?
30. How do you perform a useful postmortem?

## Artifacts, releases and Jira

31. How do you ensure the tested artifact is the released artifact?
32. How do you design artifact retention?
33. What are SBOM and artifact signing?
34. How do you handle release branches and backports?
35. How do you connect Jira, GitHub and CI?
36. How do you make release status visible to engineering leadership?

## Networking and simulation

37. What is a switch ASIC?
38. What is SAI?
39. What is the role of a vendor SDK?
40. What is the difference between control plane and data plane?
41. What are ACL and QoS?
42. What is DPDK?
43. What are RDMA and RoCE?
44. Why is simulation useful before hardware validation?
45. How would you integrate a switch model into CI?

------------------------------------------------------------------------

# 18. STAR stories to prepare from your experience

Prepare these as detailed stories. For each one, explain the problem,
your personal contribution, the technical decisions, the result and what
you learned.

  -----------------------------------------------------------------------
  Story                   Situation / challenge   Evidence to emphasize
  ----------------------- ----------------------- -----------------------
  BuildBarn RBE           Need for scalable       10 weeks, 1,600 cores,
  deployment              distributed builds      60+ nodes, 20 TB,
                                                  1,000+ daily builds

  Broadcom SDK migration  Legacy Make-based build Bazel migration,
                          environment             Jenkins integration,
                                                  hybrid builds

  Build performance       Long build cycles       Profiling, cache
                                                  optimization,
                                                  dependency tuning, up
                                                  to 3x improvement

  Toolchain discovery     Dependencies across     Discovery,
                          100+ mounts             consolidation,
                                                  standardization

  Kubernetes              Move to containerized   Podman, Argo Workflows,
  transformation          cloud-native execution  modular
                                                  images/toolchains

  Coverity automation     Slow                    Automation and 80%
                          security/compliance     turnaround-time
                          turnaround              reduction

  Emulex integration      Many software           40+ components in
                          components              nightly pipelines

  Oracle release          Repeatable product      Framework and 60+
  automation              releases                stable releases

  Engineering leadership  Cross-functional        10-member team,
                          platform                architecture,
                          responsibilities        coordination, mentoring
  -----------------------------------------------------------------------

### STAR answer structure

-   **Situation:** What was the engineering or business problem?
-   **Task:** What were you accountable for?
-   **Action:** What did you personally design, implement or change?
-   **Result:** What measurable result followed?
-   **Learning:** What would you improve or do differently?

Avoid saying only "we built it." Make your individual role clear while
giving appropriate credit to the team.

------------------------------------------------------------------------

# 19. Honest gap-management language

Use these formulations when the interviewer asks about areas not
explicitly established in your experience.

### SAI / ASIC

"My experience includes Broadcom SDK build infrastructure and native
software build environments. My primary ownership has been the build and
delivery platform rather than ASIC programming itself. I understand the
role of SAI and the vendor SDK boundary, and I would partner with the
SDK engineers to build the appropriate compatibility and validation
gates."

### DPDK / RoCE

"I have not owned a production DPDK or RoCE implementation. I understand
their relevance to high-performance data-center networking, and I am
building deeper domain knowledge. My immediate contribution would be
reliable build, test and release infrastructure for those software
components."

### Hardware-in-the-loop

"My resume is strongest in build infrastructure and software CI. I would
work with QA to integrate hardware-lab scheduling, test execution,
result collection and cleanup into the pipeline, while ensuring that
lab-dependent tests do not block unrelated developer workflows."

### Artifact repositories

"My experience includes distributed build storage and release
automation. For a formal artifact lifecycle, I would establish immutable
versioning, source and dependency metadata, checksums, retention
policies and controlled promotion. I would be precise about which
repository or registry products I have used hands-on."

### Advanced Jira administration

"I have worked with Jira and integrations with source-control/release
workflows. I understand the traceability model connecting issues,
commits, PRs, CI results and release versions. I would need to
distinguish that experience from administering every advanced Jira
workflow feature."

------------------------------------------------------------------------

# 20. Final revision checklist

Before the technical interviews, make sure you can do the following
without notes:

-   [ ] Explain your BuildBarn architecture on a whiteboard.
-   [ ] Explain remote cache, remote execution, CAS and AC.
-   [ ] Describe the Broadcom Make-to-Bazel migration.
-   [ ] Explain how you achieved the reported 3x build improvement.
-   [ ] Explain the 100+ mount dependency discovery problem.
-   [ ] Compare Jenkins, GitHub Actions and Argo Workflows.
-   [ ] Explain a complete multi-repository SDK pipeline.
-   [ ] Debug a missing `.so` library.
-   [ ] Explain static vs dynamic linking.
-   [ ] Explain a Kubernetes Pending pod.
-   [ ] Explain rootless Podman and build isolation.
-   [ ] Describe how to reduce flaky tests.
-   [ ] Design an immutable artifact promotion flow.
-   [ ] Explain your Coverity automation and its 80% improvement.
-   [ ] Explain Jira-to-GitHub-to-release traceability.
-   [ ] Explain SDK, SAI, ASIC, DPDK and RoCE at a conceptual level.
-   [ ] Explain how model simulation and hardware testing fit into CI.
-   [ ] Prepare five detailed STAR stories.

## Closing positioning

Your strongest value to ScaleUp is the ability to turn a complex native
software build ecosystem into a scalable, reproducible and observable
engineering platform.

The core message to repeat throughout the interview:

**"I build the engineering infrastructure that allows software teams to
build, test and release complex products faster and more reliably. My
experience spans distributed execution, native toolchains, CI/CD
architecture, Kubernetes-based execution, quality automation and release
engineering. I can bring that foundation to ScaleUp while partnering
with networking specialists on the ASIC-specific validation
requirements."**
