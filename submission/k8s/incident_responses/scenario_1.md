# Incident Response: Scenario 1

## What is happening?

The `video-processor` pod `video-processor-7d4f8b6c9-x2k4m` is in `CrashLoopBackOff` with `restartCount: 7`. The container last exited with **exit code 137**, which means it was killed by the Linux kernel's OOM (Out Of Memory) killer via SIGKILL. Both `Ready` and `ContainersReady` conditions are `False` — this replica is completely offline and receiving no traffic.

## Root Cause

**The memory limit (512Mi) is too tight for the JVM process's actual total memory usage.**

Evidence chain from the data files:

**From `pod_description.yaml`:**
- Memory limit: `512Mi`
- JVM env var: `JAVA_OPTS: "-Xmx384m -Xms256m"` → max heap = 384 MB
- `PROCESSING_THREADS: "8"`, `BATCH_SIZE: "50"` → 8 threads × 50 fragments running concurrently

**From `events.txt`:**
- `OOMKilling: Killed process 4521 (java) total-vm:2847632kB, anon-rss:525312kB`
- The process RSS was ~512 MB when killed — exactly at the container limit
- The event repeated: `anon-rss:531488kB` on the next restart

**From `logs.txt`:**
- JVM confirms max heap: 384 MB
- Thread-1: heap at 78% (299 MB), then 85% (326 MB)
- Full GC triggered, 1.2s pause — JVM is under extreme pressure
- `OutOfMemoryError: Java heap space` at `FragmentProcessor.concatenateFragments` — allocating a `ByteBuffer`

**Why 512Mi is not enough:**
The JVM uses memory beyond just the heap:
- Heap: up to 384 MB (Xmx)
- JVM Metaspace (class definitions): ~60–80 MB
- Thread stacks: 8 threads × ~1 MB = ~8 MB
- JIT compiler code cache: ~50 MB
- Native ByteBuffer allocations (off-heap): grows with concurrent batches

Total RSS: 510–530+ MB → OOMKill at the 512Mi hard limit.
With 8 threads each holding 50 fragments in memory simultaneously, the heap spike is extreme.

## Immediate Remediation

**1. Increase the memory limit and update JVM flags right now:**
```bash
kubectl set resources deployment/video-processor \
  -n video-analytics \
  --limits=memory=1Gi \
  --requests=memory=512Mi

kubectl set env deployment/video-processor \
  -n video-analytics \
  PROCESSING_THREADS=4 \
  JAVA_OPTS="-Xmx640m -Xms256m -XX:+UseG1GC -XX:MaxGCPauseMillis=200"
```

**2. Watch the rollout recover:**
```bash
kubectl rollout status deployment/video-processor -n video-analytics
kubectl get pods -n video-analytics -l app=video-processor -w
```

**3. Confirm no more OOMKill events:**
```bash
kubectl describe pod -n video-analytics -l app=video-processor | grep -A5 "OOM"
```

## Long-term Fix

1. **Raise memory limit to 1Gi in `deployment.yaml`** (already done in our submission). Rule: `-Xmx` should not exceed 60–65% of the container memory limit to leave room for JVM overhead. At 1Gi limit, `-Xmx640m` is 62.5% — correct.

2. **Update `configmap.yaml`** with `PROCESSING_THREADS: "4"`, `BATCH_SIZE: "25"`, and `JAVA_OPTS: "-Xmx640m -Xms256m -XX:+UseG1GC"`. Halving threads halves peak concurrent ByteBuffer allocations.

3. **Add G1GC** (`-XX:+UseG1GC -XX:MaxGCPauseMillis=200`): G1GC handles large heaps better than the default GC and reduces the likelihood of a single Full GC pause tipping the process over the memory limit.

4. **Add HPA memory trigger** (done in `hpa.yaml`) to scale out pods before memory pressure on any single replica becomes critical.

## Prevention

1. **OOMKill alert**: Set a CloudWatch alarm on `container_oom_kill_count > 0` via Container Insights. Alert within 1 minute — do not wait for 7 restarts.

2. **JVM heap utilization alert**: Export JVM metrics (via Prometheus JMX exporter or Micrometer). Alert when heap > 80% for more than 2 consecutive minutes.

3. **Load test in staging**: Run a peak-load simulation (32 cameras, batch 50, 8 threads) before each production deploy. This would have caught the OOM in staging.

4. **CI policy check**: Use OPA/Conftest to reject any deployment manifest where the `-Xmx` value exceeds 65% of the container memory limit. Enforce this as a CI gate.
