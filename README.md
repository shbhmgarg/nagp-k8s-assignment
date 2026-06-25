# NAGP 2026 — Kubernetes, DevOps & FinOps Assignment

A multi-tier Kubernetes application demonstrating containerization, orchestration, persistence, autoscaling, and cost optimization on Google Kubernetes Engine.

---

## Deliverable URLs

| Item | URL |
|------|-----|
| **Source Code Repository** | https://github.com/shbhmgarg/nagp-k8s-assignment |
| **Docker Hub Image** | https://hub.docker.com/r/shbhmgarg/nagp-api |
| **Live Service API URL** | http://35.190.59.142/employees |
| **Screen Recording** | <YOUR_LOOM_OR_DRIVE_LINK> |

---

## Architecture

```
External Traffic
       │
       ▼
Google Cloud HTTP Load Balancer (provisioned by Ingress)
       │
       ▼
nagp-api-service (ClusterIP, port 80 → 3000)
       │
       ▼
4 × nagp-api pods (Node.js 20 + Express + pg pool)
       │  (via DNS: postgres-service:5432 — no pod IPs)
       ▼
postgres-service (ClusterIP)
       │
       ▼
1 × postgres pod (PostgreSQL 15)
       │
       ▼
postgres-pvc (1 Gi PVC)
       │
       ▼
GCE Persistent Disk
```

---

## Tech Stack

| Layer | Choice | Reason |
|---|---|---|
| Service API | Node.js 20 (Express + pg) | Lightweight, fast cold start, small image |
| Database | PostgreSQL 15 | Standard relational DB with official image |
| Container base | Alpine Linux | ~50 MB image vs ~1 GB Debian — faster pulls, lower cost |
| Container Registry | Docker Hub | Assignment requirement |
| CI / Image Build | Google Cloud Build | No Docker required locally; remote build with Secret Manager auth |
| Orchestration | Google Kubernetes Engine (GKE) | Managed K8s with $300 free trial |
| Credentials | GCP Secret Manager + Kubernetes Secrets | Two-tier secret strategy |
| Ingress | GKE built-in (GCE LB) | No nginx-ingress install required |

---

## Repository Structure

```
nagp-2026-k8-assignment/
├── app/
│   ├── Dockerfile             # Alpine-based image, runs as non-root
│   ├── index.js               # Express API with pg.Pool, /employees + /health
│   └── package.json
├── k8s/
│   ├── namespace.yaml         # nagp-assignment namespace
│   ├── configmap.yaml         # DB_HOST, DB_PORT, DB_NAME, DB_USER, PORT
│   ├── secret.yaml            # DB_PASSWORD, POSTGRES_USER/PASSWORD (base64)
│   ├── db-pvc.yaml            # 1Gi PersistentVolumeClaim
│   ├── db-deployment.yaml     # Postgres 15, Recreate strategy, PVC-mounted
│   ├── db-service.yaml        # ClusterIP — internal only
│   ├── api-deployment.yaml    # 4 replicas, RollingUpdate, probes, resources
│   ├── api-service.yaml       # ClusterIP, port 80 → 3000
│   ├── api-hpa.yaml           # HPA: 2-8 replicas, 60% CPU target
│   └── ingress.yaml           # GCE Load Balancer with public IP
├── scripts/
│   ├── 01-setup-gcp.sh        # Enables APIs + grants IAM + stores Docker Hub creds
│   ├── 02-build-image.sh      # Submits Cloud Build job to build + push image
│   ├── 03-create-cluster.sh   # Creates GKE cluster with autoscaling
│   ├── 04-deploy.sh           # Applies all 10 K8s manifests in correct order
│   ├── 05-verify.sh           # Shows status of all resources + Ingress IP
│   └── cleanup.sh          # Deletes cluster, PVC, and orphaned LBs
├── cloudbuild.yaml            # Cloud Build pipeline definition
├── .gitignore
└── README.md                  # This file
```

---

## Prerequisites

Before deploying, you need:

1. **GCP account** with billing enabled (free trial is fine — $300 credit covers this assignment)
2. **`gcloud` CLI** installed and authenticated (`gcloud auth login`)
3. **`kubectl`** installed (or via `gcloud components install kubectl`)
4. **Docker Hub account** with a Read/Write access token (Settings → Security → New Access Token)
5. **A new GCP project** selected as default (`gcloud config set project <project-id>`)

---

## How To Deploy

The entire setup is scripted. Run them in order:

```bash
# 1. One-time GCP setup — enables APIs, stores Docker Hub creds in Secret Manager,
#    grants required IAM roles to the Cloud Build service account.
./scripts/01-setup-gcp.sh

# 2. Build and push the Docker image via Cloud Build.
./scripts/02-build-image.sh

# 3. Create the GKE cluster (takes ~3-5 min).
./scripts/03-create-cluster.sh

# 4. Apply all 10 Kubernetes manifests and wait for rollouts.
./scripts/04-deploy.sh

# 5. Verify status and retrieve the Ingress public IP.
./scripts/05-verify.sh
```

Once `05-verify.sh` shows the Ingress IP, test the API:

```bash
curl http://<INGRESS_IP>/employees
```

You should receive a JSON response with 7 employee records.

---

## Kubernetes Requirements Coverage

| Feature | Service API Tier | Database Tier | Implementation |
|---|---|---|---|
| Exposed outside the cluster | ✅ Yes | ❌ No | Ingress for API; ClusterIP for DB |
| Number of pods | 4 | 1 | `replicas: 4` / `replicas: 1` in deployments |
| Rolling updates support | ✅ Yes | ❌ No | `RollingUpdate` for API; `Recreate` for DB (single PVC constraint) |
| Persistent storage | ❌ No | ✅ Yes | PVC mounted at `/var/lib/postgresql/data` |
| Configurable via ConfigMap | ✅ Yes | ✅ Yes | `api-config` ConfigMap, injected via `envFrom` |
| Secrets Usage | ✅ Yes | ✅ Yes | `db-secret` — password never appears in plaintext in any YAML |

