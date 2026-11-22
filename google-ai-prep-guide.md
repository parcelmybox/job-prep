# Upscale AI (ScaleUp) — Onsite Interview Panel & Technical Deep-Dive Guide

**Role:** Senior Staff DevOps Engineer – ScaleUp  
**Location:** Santa Clara, CA (Ionosphere - 1st Floor)  
**Company Context:** Valued at $2B ($500M+ raised), building custom AI networking switch silicon (**SkyHammer**) and open Ethernet fabrics (**UALink**, **ESUN**). ScaleUp builds the Switch SDK, SAI adapters, SONiC integration, and switch simulation models.

---

## 1. Interview Panel Strategy & Focus Matrix

### 2:00 – 2:45 PM PST | Karthikesan Iyyanappan
* **Role/Background:** Distinguished Engineer / Director – Network & Security (Ex-Astera Labs, Innovium)
* **Likely Focus Areas:**
  * Infrastructure architecture & bare-metal/lab host management.
  * Linux & container security (rootless execution, SELinux, isolation boundaries).
  * Multi-tenant build farm isolation without breaking native C/C++ builds.
  * Enterprise secrets management (Vault/Conjur, Jenkins, Argo, Zookeeper) and supply-chain security.
* **What to Emphasize from Your Experience:**
  * **Security & Isolation:** Rootless Podman execution for OS-independent, isolated builds without root daemon exposure.
  * **Static Analysis Automation:** Automated Coverity security & compliance workflows at Cisco, cutting security turnaround time by **80%**.
  * **High-Speed Execution:** Delivering the 1,600-core BuildBarn RBE platform in **10 weeks** (demonstrates startup execution speed).

### 2:45 – 3:30 PM PST | Vipul Ramani
* **Role/Background:** SRE Leader / Cloud Architect (Ex-Palo Alto Networks Principal SRE; CKA/CKS, Terraform, Ansible, Zero Trust)
* **Likely Focus Areas:**
  * Kubernetes-native CI/CD architecture, pod scheduling, tainted nodes, and autoscaling.
  * Observability, SLOs/SLIs for CI pipelines, and diagnosing cluster/storage bottlenecks.
  * Zero-trust CI identity (OIDC vs. static credentials) and Infrastructure-as-Code.
* **What to Emphasize from Your Experience:**
  * **K8s-Native Build Transformation:** Migrating legacy build infrastructure to Kubernetes + Argo Workflows.
  * **Storage & Image Optimization:** Separating container images from toolchain storage (discovered across **100+ mounted filesystems**) to prevent multi-gigabyte image bloat and slow pod startups.
  * **Observability:** Prometheus & Grafana dashboards monitoring queue time, worker utilization, and RBE cache hit/miss rates.

### 3:30 – 4:15 PM PST | Matthew Jino Kim
* **Role/Background:** Software Engineer, AI Networks (SONiC, Scale-Out/Scale-Up networking software)
* **Likely Focus Areas:**
  * Developer experience ("commit-to-green" latency) and fast PR feedback loops.
  * Debugging native C/C++ & Python SDK builds (Make, CMake, Bazel, cross-compilation, shared libraries).
  * Handling multi-repo dependencies (Switch SDK + SAI + simulation models) and eliminating flaky tests.
* **What to Emphasize from Your Experience:**
  * **Broadcom SDK Migration:** Migrating Broadcom switch SDK builds from Make to Bazel, enabling distributed execution and hybrid Bazel/Make workflows.
  * **3x Build Speedup:** Profiling, dependency-graph tuning, and remote cache optimization that improved build throughput by up to **3x**.
  * **Developer Self-Service:** Building Flask-based internal portals/dashboards so developers can diagnose failures without waiting on DevOps.

### 4:15 – 5:00 PM PST | Arunkumar Arumugam
* **Role/Background:** Engineering / Software Leadership
* **Likely Focus Areas:**
  * End-to-end ownership of CI/CD and release promotion (pre-gates vs. post-gates, immutable artifacts).
  * Engineering traceability via GitHub + Jira (linking PRs, builds, releases, and tracking CI debt).
  * Leading cross-functional initiatives and operating at startup velocity.
* **What to Emphasize from Your Experience:**
  * **Release Engineering Rigor:** Delivering **60+ stable releases** via automated orchestration at Oracle; integrating **40+ components** into nightly pipelines at Emulex.
  * **Scale & Readiness:** Architecting Cisco's next-gen build platform to absorb **3x+ AI-driven commit growth** without proportional hardware spend.
  * **Leadership:** Leading a **10-member global platform team** while staying deeply hands-on in architecture and troubleshooting.

---

## 2. Technical Deep Dive: Build Runner Isolation & Linux Security

### How to Isolate Shared Build Runners Without Breaking Native C/C++ Builds
Native C/C++ SDK builds often require specific kernel headers, custom mount paths, debuggers (`gdb`/`ptrace`), or FUSE/overlay filesystems that break under overly restrictive container defaults.

