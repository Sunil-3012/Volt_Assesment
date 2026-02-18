# Incident Response: Scenario 3

## What is happening?

A deployment rollout for `chunk-processor` is stuck. The rollout updated 1 out of 3 replicas before stalling. The new pod (`chunk-processor-7c8d9e0f1-new01`) has been in `ImagePullBackOff` for 15 minutes. The 3 old pods remain running, so the service is degraded (operating at 3/4 capacity) but not fully down. The rolling update cannot complete.

## Root Cause

**The node pulling the new image (`ip-10-0-4-55`) cannot authenticate to ECR because the ServiceAccount is missing its IRSA (IAM Roles for Service Accounts) annotation.**

Evidence from `rollout_status.txt`:

**Error message:**
```
Failed to pull image: rpc error: code = Unknown desc = Error response from daemon:
pull access denied for ...chunk-processor, repository does not exist or may require
'docker login': denied: Your authorization token has expired. Reauthenticate and try again.
```

`"Your authorization token has expired"` means the node tried to use an ECR auth token that is no longer valid. ECR tokens expire every **12 hours** and must be refreshed by calling `ecr:GetAuthorizationToken`.

**From the ServiceAccount manifest:**
```yaml
metadata:
  name: chunk-processor
  namespace: video-analytics
  annotations:
    # NOTE: IAM role annotation is missing — should be:
    # eks.amazonaws.com/role-arn: arn:aws:iam::123456789012:role/chunk-processor-ecr-role
```

Without the IRSA annotation, the pod's ServiceAccount has no IAM identity. The kubelet on the new node cannot call `ecr:GetAuthorizationToken` to get a fresh token — it has no permission to do so. The old pods on other nodes happen to have valid cached tokens still within the 12-hour window, which is why they are still running.

**Why only the new node fails:** ECR credential caching is per-node. Old nodes cached a valid token earlier. The new node (`ip-10-0-4-55`) either never pulled from ECR or its cached token has expired. Without IRSA, it has no way to refresh.

## Immediate Remediation

**Step 1 — Add the IRSA annotation to the ServiceAccount:**

```bash
kubectl annotate serviceaccount chunk-processor \
  -n video-analytics \
  eks.amazonaws.com/role-arn=arn:aws:iam::123456789012:role/chunk-processor-ecr-role
```

**Step 2 — Delete the stuck pod so it reschedules with the corrected ServiceAccount:**

```bash
kubectl delete pod chunk-processor-7c8d9e0f1-new01 -n video-analytics
```

The deployment controller will immediately create a replacement pod. This time the kubelet will use the IRSA-injected credentials to get a fresh ECR token.

**Step 3 — Watch the rollout resume:**

```bash
kubectl rollout status deployment/chunk-processor -n video-analytics
kubectl get pods -n video-analytics -l app=chunk-processor -w
```

**Step 4 — If the IAM role itself doesn't exist yet, create it:**

The role `chunk-processor-ecr-role` needs:
- Trust policy allowing the ServiceAccount to assume it (OIDC federation)
- Permission: `ecr:GetAuthorizationToken` + `ecr:BatchGetImage` + `ecr:GetDownloadUrlForLayer`

```bash
# Verify the role exists and has ECR permissions:
aws iam get-role --role-name chunk-processor-ecr-role
aws iam list-attached-role-policies --role-name chunk-processor-ecr-role
```

## Long-term Fix

1. **Add the IRSA annotation to the ServiceAccount in the manifest** (infrastructure as code), not just imperatively. Commit this to the repo so it survives future re-deployments.

2. **Ensure the IAM role is created via Terraform** (in `main.tf` or a dedicated IAM module) with the correct OIDC trust policy and `AmazonEC2ContainerRegistryReadOnly` policy attached.

3. **Use the EKS node group IAM role as a fallback**: The node group IAM role in `main.tf` already has `AmazonEC2ContainerRegistryReadOnly` attached. For workloads without IRSA, nodes can pull from ECR using the node role. Verify this is present on the new node.

4. **Pin image tags to tested versions**: The failing image is `v3.0.0-rc1` — a release candidate. RC tags should never be deployed to production without explicit approval. Use semantic versioning and require stable tags (`v3.0.0`) for production deployments.

## Prevention

1. **ImagePullBackOff alert**: Create a CloudWatch alarm on `kube_pod_container_status_waiting_reason{reason="ImagePullBackOff"} > 0`. Alert within 2 minutes — this is always a hard blocker for rollouts.

2. **IRSA validation in CI**: Add a check to the deployment pipeline that verifies the ServiceAccount for every Deployment has the `eks.amazonaws.com/role-arn` annotation set before applying to production. Fail the pipeline if it is missing.

3. **ECR image existence check**: Before triggering a rollout, verify the image tag exists in ECR:
   ```bash
   aws ecr describe-images \
     --repository-name chunk-processor \
     --image-ids imageTag=v3.0.0-rc1
   ```
   Fail the deploy pipeline if the tag does not exist.

4. **Block RC/pre-release tags in production**: Enforce via OPA/Gatekeeper that production namespaces may only run images tagged with a full semantic version (`vX.Y.Z`), never `-rc`, `-alpha`, or `-beta` suffixes.

5. **Rollback strategy**: The rolling update strategy (`maxUnavailable: 25%`) kept 3 old pods running during the failed rollout — service degraded but not down. Ensure all deployments have rollback automation:
   ```bash
   kubectl rollout undo deployment/chunk-processor -n video-analytics
   ```
   Trigger this automatically in CI/CD if `rollout status` does not complete within a timeout window (e.g., 10 minutes).