### Other Requirements Met

- **Pod IPs not used between tiers** — API connects via `postgres-service` DNS name (Kubernetes Service)
- **Externally accessible via Ingress** — `nagp-ingress` provisions a GCE Load Balancer with public IP
- **DB password not visible in plaintext** — stored in Kubernetes Secret (base64), never in ConfigMap or code
- **DB data survives pod redeploy** — verified by inserting marker row, killing pod, observing row still present
- **Self-healing** — liveness + readiness probes on `/health`, K8s restarts failed pods
- **HPA on Service API** — `nagp-api-hpa` scales 2-8 replicas based on 60% CPU target
- **Connection pooling** — `pg.Pool` with `max: 10`, verified via `pg_stat_activity`
- **Config separation** — zero hardcoded DB values in `index.js`; all from `process.env`

---

## FinOps Implementation

### Resource requests and limits (API tier)

```yaml
resources:
  requests: { cpu: 100m, memory: 128Mi }
  limits:   { cpu: 300m, memory: 256Mi }
```

Sized based on observed metrics (`kubectl top`): idle ~2m CPU / ~65 MiB; under load ~50m CPU / ~80 MiB. Requests at ~2× observed peak provide safety margin without overprovisioning.

### Three cost optimization opportunities implemented

1. **Right-sized resource requests** — 100m CPU per pod enables ~4× higher pod density per node vs naive 500m defaults. Reduces minimum node count by a factor of 4.

2. **Horizontal Pod Autoscaler (HPA)** — Scales API replicas 2-8 based on observed CPU. At idle, runs at floor (2 pods) instead of constant 4. For variable traffic, saves ~35-40% of pod runtime.

3. **Cluster Autoscaler** — Worker node pool scales 1-3 nodes based on pending pods. Combined with HPA, the cluster shrinks both vertically (pods) and horizontally (nodes) during low traffic. Minimum-state cluster cost is ~50% of baseline.

### Additional optimizations

- **Alpine base image** (~50 MB vs ~1 GB) — faster pulls, lower storage / egress costs
- **`pd-standard` boot disks** instead of `pd-ssd` — ~70% cheaper, sufficient for this workload
- **Single-zone cluster** (us-central1-a) — avoids regional control plane (~$74/month) and inter-zone egress
- **`e2-small` machine type** — cost-optimized for low-traffic workloads

---

## Screen Recording — Demonstrated Items

The recording (link above) covers:

| # | Demonstration |
|---|---|
| 1 | All Kubernetes objects deployed and running |
| 2 | API call retrieving records from the database |
| 3 | Kill API microservice pod → automatic regeneration (self-healing) |
| 4 | Kill database pod → regeneration with **data preserved** (persistence) |
| 5 | Rolling update of the API deployment |
| 6 | HPA configuration and live observed metrics |
| 7 | FinOps demonstration: requests/limits, observed metrics via `kubectl top`, autoscaling configs |

---

## Cleanup (Important — Stops Billing)

After the demo and recording are captured:

```bash
./scripts/cleanup.sh
```

This deletes:
- The GKE cluster (stops compute charges)
- The PVC and underlying GCE Persistent Disk
- Any orphaned Load Balancer forwarding rules

---

## Important Notes

- The Docker Hub credentials are stored in GCP Secret Manager (not committed to the repo)
- The Kubernetes Secret YAML in `k8s/secret.yaml` uses base64-encoded values for the assignment demo — production deployments should use [Sealed Secrets](https://github.com/bitnami-labs/sealed-secrets) or [External Secrets Operator](https://external-secrets.io/)
- The cluster is single-zone and **not** highly available — appropriate for a cost-conscious demo, not production
- This is a learning exercise; no client or production code is used

---

## Author

Submitted as part of NAGP 2026 Technology Band III — Workshop on Kubernetes, DevOps & FinOps.

## DEMO COMMANDS

Get namespace - `kubectl get namespace nagp-assignment`
Get Configmaps and secrets - `kubectl get configmap,secret -n $NS`
Get persistent volume information - `kubectl get pvc,pv -n $NS`
Get Ingress Information - `kubectl get ingress -n $NS`
Get all nodes - `kubectl get nodes`

Self healing and DB updates
INSERT DATA IN DB - `kubectl exec -n $NS deployment/postgres -- psql -U nagpuser -d nagpdb -c \
  "INSERT INTO employees (name, department, salary) VALUES ('NEW_MARKER', 'DEMO', 99999);"`


Rolling updates - `kubectl get deployment nagp-api -n $NS`
Verify strategy - `kubectl get deployment nagp-api -n $NS -o jsonpath='{.spec.strategy}' | jq`
Trigger rollout - `kubectl rollout restart deployment/nagp-api -n $NS`

HPA Status - `kubectl get hpa -n $NS`
Metrics - `kubectl describe hpa nagp-api-hpa -n $NS | grep -A 8 "Metrics:\|Min replicas\|Max replicas"`
Autoscaling - `gcloud container clusters describe nagp-cluster --zone us-central1-a \
  --format="value(autoscaling)"`

FINOPS 
CPU Memory- `kubectl top pods -n nagp-assignment`
LIMITS/Requests - `kubectl describe deployment nagp-api -n $NS | grep -A 6 "Limits:\|Requests:"`