1. **Kubernetes Node Isolation (Taints, Tolerations & Node Affinity):**
   * **Workload Segregation:** Dedicate bare-metal or high-CPU/high-NVMe nodes to heavy C/C++ compilation and switch simulation using taints (e.g., `kubectl taint nodes <node> workload=native-sdk:NoSchedule`).
   * **Targeted Scheduling:** Only CI runner pods with matching `tolerations` and `nodeAffinity` schedule onto those nodes, preventing noisy-neighbor interference from lightweight linters or web services.
   * **Ephemeral Workspaces:** Mount ephemeral NVMe `emptyDir` or local CSI volumes per build pod so workspaces are wiped immediately upon pod termination—zero cross-job file leakage.

2. **Rootless Containers (Podman) & User Namespaces:**
   * **Eliminate Root Daemon Risk:** Unlike standard Docker (which runs a privileged root daemon), rootless Podman maps container `UID 0` to an unprivileged host UID via `/etc/subuid` and `/etc/subgid`. Even if a malicious build script escapes the container, it holds zero root privileges on the host.
   * **Decoupled Toolchain Mounts:** Mount standardized toolchains (compilers, Wind River/cross-compilers, Python/Perl runtimes) as **read-only (`:ro`)** hostPath or CSI volumes into the container. Builds can execute compilers freely but cannot mutate or poison shared toolchain binaries.

3. **SELinux & Container Security Controls:**
   * **Mandatory Access Control (MAC):** With SELinux in `Enforcing` mode, container engines assign a unique MCS (Multi-Category Security) label (e.g., `system_u:system_r:container_t:s0:c102,c450`) to each container process and its private workspace. Even if two builds share the same host UID, the kernel blocks Container A from reading Container B's files.
   * **Volume Relabeling Pitfalls in C/C++ Builds:**
     * `:Z` (private relabel) changes file labels so *only* that container can access the directory—**never use `:Z` on shared read-only toolchain mounts**, or you will break concurrent builds.
     * `:z` (shared relabel) allows multiple containers to share a volume, or better yet, mount read-only toolchains with standard `container_file_t` labels (`ro,nosuid,nodev`).
   * **Capabilities & Seccomp:** Drop all Linux capabilities (`--cap-drop=ALL`) by default, adding back only minimal required capabilities (e.g., `SYS_PTRACE` strictly for unit-test crash dumps/sanitizers like ASan/TSan) rather than ever running `--privileged`.

---

## 3. Technical Deep Dive: Secrets & Configuration Management Across CI/CD

### Core Principle
Never bake secrets into container images, Git repositories, or long-lived environment variables. Authenticate workloads dynamically via identity (OIDC / K8s ServiceAccounts) and inject short-lived secrets into memory (`tmpfs`) only for the duration of the build step.

### 1. Jenkins Secrets Management
* **Built-in Credentials Store:** Secrets (`Secret text`, `SSH Username with private key`, `Certificate`) are encrypted at rest on the controller using AES (`master.key` + `hudson.util.Secret`).
* **Runtime Masking & Scoping:** Use the `withCredentials` block in Declarative/Scripted pipelines so credentials are injected only into specific steps and automatically masked (`****`) in console logs. Folder-level credential scoping ensures Team A's jobs cannot access Team B's signing keys.
* **External Secrets Integration:** For enterprise scale, integrate Jenkins with CyberArk Conjur or HashiCorp Vault plugins so Jenkins fetches dynamic, short-lived tokens at runtime rather than storing static secrets on the controller disk.

### 2. CyberArk Conjur (Enterprise Secrets Management)
* **Architecture:** Policy-as-Code RBAC model defining Hosts (applications/runners), Layers (groups of hosts), Variables (secrets), and Privileges (`read`, `execute`).
* **Authenticators (`authn-k8s` / `authn-jwt`):**
  * Instead of storing a static Conjur API key inside a CI runner, use **JWT/OIDC or Kubernetes authentication**.
  * A Kubernetes pod presents its projected ServiceAccount JWT to Conjur; Conjur validates the token against the K8s API server/OIDC provider and returns a short-lived access token (typically 8-minute TTL).
* **Summon Pattern:** Use `summon` (CyberArk's CLI wrapper) to fetch secrets from Conjur and inject them into the build subprocess's environment memory—writing nothing to disk and automatically clearing them when the process exits.

### 3. Argo Workflows (Kubernetes-Native CI)
* **Native Kubernetes Secrets & RBAC:** Reference K8s `Secret` objects via `secretKeyRef` (env vars) or volume mounts (`tmpfs` in RAM) scoped strictly to the workflow's `ServiceAccount` using least-privilege K8s RBAC.
* **External Secrets Operator (ESO):** Sync secrets from Conjur, Vault, or AWS Secrets Manager into native Kubernetes Secrets automatically with rotation policies.
* **Artifact Repository Credentials:** Configure S3/Artifactory credentials in the `workflow-controller-configmap` or dedicated per-namespace Secrets so individual workflow YAML definitions never contain storage keys.
* **Log Redaction:** Avoid echoing environment variables (`env` / `printenv`) in Argo step containers, and leverage Argo's built-in masking for secret parameters.

### 4. Apache ZooKeeper (Distributed Coordination vs. Secrets)
