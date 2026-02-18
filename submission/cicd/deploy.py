#!/usr/bin/env python3
"""
deploy.py — Deployment automation for video-analytics service.
Usage:
    deploy.py deploy   --environment staging --image-tag abc1234 [--dry-run]
    deploy.py rollback --environment production [--revision 3]
    deploy.py status   --environment staging
"""

import argparse
import logging
import subprocess
import sys
import time

NAMESPACE = "video-analytics"
DEPLOYMENT = "video-processor"
ECR_REGISTRY = "123456789012.dkr.ecr.us-east-1.amazonaws.com"
ECR_REPO = "video-processor"

EKS_CLUSTERS = {
    "staging":    "vlt-staging",
    "production": "vlt-prod",
}

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
    datefmt="%Y-%m-%dT%H:%M:%S",
)
log = logging.getLogger(__name__)


def run(cmd, dry_run=False, check=True):
    """Run a shell command, or just log it if dry_run is True."""
    log.info("$ %s", " ".join(cmd))
    if dry_run:
        log.info("  (dry-run — skipped)")
        return ""
    result = subprocess.run(cmd, capture_output=True, text=True, check=check)
    if result.stdout.strip():
        log.info(result.stdout.strip())
    return result.stdout.strip()


def set_cluster_context(environment):
    """Point kubectl at the right EKS cluster."""
    cluster = EKS_CLUSTERS.get(environment)
    if not cluster:
        log.error("Unknown environment '%s'. Valid: %s", environment, list(EKS_CLUSTERS))
        sys.exit(1)
    run(["aws", "eks", "update-kubeconfig",
         "--name", cluster, "--region", "us-east-1"])


def health_check(environment, timeout=300):
    """
    Wait for the rollout to complete and verify pods are ready.
    Returns True if healthy, False if timed out or failed.
    """
    log.info("[%s] Running health check (timeout: %ss)...", environment, timeout)
    deadline = time.time() + timeout

    # Wait for rollout to complete
    try:
        run(["kubectl", "rollout", "status",
             f"deployment/{DEPLOYMENT}",
             "-n", NAMESPACE,
             f"--timeout={timeout}s"])
    except subprocess.CalledProcessError:
        log.error("[%s] Rollout did not complete within %ss", environment, timeout)
        return False

    # Verify at least min-ready pods are running
    if time.time() < deadline:
        try:
            ready = run(["kubectl", "get", "deployment", DEPLOYMENT,
                         "-n", NAMESPACE,
                         "-o", "jsonpath={.status.readyReplicas}"])
            desired = run(["kubectl", "get", "deployment", DEPLOYMENT,
                           "-n", NAMESPACE,
                           "-o", "jsonpath={.spec.replicas}"])
            log.info("[%s] Ready replicas: %s/%s", environment, ready, desired)
            if ready and desired and int(ready) >= int(desired):
                log.info("[%s] Health check PASSED", environment)
                return True
        except subprocess.CalledProcessError as e:
            log.error("[%s] Health check query failed: %s", environment, e)

    log.error("[%s] Health check FAILED", environment)
    return False


def deploy(environment, image_tag, dry_run=False):
    """Update the deployment image and wait for a healthy rollout."""
    log.info("[%s] Starting deploy (image-tag: %s, dry-run: %s)",
             environment, image_tag, dry_run)

    set_cluster_context(environment)

    image = f"{ECR_REGISTRY}/{ECR_REPO}:{image_tag}"

    # Update the container image in-place (no Helm in this example — kubectl set image)
    run(["kubectl", "set", "image",
         f"deployment/{DEPLOYMENT}",
         f"{DEPLOYMENT}={image}",
         "-n", NAMESPACE], dry_run=dry_run)

    # Annotate with the deployer and commit SHA for audit trail
    run(["kubectl", "annotate", "deployment", DEPLOYMENT,
         f"deployment.kubernetes.io/revision-note=image={image_tag}",
         "--overwrite", "-n", NAMESPACE], dry_run=dry_run)

    if dry_run:
        log.info("[%s] Dry-run complete — no changes applied", environment)
        return

    if not health_check(environment):
        log.error("[%s] Deploy FAILED health check — triggering rollback", environment)
        rollback(environment)
        sys.exit(1)

    log.info("[%s] Deploy SUCCESSFUL ✓", environment)


def rollback(environment, revision=None):
    """Rollback to the previous deployment revision (or a specific one)."""
    log.info("[%s] Starting rollback (revision: %s)...",
             environment, revision or "previous")

    set_cluster_context(environment)

    cmd = ["kubectl", "rollout", "undo",
           f"deployment/{DEPLOYMENT}", "-n", NAMESPACE]
    if revision:
        cmd += ["--to-revision", str(revision)]

    run(cmd)

    if health_check(environment, timeout=120):
        log.info("[%s] Rollback SUCCESSFUL ✓", environment)
    else:
        log.error("[%s] Rollback health check FAILED — manual intervention required", environment)
        sys.exit(1)


def status(environment):
    """Show current deployment status: image, replicas, pod states."""
    log.info("[%s] Fetching deployment status...", environment)

    set_cluster_context(environment)

    # Current image tag
    run(["kubectl", "get", "deployment", DEPLOYMENT,
         "-n", NAMESPACE,
         "-o", "jsonpath=Image: {.spec.template.spec.containers[0].image}\\n"])

    # Rollout history (last 5 revisions)
    run(["kubectl", "rollout", "history",
         f"deployment/{DEPLOYMENT}", "-n", NAMESPACE])

    # Pod states
    run(["kubectl", "get", "pods",
         "-n", NAMESPACE,
         "-l", f"app={DEPLOYMENT}",
         "-o", "wide"])


def parse_args():
    parser = argparse.ArgumentParser(
        description="Deploy, rollback, or check status of video-analytics service"
    )
    sub = parser.add_subparsers(dest="command", required=True)

    # deploy subcommand
    p_deploy = sub.add_parser("deploy", help="Deploy a new image to an environment")
    p_deploy.add_argument("--environment", required=True, choices=["staging", "production"])
    p_deploy.add_argument("--image-tag",   required=True, help="Docker image tag (e.g. git SHA)")
    p_deploy.add_argument("--dry-run",     action="store_true", help="Print commands without executing")

    # rollback subcommand
    p_rollback = sub.add_parser("rollback", help="Rollback to the previous deployment revision")
    p_rollback.add_argument("--environment", required=True, choices=["staging", "production"])
    p_rollback.add_argument("--revision", type=int, default=None,
                            help="Specific revision number (defaults to previous)")

    # status subcommand
    p_status = sub.add_parser("status", help="Show current deployment status")
    p_status.add_argument("--environment", required=True, choices=["staging", "production"])

    return parser.parse_args()


def main():
    args = parse_args()

    if args.command == "deploy":
        deploy(args.environment, args.image_tag, args.dry_run)
    elif args.command == "rollback":
        rollback(args.environment, args.revision)
    elif args.command == "status":
        status(args.environment)


if __name__ == "__main__":
    main()
