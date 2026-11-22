## 6. Whiteboard Architecture Diagrams (ASCII)

### Architecture A: BuildBarn RBE Platform (1,600 Cores | 60+ Nodes | 20 TB | 1,000+ Builds/Day)

```text
+-----------------------------------------------------------------------------------+

|                        DEVELOPER / CI CLIENT LAYER                                |
|  [ Developer Workstations ]            [ CI Orchestrators: Jenkins / GitHub ]     |
|              \                                          /                         |
|               +----------> [ Bazel Client ] <----------+                          |
|                    (Action Graph + Digest Calculation)                            |
+-------------------------------------+---------------------------------------------+
                                      | gRPC (Remote Execution API v2 + mTLS)
                                      v
+-----------------------------------------------------------------------------------+

|                         BUILDBARN CONTROL & STORAGE PLANE                         |
|                                                                                   |
|   +-----------------------+                 +---------------------------------+   |
|   |   bb-frontend (Proxy) |---------------->|     bb-storage (20 TB NVMe)     |   |
|   | - Auth / Routing      |                 |  +---------------------------+  |   |
|   | - Instance Prefixing  |                 |  | Action Cache (AC)         |  |   |
|   +-----------+-----------+                 |  | Key: ActionDigest -> Out  |  |   |
|               |                             |  +---------------------------+  |   |
|               | Cache Miss                  |  | Content Addressable (CAS) |  |   |
|               v                             |  | Key: SHA256 -> File Blobs |  |   |
|   +-----------------------+                 |  +---------------------------+  |   |
|   |     bb-scheduler      |                 +----------------+----------------+   |
|   | - Platform Queues     |                                  ^                    |
|   | - Fair-Share / PR>Nightly                                | Read Inputs /      |
|   | - Worker Health/Drain |                                  | Write Outputs      |
|   +-----------+-----------+                                  |                    |
+---------------|----------------------------------------------|--------------------+

                | gRPC Task Dispatch                           |
                v                                              |
+-----------------------------------------------------------------------------------+

|                   DISTRIBUTED EXECUTION FARM (60+ Nodes / 1,600 Cores)            |
|                                                                                   |
|  +-------------------------------------+   +-----------------------------------+  |
|  | Worker Node 1..N (Tainted K8s/Bare) |   | Worker Node N+1 (Cross-Compile)   |  |
|  |  +-------------------------------+  |   |  +-----------------------------+  |  |
|  |  | bb-worker (Resource Mgmt)     |  |   |  | bb-worker                   |  |  |
|  |  +---------------+---------------+  |   |  +--------------+--------------+  |  |
|  |                  |                  |   |                 |                 |  |
|  |                  v                  |   |                 v                 |  |
|  |  +-------------------------------+  |   |  +-----------------------------+  |  |
|  |  | bb-runner (Rootless Podman /  |  |   |  | bb-runner (Wind River /     |  |  |
|  |  | Isolated Sandbox + SELinux)   |  |   |  | Target Sysroot Container)   |  |  |
|  |  +-------------------------------+  |   |  +-----------------------------+  |  |
|  +-------------------------------------+   +-----------------------------------+  |
+-----------------------------------------------------------------------------------+
                                      |
                                      v
+-----------------------------------------------------------------------------------+

|                     OBSERVABILITY & DEVELOPER VISIBILITY                          |
|   [ Prometheus ] ---> [ Grafana Dashboards: Hit Rate, Queue Time, Worker CPU ]    |
|   [ Splunk Logs ]     [ Flask Self-Service Portal: Action Diagnostics & Stats ]   |
+-----------------------------------------------------------------------------------+
```

**Whiteboard Talking Points for Architecture A:**
* **Why `bb-frontend` + `bb-scheduler` separation matters:** `bb-frontend` handles authentication and fast Action Cache (AC) lookups without touching execution workers; only cache misses hit `bb-scheduler`.
* **Platform-aware routing:** `bb-scheduler` routes actions based on Bazel `platform` properties (e.g., standard Linux x86_64 vs. Wind River cross-compilation toolchains) and prioritizes PR builds over nightly builds.
* **Hermeticity guarantee:** `bb-runner` mounts only declared CAS inputs into an isolated, ephemeral rootless container—if a target uses an undeclared header from `/usr/include`, the build fails immediately rather than poisoning the cache.

---

### Architecture B: Kubernetes/Argo Native Build & Decoupled Toolchain Storage

```text
+-----------------------------------------------------------------------------------+

|                       CI TRIGGER & IDENTITY LAYER                                 |
|  [ GitHub PR / Push ] ---> [ Argo Events / Webhook ] ---> [ Argo Workflows DAG ]  |
|                                                                  |                |
|  [ CyberArk Conjur / Vault ] <--- (OIDC / K8s SA JWT) -----------+                |
|        (Injects short-lived tokens into tmpfs RAM only)                           |
+------------------------------------------------------------------+----------------+
                                                                   |
                                  Schedules Pods on Tainted Nodes  |
                                  (workload=native-sdk:NoSchedule) |
                                                                   v
+-----------------------------------------------------------------------------------+

|                     KUBERNETES BUILD WORKER NODE (SELinux Enforcing)              |
|                                                                                   |
|  +-----------------------------------------------------------------------------+  |
|  |  EPHEMERAL BUILD POD (Rootless Podman / Unprivileged UID Mapping)           |  |
|  |                                                                             |  |
|  |  +---------------------------------+   +---------------------------------+  |  |
|  |  | Lightweight Base OS Image       |   | Ephemeral Workspace (emptyDir)  |  |  |
|  |  | (~200 MB: glibc, bash, git)     |   | - Source checkout & build/ out  |  |  |
|  |  | Fast pull, zero compiler bloat  |   | - Wiped immediately on Pod exit |  |  |
|  |  +---------------------------------+   +---------------------------------+  |  |
|  |                   |                                     ^                   |  |
|  |                   +------------------+------------------+                   |  |
|  |                                      | Bind-Mounted (:ro)                   |  |
|  +--------------------------------------|--------------------------------------+  |
|                                         |                                         |
|  +--------------------------------------v--------------------------------------+  |
|  |  SHARED READ-ONLY TOOLCHAIN VOLUME (PV / NFS / Local NVMe Cache)            |  |
|  |  (Consolidated from 100+ legacy mounts into versioned immutable paths)      |  |
|  |                                                                             |  |
|  |  /toolchains/gcc/12.3.0/     /toolchains/python/3.11/     /toolchains/      |  |
|  |  /toolchains/windriver/x.y/  /toolchains/cmake/3.28/      bazel/7.1.0/      |  |
|  +-----------------------------------------------------------------------------+  |
+-----------------------------------------------------------------------------------+
```

**Whiteboard Talking Points for Architecture B:**
* **Why decouple container images from toolchains:** Native C/C++ SDK toolchains (GCC, LLVM, Wind River, Python/Perl dependencies) easily reach 10–30 GB. Baking them into Docker images causes multi-minute image pulls and registry bottlenecks. Keeping a ~200 MB base container and mounting versioned `/toolchains/<name>/<version>` read-only (`:ro`) gives instant pod startup and clean multi-version support.
* **Security + Native Build Compatibility:** Rootless execution + SELinux MCS labels isolate concurrent pods' `emptyDir` workspaces while allowing shared read-only access to `/toolchains`.
