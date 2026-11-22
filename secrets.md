# Enterprise Secrets Management & Software Supply-Chain Security Prep Guide

---

## 1. Enterprise Secrets Management Architecture

| Component / Tool | Role in Enterprise CI/CD | How Authentication & Secret Delivery Works |
| :--- | :--- | :--- |
| **HashiCorp Vault / CyberArk Conjur** | Central Secret Engine & Policy Authority | Authenticates workloads via **OIDC / JWT** or **Kubernetes Auth** (verifying Pod ServiceAccount tokens), issuing dynamic, short-lived credentials (e.g., temporary AWS STS tokens, ephemeral Artifactory tokens) with automatic TTL revocation. |
| **Kubernetes Delivery (`ESO` / `CSI Driver`)** | Secret Injection Layer | **External Secrets Operator (ESO)** syncs secrets into native K8s `Secret` objects, while the **Secrets Store CSI Driver** mounts secrets directly into container `tmpfs` (RAM) so they never touch disk or etcd. |
| **Argo Workflows / Argo CD** | Cloud-Native CI/CD Orchestration | Pods run with dedicated `ServiceAccount` identities; steps fetch secrets from Vault/Conjur at runtime via CSI `tmpfs` mounts or OIDC federation—never hardcoding credentials in workflow YAML. |
| **Jenkins** | Legacy / Hybrid CI Orchestrator | Uses the **HashiCorp Vault Plugin** or **CyberArk Conjur Plugin** via AppRole or OIDC/JWT auth to inject masked environment variables (`withVault` / `withCredentials`) scoped strictly to a single build step and wiped upon completion. |
| **Apache ZooKeeper** | Distributed Coordination & Config Store | **Anti-pattern for raw secrets:** ZooKeeper stores znodes unencrypted in memory/snapshots by default. Store only non-sensitive config/service discovery in ZooKeeper (protected with SASL/Kerberos + mTLS ACLs) and keep secret pointers referencing Vault/Conjur paths. |

### Key CI/CD Secrets Rules
* **Eliminate "Secret Zero":** Never store static Vault tokens or Conjur API keys in CI variables. Bootstrap trust using Kubernetes `ServiceAccount` JWTs or OIDC identity tokens.
* **Prevent Cache & Process Leaks:** Never pass secrets via CLI flags (visible in `ps aux` and `bazel aquery`), never bake them into Docker layers (`ARG`/`ENV`), and never mount secret files inside Bazel RBE/CAS inputs.

---

## 2. Concrete Implementation: Vault CSI Driver + Argo Workflows

Using the **Secrets Store CSI Driver** (`provider: vault`), Vault authenticates the Argo Workflow pod's `ServiceAccount` JWT and mounts the secret directly into an in-memory `tmpfs` volume (`/mnt/secrets-store`), leaving **zero footprint in Kubernetes `etcd` or node disks**.

### Step A: `SecretProviderClass` (Maps Vault Secrets to Pod `tmpfs`)
```yaml
apiVersion: secrets-store.csi.x-k8s.io/v1
kind: SecretProviderClass
metadata:
  name: vault-ci-sdk-creds
  namespace: argo-ci
spec:
  provider: vault
  parameters:
    vaultAddress: "https://example.com"
    roleName: "argo-ci-builder-role"        # Bound to K8s ServiceAccount `argo-builder-sa`
    objects: |
      - objectName: "artifactory-token"
        secretPath: "secret/data/ci/artifactory"
        secretKey: "readonly_token"
      - objectName: "cosign-kms-key-uri"
        secretPath: "secret/data/ci/signing"
        secretKey: "kms_uri"
```

