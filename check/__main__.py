"""
Syntax checker for DevOps interview submission.

Validates that your files parse correctly before submission.
This does NOT score your work — scoring is done by the hiring team.

Usage:
    python -m check                          # Check all files
    python -m check --module terraform       # Check one module
"""

import argparse
import ast
import os
import subprocess
import sys

import yaml

try:
    import hcl2
    HCL2_AVAILABLE = True
except ImportError:
    HCL2_AVAILABLE = False


SUBMISSION_DIR = os.path.join(os.path.dirname(os.path.dirname(__file__)), "submission")

PASS = "\033[92mPASS\033[0m"
FAIL = "\033[91mFAIL\033[0m"
SKIP = "\033[93mSKIP\033[0m"


def check_terraform():
    """Check Terraform files parse as valid HCL."""
    print("\n--- Terraform ---")
    tf_dir = os.path.join(SUBMISSION_DIR, "terraform")
    if not HCL2_AVAILABLE:
        print(f"  [{SKIP}] python-hcl2 not installed (pip install python-hcl2)")
        return 0, 0

    errors = 0
    checked = 0
    for fname in sorted(os.listdir(tf_dir)):
        if not fname.endswith(".tf"):
            continue
        fpath = os.path.join(tf_dir, fname)
        checked += 1
        try:
            with open(fpath, "r") as f:
                hcl2.load(f)
            print(f"  [{PASS}] {fname}")
        except Exception as e:
            print(f"  [{FAIL}] {fname}: {e}")
            errors += 1
    return checked, errors


def check_kubernetes():
    """Check Kubernetes YAML files parse correctly."""
    print("\n--- Kubernetes ---")
    k8s_dir = os.path.join(SUBMISSION_DIR, "k8s")
    errors = 0
    checked = 0
    for fname in sorted(os.listdir(k8s_dir)):
        if not fname.endswith((".yaml", ".yml")):
            continue
        fpath = os.path.join(k8s_dir, fname)
        with open(fpath, "r") as f:
            content = f.read()

        # Skip comment-only files
        has_yaml = any(
            l.strip() and not l.strip().startswith("#")
            for l in content.splitlines()
        )
        if not has_yaml:
            print(f"  [{SKIP}] {fname} (no YAML content yet)")
            continue

        checked += 1
        try:
            list(yaml.safe_load_all(content))
            print(f"  [{PASS}] {fname}")
        except yaml.YAMLError as e:
            print(f"  [{FAIL}] {fname}: {e}")
            errors += 1
    return checked, errors


def check_shell():
    """Check shell scripts for syntax errors."""
    print("\n--- Shell Scripts ---")
    errors = 0
    checked = 0

    sh_files = []
    for subdir in ["network", "edge", "debug"]:
        d = os.path.join(SUBMISSION_DIR, subdir)
        if not os.path.isdir(d):
            continue
        for fname in sorted(os.listdir(d)):
            if fname.endswith(".sh"):
                sh_files.append((subdir, fname, os.path.join(d, fname)))

    for subdir, fname, fpath in sh_files:
        with open(fpath, "r") as f:
            content = f.read()
        non_comment = [l for l in content.splitlines() if l.strip() and not l.strip().startswith("#")]
        if len(non_comment) < 3:
            print(f"  [{SKIP}] {subdir}/{fname} (skeleton only)")
            continue

        checked += 1
        # Try shellcheck if available
        try:
            result = subprocess.run(
                ["shellcheck", "-S", "error", fpath],
                capture_output=True, text=True, timeout=30,
            )
            if result.returncode == 0:
                print(f"  [{PASS}] {subdir}/{fname}")
            else:
                print(f"  [{FAIL}] {subdir}/{fname}")
                for line in result.stdout.strip().splitlines()[:5]:
                    print(f"         {line}")
                errors += 1
        except FileNotFoundError:
            # shellcheck not installed, just check for shebang
            if content.strip().startswith("#!/"):
                print(f"  [{PASS}] {subdir}/{fname} (shellcheck not installed, basic check only)")
            else:
                print(f"  [{FAIL}] {subdir}/{fname}: missing shebang (#!/...)")
                errors += 1

    return checked, errors


def check_python():
    """Check Python files for syntax errors."""
    print("\n--- Python ---")
    errors = 0
    checked = 0

    py_files = [
        ("network", "camera_discovery.py"),
        ("cicd", "deploy.py"),
    ]

    for subdir, fname in py_files:
        fpath = os.path.join(SUBMISSION_DIR, subdir, fname)
        if not os.path.exists(fpath):
            continue
        checked += 1
        try:
            with open(fpath, "r") as f:
                content = f.read()
            ast.parse(content)
            print(f"  [{PASS}] {subdir}/{fname}")
        except SyntaxError as e:
            print(f"  [{FAIL}] {subdir}/{fname}: {e}")
            errors += 1

    return checked, errors


def check_pipeline():
    """Check pipeline YAML syntax."""
    print("\n--- Pipeline ---")
    fpath = os.path.join(SUBMISSION_DIR, "cicd", "pipeline.yaml")
    with open(fpath, "r") as f:
        content = f.read()

    has_yaml = any(
        l.strip() and not l.strip().startswith("#")
        for l in content.splitlines()
    )
    if not has_yaml:
        print(f"  [{SKIP}] pipeline.yaml (no YAML content yet)")
        return 0, 0

    try:
        yaml.safe_load(content)
        print(f"  [{PASS}] pipeline.yaml")
        return 1, 0
    except yaml.YAMLError as e:
        print(f"  [{FAIL}] pipeline.yaml: {e}")
        return 1, 1


MODULE_CHECKS = {
    "terraform": check_terraform,
    "k8s": check_kubernetes,
    "network": check_shell,
    "cicd": lambda: (check_pipeline()[0] + check_python()[0], check_pipeline()[1] + check_python()[1]),
    "python": check_python,
    "shell": check_shell,
    "pipeline": check_pipeline,
}


def main():
    parser = argparse.ArgumentParser(
        description="Check submission files for syntax errors",
        prog="python -m check",
    )
    parser.add_argument(
        "--module",
        choices=["terraform", "k8s", "network", "cicd"],
        help="Check a single module",
    )
    args = parser.parse_args()

    print("Submission Syntax Checker")
    print("=" * 40)
    print("This checks that your files parse correctly.")
    print("Full scoring is done by the hiring team.")

    total_checked = 0
    total_errors = 0

    if args.module:
        checks = {args.module: MODULE_CHECKS[args.module]}
    else:
        checks = {
            "terraform": check_terraform,
            "k8s": check_kubernetes,
            "shell": check_shell,
            "python": check_python,
            "pipeline": check_pipeline,
        }

    for name, check_fn in checks.items():
        checked, errors = check_fn()
        total_checked += checked
        total_errors += errors

    print("\n" + "=" * 40)
    if total_errors == 0:
        print(f"All {total_checked} checked files passed syntax validation.")
    else:
        print(f"{total_errors} of {total_checked} files have errors.")

    sys.exit(1 if total_errors > 0 else 0)


if __name__ == "__main__":
    main()
