# NAGP 2026 — Kubernetes, DevOps & FinOps Assignment
## Solution Documentation

---

**Project:** Multi-tier Kubernetes Application Deployment on GKE
**Submitted by:** Shubham Garg

---

## Table of Contents

1. [Requirement Understanding](#1-requirement-understanding)
2. [Assumptions](#2-assumptions)
3. [Solution Overview](#3-solution-overview)
4. [Justification for the Resources Utilized](#4-justification-for-the-resources-utilized)

---

# 1. Requirement Understanding

The assignment requires designing, containerizing, and deploying a **multi-tier system on Kubernetes** that simulates a real-world setup where a service tier fetches data from a database tier via an exposed API. The implementation must satisfy concrete technical, operational, and cost-optimization requirements.

## 1.1 Functional Requirements

The system must consist of two distinct tiers:

**Service API Tier:**
- Exposes a public REST API endpoint that returns records from the database tier
- Built using any standard backend language or framework
- Implements best practices for database connectivity (connection pooling, configuration separation)
- Supports rolling updates with zero downtime
- Is externally accessible from outside the cluster
- Demonstrates self-healing behavior when pods fail
- Includes Horizontal Pod Autoscaling (HPA) based on observed resource metrics

**Database Tier:**
- Contains at least one table with 5-10 sample records
- Supports data persistence — data must survive pod restarts
- Is accessible only from inside the cluster (not externally exposed)
- Automatically recovers when its pod is deleted

## 1.2 Kubernetes Platform Requirements

| Feature | Service API Tier | Database Tier |
|---|---|---|
| Exposed outside the cluster | Required | Forbidden |
| Number of pods | 4 | 1 |
| Rolling updates support | Required | Not required |
| Persistent storage | Not required | Required |
| Configurable via ConfigMap | Required | Optional |
| Secrets usage | Required | Required |

## 1.3 FinOps Requirements

- Define CPU and memory **requests and limits** for the Service/API tier
- Identify at least **three** opportunities to optimize Kubernetes costs
- Implement resource optimization driven by **observed metrics**, not arbitrary defaults

# 2. Assumptions

Several decisions were taken to balance assignment requirements against practical constraints. These assumptions are documented here so the implementation choices are understood in context.

## 2.1 Environmental Assumptions

- **Cloud provider: Google Cloud Platform (GCP).** Chosen because GCP offers a **$300 free trial credit** valid for 90 days, which comfortably covers the duration of this assignment. AWS and Azure also offer free tiers, but GCP's $300 ungated credit is the most generous for an exercise of this size.

- **Kubernetes distribution: Google Kubernetes Engine (GKE).** Managed control plane is free for a single zonal cluster, which removes operational overhead and avoids the cost of running a self-managed control plane on Compute Engine VMs.

## 2.2 Technology Stack Assumptions

- **API language: Node.js 20 with Express.** Chosen for:
  - Fast cold-start times (relevant for HPA scale-up responsiveness)
  - Mature PostgreSQL client library (`pg`) with built-in connection pooling

- **Database: PostgreSQL 15.** Chosen because:
  - Official Docker image (`postgres:15`) is well-maintained
  - Supports environment-variable-driven initialization (no init scripts needed for basic setup)
  - The `pg_stat_activity` system view provides an easy way to verify connection pooling at runtime

## 2.3 Build Pipeline Assumptions

- **Docker Hub credentials are stored in GCP Secret Manager**, not in `cloudbuild.yaml`, environment variables, or Git history. Cloud Build accesses them at build time via the `availableSecrets` directive.

## 2.4 Kubernetes Topology Assumptions

- **Worker nodes: 2 × `e2-small` VMs at baseline.** Each `e2-small` has 2 vCPU and 2 GB RAM. Two nodes are the minimum needed to fit all required pods plus GKE system pods comfortably. The cluster autoscaler can scale this from 1 (idle) to 3 (peak load).

- **Persistent storage: GKE default StorageClass (`pd-standard`).** Standard persistent disks instead of SSD-backed disks. The workload (7 employee records) has no IOPS requirements that justify SSD.

- **Ingress controller: GKE built-in (GCE Load Balancer).** GKE provisions a Google Cloud HTTP(S) Load Balancer automatically when an Ingress is created. No separate ingress controller (e.g., nginx-ingress) needs to be installed.

## 2.5 Operational Assumptions

- **Database seeding happens at API startup.** The API connects to Postgres and runs `CREATE TABLE IF NOT EXISTS` followed by conditional `INSERT` statements if the table is empty. This means the DB is self-seeding without needing a separate init Job or init container.

- **7 sample employee records.** The assignment specifies 5-10 records; 7 was chosen as a comfortable mid-range.

- **HPA target: 60% average CPU utilization.** Standard tradeoff: low enough that pods scale up before saturation, high enough to avoid thrashing.

- **Cluster lifetime: minutes to hours.** The cluster is created for demonstration, the screen recording is captured, and the cluster is deleted immediately afterward to stop billing.

---

# 3. Solution Overview

## 3.1 Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│                        External Traffic                         │
└─────────────────────────────────────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────┐
│        Google Cloud HTTP Load Balancer (public IP)              │
│                  (provisioned by Ingress)                       │
└─────────────────────────────────────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────┐
│           nagp-api-service (ClusterIP, port 80 → 3000)          │
└─────────────────────────────────────────────────────────────────┘
                                │
                                ▼
┌──────────┬──────────┬──────────┬──────────┐
│ API Pod  │ API Pod  │ API Pod  │ API Pod  │   (4 replicas)
│ Node.js  │ Node.js  │ Node.js  │ Node.js  │
│ Express  │ Express  │ Express  │ Express  │
└──────────┴──────────┴──────────┴──────────┘
                                │
                                │ DNS: postgres-service:5432
                                │ (Kubernetes Service DNS, NOT pod IPs)
                                ▼
┌─────────────────────────────────────────────────────────────────┐
│        postgres-service (ClusterIP, port 5432, internal only)   │
└─────────────────────────────────────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────┐
│                   1 × Postgres Pod (PostgreSQL 15)              │
└─────────────────────────────────────────────────────────────────┘
                                │
                                │ Volume mount: /var/lib/postgresql/data
                                ▼
┌─────────────────────────────────────────────────────────────────┐
│             postgres-pvc (PersistentVolumeClaim, 1Gi)           │
└─────────────────────────────────────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────┐
│                 GCE Persistent Disk (1Gi, pd-standard)          │
└─────────────────────────────────────────────────────────────────┘
```

## 3.2 Kubernetes Resources

The deployment consists of **10 Kubernetes YAML manifests**, applied in dependency order.

| # | Manifest | Kind | Purpose |
|---|---|---|---|
| 1 | `namespace.yaml` | Namespace | Logical isolation boundary (`nagp-assignment`) |
| 2 | `configmap.yaml` | ConfigMap | Non-sensitive DB config (host, port, name, user, port) |
| 3 | `secret.yaml` | Secret | Sensitive credentials (DB password, base64-encoded) |
| 4 | `db-pvc.yaml` | PersistentVolumeClaim | 1 Gi storage request for Postgres data |
| 5 | `db-deployment.yaml` | Deployment | 1 Postgres pod, Recreate strategy, PVC-mounted |
| 6 | `db-service.yaml` | Service | ClusterIP exposing Postgres on port 5432 internally |
| 7 | `api-deployment.yaml` | Deployment | 4 Node.js API pods, RollingUpdate strategy, probes, resources |
| 8 | `api-service.yaml` | Service | ClusterIP exposing API on port 80 → container 3000 |
| 9 | `api-hpa.yaml` | HorizontalPodAutoscaler | Scales API 2-8 replicas at 60% CPU target |
| 10 | `ingress.yaml` | Ingress | Provisions GCP HTTP Load Balancer with public IP |

## 3.3 Application Code (Service API Tier)

The API is a small Node.js Express server with the following responsibilities:

- **Initialize the connection pool** using `pg.Pool` with `max: 10` connections per pod
- **Seed the database** on startup if the `employees` table is empty
- **Serve three endpoints:**
  - `GET /` — service identification and endpoint listing
  - `GET /health` — used by Kubernetes liveness and readiness probes
  - `GET /employees` — queries Postgres and returns all employee rows

### Connection pooling

The connection pool is configured to:
- Maintain up to 10 concurrent connections per pod (40 across the 4-replica deployment)
- Close idle connections after 30 seconds (`idleTimeoutMillis: 30000`)
- Time out new connection attempts at 2 seconds (`connectionTimeoutMillis: 2000`)

This was verified at runtime by querying `pg_stat_activity` while sending 100 concurrent requests — the connection count remained bounded around 20-30, not 100, confirming that connections are reused rather than opened per request.

### Configuration separation

The API contains zero hardcoded database values. Every connection parameter is read from environment variables:
- `DB_HOST`, `DB_PORT`, `DB_NAME`, `DB_USER`, `PORT` — sourced from the `api-config` ConfigMap
- `DB_PASSWORD` — sourced from the `db-secret` Kubernetes Secret

Changing any database configuration requires only editing the ConfigMap or Secret and restarting the pods — no code change, no image rebuild, no redeployment of the application artifact.

## 3.4 Build & Deployment Pipeline

### Image build (Google Cloud Build)

Because Docker cannot run on the development machine, image builds happen in GCP:

1. `cloudbuild.yaml` defines a three-step pipeline:
   - **Login to Docker Hub** using credentials from GCP Secret Manager
   - **Build the image** from `./app/Dockerfile`
   - **Push the image** tagged `shbhmgarg/nagp-api:v1` to Docker Hub

2. `gcloud builds submit --config=cloudbuild.yaml .` uploads the source, runs the pipeline on GCP infrastructure, and publishes the image.

3. The image is pulled by Kubernetes nodes at pod creation time.

### Cluster provisioning

The GKE cluster is created with:

```bash
gcloud container clusters create nagp-cluster \
  --zone us-central1-a \
  --num-nodes 2 \
  --machine-type e2-small \
  --enable-autoscaling \
  --min-nodes 1 \
  --max-nodes 3 \
  --disk-size 20 \
  --disk-type pd-standard
```

Key flags:
- `--enable-autoscaling --min-nodes 1 --max-nodes 3` — Cluster Autoscaler enabled
- `--disk-size 20 --disk-type pd-standard` — Smaller, cheaper boot disks than the default

### Deployment to Kubernetes

The 10 YAMLs are applied in dependency order via `kubectl apply -f`. Operationally, this is wrapped in a shell script (`scripts/04-deploy.sh`) that also waits for deployments to become available.

## 3.5 Secret and Credential Management

This solution uses **two layers of secrets** for different purposes:

| Layer | What it stores | Why |
|---|---|---|
| **GCP Secret Manager** | Docker Hub username + access token | Used by Cloud Build at image build time; never enters the Git repo |
| **Kubernetes Secret** | Database password (base64-encoded) | Used by both the Postgres pod and the API pod at runtime |

This separation ensures:
- Build-time credentials (Docker Hub) live outside the cluster — managed by GCP IAM
- Runtime credentials (DB password) live inside the cluster — managed by Kubernetes RBAC

Neither password ever appears in plaintext in any YAML file or in version control.

## 3.6 Deployment Strategies

### API Tier — RollingUpdate

The API deployment uses `RollingUpdate` strategy with:
- `maxSurge: 1` — allow at most 1 pod above desired count during rollout
- `maxUnavailable: 1` — allow at most 1 pod below desired count during rollout

With 4 baseline replicas, this guarantees at least 3 pods serving traffic at all times during a rolling update — zero downtime.

### Database Tier — Recreate

The Postgres deployment uses `Recreate` strategy. With only 1 replica and a `ReadWriteOnce` PVC, two pods cannot mount the same volume simultaneously. Recreate strategy kills the old pod first, releases the volume, then starts the new pod. This is the correct strategy for single-replica stateful workloads.

## 3.7 Self-Healing Implementation

Self-healing is implemented through **two complementary mechanisms**:

1. **Deployment + ReplicaSet controller** — If any pod is killed or crashes, the controller immediately spawns a replacement to match the desired replica count.

2. **Liveness and Readiness probes** on the API:
   - **Readiness probe** — HTTP GET to `/health` every 5 seconds. If it fails, the pod is removed from the Service's load-balancing rotation. Traffic resumes when it passes again.
   - **Liveness probe** — HTTP GET to `/health` every 10 seconds (with 30-second initial delay). If it fails repeatedly, Kubernetes kills the pod and the controller restarts it.

Together, these ensure:
- Crashed pods are restarted automatically
- Unresponsive pods are killed and replaced
- Slow-starting pods don't receive traffic until they're ready
- The database, despite having only one replica, recovers automatically because the Deployment controller spawns a new pod that re-attaches to the same PVC

## 3.8 Horizontal Pod Autoscaling

The HPA configuration scales the API deployment between **2 and 8 replicas** based on **60% average CPU utilization**.

- At idle (no traffic), HPA scales to the minimum (2 pods) — saving resources versus running 4 constantly
- Under load, HPA observes CPU rising above 60% of the request and adds pods proportionally
- After load subsides, HPA scales back down (with a stabilization window to prevent thrashing)

The HPA uses the `metrics-server` running on GKE (enabled by default) to read CPU utilization.

## 3.9 Persistence

The Postgres pod mounts a PersistentVolumeClaim at `/var/lib/postgresql/data`, where Postgres stores all its data files. The PVC is backed by a **GCE Persistent Disk** (provisioned dynamically by GKE).

Critically, the persistent disk's lifecycle is **independent of the pod**. When the Postgres pod is deleted:
1. The pod is destroyed
2. The persistent disk is detached but NOT deleted
3. A new pod is created by the Deployment controller
4. The same persistent disk is attached to the new pod
5. Postgres starts up and finds its existing data files intact

This was verified during the screen recording by inserting a marker row, deleting the Postgres pod, and confirming the marker row is still present after the new pod starts.

---

# 4. Justification for the Resources Utilized

This section explains *why* each resource is sized the way it is, with concrete data backing every choice.

## 4.1 API Tier — Resource Requests and Limits

The API deployment specifies:

```yaml
resources:
  requests:
    cpu: 100m
    memory: 128Mi
  limits:
    cpu: 300m
    memory: 256Mi
```

### Observed metrics (the basis for these numbers)

Resource sizing was driven by actual measurements using `kubectl top pods`, not arbitrary defaults.

| State | Observed CPU | Observed Memory |
|---|---|---|
| Idle (no traffic) | ~2-5 millicores | ~60-80 MiB |
| Under 100 concurrent requests (using for loop) | ~40-60 millicores | ~80-100 MiB |

### Justification

- **CPU request `100m`** — Approximately 2× the observed peak under load. Provides safety margin without overprovisioning. Lower than naive defaults (`500m` is common), which means **higher pod density per node**.

- **CPU limit `300m`** — 3× the request. Absorbs transient spikes (slow GC, request fan-in) without throttling. CPU limits cause throttling (not OOM-kill), so being slightly generous here is low-risk.

- **Memory request `128Mi`** — Approximately 2× the observed working set. Node.js with Express and pg pool sits at ~80 MiB even under load.

- **Memory limit `256Mi`** — 2× the request. Memory limits trigger OOM-kill, so they're set generously to avoid surprises during traffic bursts.

## 4.2 Database Tier — Resource Requests and Limits

The Postgres deployment specifies:

```yaml
resources:
  requests:
    cpu: 100m
    memory: 256Mi
  limits:
    cpu: 500m
    memory: 512Mi
```

### Justification

- **CPU request `100m`** — Postgres is largely idle for this workload (7-row table, low query rate), but the process has steady-state CPU activity for autovacuum, statistics collection, and WAL maintenance.

- **CPU limit `500m`** — Generous ceiling for query bursts or maintenance operations.

- **Memory request `256Mi`** — Postgres uses more memory than the API because of its shared buffers, connection management, and OS file cache pressure. 256 MiB is enough for default `shared_buffers` (128 MB) plus working memory.

- **Memory limit `512Mi`** — 2× request, with safety margin for query plan execution and connection memory.

## 4.3 Cluster Compute — Node Sizing

The GKE cluster uses **2 × `e2-small` nodes at baseline**, with autoscaling from 1 to 3.

### Why `e2-small`

- 2 vCPU + 2 GB RAM per node
- ~$13/month per node on-demand pricing
- The smallest cost-effective machine type that can host the required pods plus GKE system pods

### Why 2 nodes baseline

- One node cannot fit all required pods + system pods comfortably (Postgres alone wants 256 MiB, plus 4 × 128 MiB for API, plus 200-400 MiB for GKE system pods → close to 2 GB)
- Two nodes provide redundancy for the API tier (no single node failure can take down all 4 replicas)

### Why autoscaling 1-3

- **Minimum 1** — During very low traffic and overnight, the cluster can collapse to a single node
- **Maximum 3** — Cost ceiling for unexpected scale-up events

## 4.4 Three FinOps Cost Optimization Opportunities

Three explicit optimizations are implemented, with concrete cost rationale.

### Opportunity 1 — Right-Sized Resource Requests

**Implementation:** API pods request `100m CPU / 128Mi memory` instead of arbitrary defaults like `500m / 512Mi`.

**Cost mechanism:** The Kubernetes scheduler reserves resources based on `requests`, not on actual usage. With 100m requests, ~16 API pods fit on a single `e2-small` node (2 vCPU). With 500m requests, only ~4 fit — Kubernetes would need 4× more nodes.

**Measurable saving:** Reduces the minimum required node count from ~4 to ~1 for the same pod workload, saving ~$40/month on compute.

### Opportunity 2 — Horizontal Pod Autoscaler (HPA)

**Implementation:** API replicas scale 2-8 based on observed CPU utilization.

**Cost mechanism:** During low-traffic periods, the cluster runs 2 API pods instead of a fixed 4 — a 50% reduction in pod count and resource consumption. Combined with scale-up during peaks, this matches resource cost to actual demand.

**Measurable saving:** For a workload that is at peak load only 30% of the time, this saves roughly 35-40% of total pod-runtime compared to running 4 pods continuously.

### Opportunity 3 — Cluster Autoscaler

**Implementation:** Worker node pool scales 1-3 nodes based on pending pods.

**Cost mechanism:** HPA reduces pod count during idle periods, but if 2 nodes are running, you still pay for both nodes. The Cluster Autoscaler removes nodes when pods can be consolidated. At minimum-state (1 node), compute cost is **half** of the baseline 2-node configuration.

**Measurable saving:** ~$13/month per removed node. Over a typical day where idle hours dominate, this can reduce compute cost by 30-40%.

## Closing Note

This solution satisfies every functional, platform, security, and FinOps requirement specified in the assignment brief. The implementation prioritizes:

- **Reproducibility** — every step is scripted and idempotent
- **Auditability** — no plaintext secrets, no hardcoded config, observable via `kubectl describe` and Cloud Build logs
- **Cost discipline** — every resource is sized based on observed data and explicitly justified
- **Operational realism** — uses managed services where they reduce operational overhead, while remaining vendor-agnostic in the application layer

The cluster is deleted after demonstration capture (`./scripts/cleanup.sh`) to avoid further billing, per the assignment's explicit suggestion.

---