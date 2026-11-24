# Kubernetes (K8s) Architecture & Issue Tracing Notes

## 1. Architecture & Component Purpose

Kubernetes follows a **Control Plane + Worker Node** architecture to maintain the *desired state* of containerized workloads.

### Control Plane (The Cluster Brain)
* **`kube-apiserver`**: The central REST API gateway. Validates and configures data for all API objects (Pods, Services, etc.). Every internal and external request passes through here.
* **`etcd`**: Distributed, consistent key-value store. Acts as the single source of truth for all cluster state and configuration.
* **`kube-scheduler`**: Watches for unscheduled (`Pending`) Pods and assigns them to an optimal Worker Node based on resource requests, taints/tolerations, and affinity rules.
* **`kube-controller-manager`**: Runs continuous reconciliation loops (Node, ReplicaSet, Endpoints, HPA controllers) to drive current cluster state toward desired state.
* **`cloud-controller-manager`**: Interfaces with underlying cloud provider APIs to manage cloud-specific load balancers, storage volumes, and node instances.

### Worker Nodes (The Compute Muscle)
* **`kubelet`**: Node-level agent that communicates with the API server, reads `PodSpecs`, and ensures containers are running and healthy.
* **Container Runtime (`containerd` / CRI-O)**: Pulls container images and manages container execution lifecycles via the Container Runtime Interface (CRI).
* **`kube-proxy`**: Maintains node network rules (`iptables` / IPVS) to route traffic to Pods. *(Often replaced by eBPF plugins like Cilium).*

### Core Add-ons
* **CNI (Container Network Interface)**: Handles Pod-to-Pod networking and IP address allocation (e.g., Calico, Cilium).
* **CSI (Container Storage Interface)**: Connects external block/file storage systems to Pods as PersistentVolumes.
* **CoreDNS**: Provides internal cluster DNS and service discovery.

---

## 2. Top Areas for Issue Tracing

When diagnosing cluster failures, trace issues systematically from the **API/Controller layer** down to **Node/Runtime execution**.

### Area A: Resource Exhaustion & Scheduling Failures
**Symptoms:** Pods stuck in `Pending`, `OOMKilled` (Exit Code 137), `Evicted` pods, or severe CPU throttling.

* **Root Causes:**
  1. **Insufficient Cluster Capacity:** Worker nodes lack unallocated CPU or RAM to satisfy Pod `requests`.
  2. **Missing/Misconfigured Requests & Limits:** Pods without `requests` allow overcommitment until nodes hit memory pressure and evict workloads. Tight memory `limits` trigger `OOMKilled`.
  3. **Namespace Quotas:** A `ResourceQuota` or `LimitRange` blocks new Pod creation even if nodes have free capacity.
  4. **Scheduling Constraints:** Taints without matching tolerations, strict `nodeAffinity`, or unbound PersistentVolumeClaims (`PVC`).
* **Tracing Commands:**
  ```bash
  kubectl describe pod <pod-name>          # Look for 'FailedScheduling' or 'OOMKilled' events
  kubectl describe node <node-name>        # Check 'Allocated resources' vs 'Capacity' and Pressure conditions
  kubectl get resourcequota -A             # Verify namespace limits aren't maxed out
  kubectl top nodes && kubectl top pods    # Compare actual live usage against requests
  ```

### Area B: Autoscaling Not Triggered (HPA & Cluster Autoscaler / Karpenter)
**Symptoms:** Traffic spikes or `Pending` queues grow, but Pod replicas or Node counts remain flat.

* **Root Causes (Horizontal Pod Autoscaler - HPA):**
  1. **Missing `metrics-server`:** HPA cannot read CPU/memory utilization if the metrics pipeline is down.
  2. **Missing Resource `requests`:** HPA calculates utilization as a percentage of `requests`. Without `requests` defined on *all* containers in a Pod, HPA cannot compute scaling metrics.
  3. **Max Replicas Reached:** Deployment has already hit `spec.maxReplicas`.
* **Root Causes (Node Autoscaling - Cluster Autoscaler / Karpenter):**
  1. **Pod Disruption Budgets (PDBs) / Local Storage:** Prevents scale-down, or cloud autoscaling group (`ASG`) limits prevent scale-up.
  2. **Unschedulable Reasons Ignored:** Node autoscalers only add nodes if a new node will actually satisfy the Pod's constraints (e.g., if a `PVC` is stuck in a different Availability Zone, adding nodes won't help).
* **Tracing Commands:**
  ```bash
  kubectl describe hpa <hpa-name>          # Check 'Conditions' (e.g., FailedGetResourceMetric, ScalingLimited)
  kubectl get apiservices | grep metrics   # Verify metrics.k8s.io is Available
  kubectl logs -n kube-system -l app=cluster-autoscaler  # Inspect node scale-up decisions
  ```

### Area C: Container Crash Loops & Startup Failures
**Symptoms:** `CrashLoopBackOff`, `ImagePullBackOff`, `CreateContainerConfigError`.

* **Root Causes:**
  1. **Application Crash / Bad Entrypoint:** Container starts, exits with non-zero code, and `kubelet` applies exponential backoff.
  2. **Failing Probes:** Aggressive `livenessProbe` kills slow-starting containers before initialization finishes (use a `startupProbe` instead).
  3. **Missing Configs/Secrets:** Referenced `ConfigMap` or `Secret` does not exist in the namespace.
* **Tracing Commands:**
  ```bash
  kubectl logs <pod-name> --previous       # View logs from the crashed container instance
  kubectl get events --sort-by='.lastTimestamp' -n <namespace>
  ```

### Area D: Networking & Service Discovery Breakdowns
**Symptoms:** `502/504` timeouts, Pods unable to reach external APIs or internal Services, `NodeNotReady`.

* **Root Causes:**
  1. **Selector Mismatch:** Service `spec.selector` labels do not match Pod labels (results in empty `Endpoints`).
  2. **DNS Bottlenecks:** `CoreDNS` pods are throttled or `ndots:5` configuration causes excessive DNS query amplification.
  3. **IP Exhaustion:** Subnet IP pool exhausted by CNI plugin, preventing new Pods from receiving IPs.
* **Tracing Commands:**
  ```bash
  kubectl get endpoints <service-name>     # If '<none>', Service selector doesn't match any Ready Pods
  kubectl get pods -n kube-system -l k8s-app=kube-dns
  ```
