# Incident Response: Scenario 2

## What is happening?

The `inference-api` service has **zero active endpoints**. All 3 pods are `Running` and healthy, but any caller (e.g., `web-frontend`) gets `Connection timed out` when trying to reach `inference-api:8080`. The service exists and has an IP (`172.20.45.123`), but traffic never reaches the pods.

## Root Cause

There are **two separate bugs** both active simultaneously. Fixing only one is not enough.

---

**Bug 1 — Label mismatch between Service selector and pod labels (primary cause of empty endpoints)**

From `service.yaml`:
```yaml
selector:
  app: inference-api
  tier: backend        # ← Service requires BOTH labels
```

From `deployment.yaml`:
```yaml
labels:
  app: inference-api
  # NOTE: "tier: backend" label is missing from pod template
```

The Kubernetes Service uses its `selector` to find pods. It requires ALL listed labels to be present. The pods only have `app: inference-api` — they are missing `tier: backend`. Kubernetes sees zero matching pods and sets `Endpoints: <none>`.

**Confirmed by `debug_output.txt`:**
```
kubectl get endpoints inference-api -n video-analytics
NAME            ENDPOINTS   AGE
inference-api   <none>      2h

kubectl get pods --show-labels
LABELS: app=inference-api,pod-template-hash=5f7b8c9d4
# "tier=backend" is absent from every pod
```

---

**Bug 2 — NetworkPolicy blocks the calling pod (secondary cause of connection timeout)**

From `networkpolicy.yaml`:
```yaml
ingress:
- from:
  - podSelector:
      matchLabels:
        app: api-gateway   # ← ONLY allows api-gateway pods
```

The debug output shows the request comes from `web-frontend`:
```
kubectl exec -it web-frontend-6a5b4c3d2-jkl78 -- curl http://inference-api:8080/health
→ Connection timed out
```

`web-frontend` has label `app: web-frontend`, not `app: api-gateway`. The NetworkPolicy silently drops its packets. Even after fixing Bug 1 (endpoints populated), the connection would still time out due to this NetworkPolicy block.

**Architecture issue:** `web-frontend` should not call `inference-api` directly. It should go through `api-gateway`. This NetworkPolicy is architecturally correct — the bug is that the caller is wrong, not the policy.

## Immediate Remediation

**Fix Bug 1 — Add the missing label to the deployment pod template:**

```bash
kubectl patch deployment inference-api -n video-analytics \
  --type=json \
  -p='[{"op":"add","path":"/spec/template/metadata/labels/tier","value":"backend"}]'
```

This triggers a rolling update. Verify endpoints populate:
```bash
kubectl get endpoints inference-api -n video-analytics
# Should now show: 10.x.x.x:8080,10.x.x.x:8080,10.x.x.x:8080
```

**Fix Bug 2 — Route web-frontend through api-gateway (correct architecture):**

The `web-frontend` should never call `inference-api` directly. The correct fix is to ensure `web-frontend` calls `api-gateway`, which is already allowed by the NetworkPolicy. If there is a legitimate need for `web-frontend` to reach `inference-api` directly, add it explicitly:

```bash
kubectl patch networkpolicy inference-api-netpol -n video-analytics \
  --type=json \
  -p='[{"op":"add","path":"/spec/ingress/0/from/-","value":{"podSelector":{"matchLabels":{"app":"web-frontend"}}}}]'
```

**Verify end-to-end:**
```bash
kubectl exec -it web-frontend-6a5b4c3d2-jkl78 -n video-analytics \
  -- curl -v http://inference-api:8080/health
# Should now return HTTP 200
```

## Long-term Fix

1. **Add `tier: backend` to the deployment pod template** permanently in `deployment.yaml`. Add a comment explaining it is required by both the Service selector and the NetworkPolicy. This makes the dependency explicit and visible in code review.

2. **Enforce architectural traffic flow**: `web-frontend` → `api-gateway` → `inference-api`. The NetworkPolicy correctly enforces this; fix the calling code in `web-frontend` to route through `api-gateway`.

3. **Add a CI/CD check**: Use `kubeconform` or OPA/Conftest to verify that every Service selector label is present in the corresponding Deployment pod template. This is a class of bug that can be caught statically.

## Prevention

1. **Endpoint alert**: Create a CloudWatch alarm that fires when `kube_endpoint_address_not_ready` > 0 OR when an endpoint has `<none>` for more than 2 minutes. Empty endpoints are always a misconfiguration or failure — they should never be silent.

2. **Synthetic health check**: Run a periodic `curl` from a test pod to `inference-api:8080/health` via a CronJob. Alert if it fails. This catches network-level issues (NetworkPolicy, empty endpoints) that pod-level health checks miss.

3. **Label conventions**: Document and enforce label conventions in a team runbook. Require `app`, `tier`, and `version` labels on all pod templates. A linter (e.g., `kube-score`) can enforce this in CI.

4. **Deployment validation pipeline**: After every `kubectl apply`, run `kubectl get endpoints <service>` and fail the deploy pipeline if endpoints are `<none>` after 60 seconds.