### Step B: Argo `WorkflowTemplate` Mounting Vault Secrets into RAM (`tmpfs`)
```yaml
apiVersion: argoproj.io/v1alpha1
kind: WorkflowTemplate
metadata:
  name: hermetic-release-pipeline
  namespace: argo-ci
spec:
  serviceAccountName: argo-builder-sa
  entrypoint: build-and-sign

  # Mount Vault CSI volume at the workflow pod level (in-memory tmpfs)
  volumes:
    - name: secrets-store-inline
      csi:
        driver: secrets-store.csi.k8s.io
        readOnly: true
        volumeAttributes:
          secretProviderClass: "vault-ci-sdk-creds"

  templates:
    - name: build-and-sign
      container:
        image: your-registry/bazel-cosign-runner:latest
        command: ["/bin/bash", "-c"]
        args:
          - |
            set -euo pipefail
            # Read ephemeral token from RAM (never echoed to stdout or Bazel action cache)
            export ARTIFACTORY_TOKEN=\$(cat /mnt/secrets-store/artifactory-token)

            # 1. Run hermetic Bazel multi-platform build
            bazel build //:hello_release

            # 2. Generate CycloneDX SBOM for the release artifact
            syft bazel-bin/hello_release.tar.gz -o cyclonedx-json=bazel-bin/hello_release.sbom.json

            # 3. Sign release tarball & attach SBOM attestation using Cosign + Vault/KMS
            KMS_URI=\$(cat /mnt/secrets-store/cosign-kms-key-uri)
            cosign sign-blob \
              --key "\$KMS_URI" \
              --bundle bazel-bin/hello_release.tar.gz.bundle \
              bazel-bin/hello_release.tar.gz
        volumeMounts:
          - name: secrets-store-inline
            mountPath: "/mnt/secrets-store"
            readOnly: true
```

---

## 3. Alternative Delivery: External Secrets Operator (ESO) YAML

When an application or legacy tool strictly requires a native Kubernetes `Secret` (for example, `imagePullSecrets` or environment variable injection via `secretKeyRef`), use **External Secrets Operator (ESO)** with short `refreshInterval` rotation:

```yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: ci-registry-pull-secret
  namespace: argo-ci
spec:
  refreshInterval: "15m"                    # Automatically rotates credentials every 15 minutes
  secretStoreRef:
    name: vault-backend-store
    kind: ClusterSecretStore
  target:
    name: regcred-secret                    # Native K8s Secret created/updated by ESO
    creationPolicy: Owner
    template:
      type: kubernetes.io/dockerconfigjson
  data:
    - secretKey: .dockerconfigjson
      remoteRef:
        key: secret/data/ci/registry
        property: dockerconfigjson
```

---

## 4. Software Supply-Chain Security (SLSA, SBOM & Cosign Commands)

| Security Pillar | Standard / Tool | Purpose |
| :--- | :--- | :--- |
| **Build Provenance** | **SLSA Level 3+** | Ensures builds run on isolated, ephemeral CI runners with non-falsifiable build provenance generated by the CI platform. |
| **Dependency Inventory** | **Syft / Trivy** (`CycloneDX` / `SPDX`) | Produces a machine-readable SBOM listing every compiled library and SDK version inside the release binary/archive. |
| **Cryptographic Signing** | **Sigstore (`Cosign`)** | Signs container images and binary tarballs using either **keyless OIDC** (ephemeral Fulcio certs + Rekor transparency log) or **KMS/Vault transit keys**. |
| **Admission Enforcement** | **Kyverno / OPA Gatekeeper** | Blocks deployment of any unsigned image or artifact missing a valid SBOM/SLSA attestation in production clusters. |

### Essential Cosign & SBOM CLI Commands

#### 1. Keyless OIDC Signing & Verification (CI Pipelines with OIDC Identity)
```bash
# Sign a container image using the CI runner's OIDC token (no static private keys!)
cosign sign --yes ://example.com...

# Verify container image signature and enforce exact CI workflow identity
cosign verify \
  --certificate-identity="https://github.com" \
  --certificate-oidc-issuer="https://githubusercontent.com" \
  ://example.com...
```

#### 2. Signing Binary Tarballs / RPMs (`sign-blob` + Bundle Verification)
```bash
# Sign a release tarball using a HashiCorp Vault Transit key (private key never leaves Vault)
cosign sign-blob \
  --key "hashivault://ci-release-signing-key" \
  --bundle hello_release.tar.gz.bundle \
  hello_release.tar.gz

# Verify the release tarball offline or in downstream deployment gates
cosign verify-blob \
  --key "hashivault://ci-release-signing-key" \
  --bundle hello_release.tar.gz.bundle \
  hello_release.tar.gz
```

#### 3. Attaching & Verifying Signed SBOM Attestations
```bash
# Generate SBOM and attach it as a signed in-toto attestation on the OCI image
syft ://example.com... -o cyclonedx-json=sbom.cdx.json
cosign attest \
  --yes \
  --predicate sbom.cdx.json \
  --type cyclonedx \
  ://example.com...

# Verify the signed SBOM attestation before deploying
cosign verify-attestation \
  --type cyclonedx \
  --certificate-identity-regexp=".*@org\.com\$" \
  --certificate-oidc-issuer="https://google.com" \
  ://example.com...
```
