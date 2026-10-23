#!/usr/bin/env python3
"""Deploy an exact green Android + iPhone mobile PWA push build to Spark QA.

Requires locally authenticated gh/Firebase CLIs. No secret values are read or
uploaded. Never deploys Firestore Rules, Functions, or the account-deletion site.
"""
from __future__ import annotations
import argparse
import json
from pathlib import Path
import shutil
import subprocess
import sys

REPO = "analienx/baby-sleep-tracker"
BRANCH = "feat/ios-home-screen-pwa"
PROJECT = "little-rest-stage-jh-261020"
SITE = "little-rest-ios-qa"  # Legacy origin; shared by Android and iPhone.
WORKFLOW = "ios-pwa-ci.yml"
REQUIRED = (
    "index.html", "main.dart.js", "flutter_bootstrap.js",
    "pwa-sw.js", "storage_probe.js", "manifest.json",
    "install_prompt.js",
)


def command(*parts: str) -> str:
    return subprocess.check_output(parts, text=True, encoding="utf-8").strip()


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-sha", help="Previously green source commit; must be an ancestor of HEAD")
    parser.add_argument("--branch", choices=(BRANCH, "feat/multi-baby-spark-family"), default=BRANCH, help="Exact reviewed PWA source branch")
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    git = shutil.which("git") or "git"
    sha = args.source_sha or command(git, "-C", str(root), "rev-parse", "HEAD")
    if len(sha) != 40 or any(c not in "0123456789abcdef" for c in sha):
        raise RuntimeError("Untrusted source SHA.")
    subprocess.run([git, "-C", str(root), "merge-base", "--is-ancestor",
                    sha, "HEAD"], check=True)
    status = command(git, "-C", str(root), "status", "--porcelain")
    if status:
        raise RuntimeError("Repository worktree is dirty; refusing deployment.")

    config = json.loads((root / "firebase.pwa.json").read_text(encoding="utf-8-sig"))
    hosting = config.get("hosting", {})
    if hosting.get("site") != SITE or hosting.get("public") != "build/web":
        raise RuntimeError("Wrong Firebase Hosting target.")
    if any(key in config for key in ("firestore", "functions", "storage")):
        raise RuntimeError("Unexpected non-Hosting resources in PWA config.")

    gh = shutil.which("gh") or "gh"
    runs = json.loads(command(
        gh, "run", "list", "-R", REPO, "--workflow", WORKFLOW,
        "--branch", args.branch, "--limit", "50",
        "--json", "databaseId,event,headSha,status,conclusion,url"
    ))
    matches = [r for r in runs if r.get("headSha") == sha
               and r.get("event") == "push"
               and r.get("status") == "completed"
               and r.get("conclusion") == "success"]
    if len(matches) != 1:
        raise RuntimeError(f"Expected one green push build for {sha}; found {len(matches)}.")
    run = matches[0]
    run_id = str(run["databaseId"])
    artifact = f"little-rest-ios-pwa-staging-{sha}"
    archive = json.loads(command(gh, "api", f"repos/{REPO}/actions/runs/{run_id}/artifacts"))
    candidates = [a for a in archive.get("artifacts", [])
                  if a.get("name") == artifact and not a.get("expired")]
    if len(candidates) != 1:
        raise RuntimeError("Missing/ambiguous exact-SHA PWA artifact.")

    out = root / "build" / "pwa-release-artifact" / run_id
    if out.exists():
        raise RuntimeError("Artifact directory already exists; clear manually to retry.")
    out.mkdir(parents=True)
    subprocess.run([gh, "run", "download", run_id, "-R", REPO,
                    "--name", artifact, "--dir", str(out)], check=True)
    for name in REQUIRED:
        if not (out / name).is_file():
            raise RuntimeError(f"Missing compiled asset {name}; cannot deploy.")
    if (out / "main.dart.js").stat().st_size < 100000:
        raise RuntimeError("Suspicious compiled application size.")
    manifest = json.loads((out / "manifest.json").read_text(encoding="utf-8-sig"))
    if manifest.get("display") != "standalone" or manifest.get("start_url") != "/" or manifest.get("id") != "/":
        raise RuntimeError("PWA manifest failed installability checks.")
    sw = (out / "pwa-sw.js").read_text(encoding="utf-8")
    if "little-rest-shell-" not in sw or "url.origin !== self.location.origin" not in sw or "/install_prompt.js" not in sw:
        raise RuntimeError("Offline shell does not pass same-origin guard.")

    public = root / "build" / "web"
    if public.exists():
        shutil.rmtree(public)
    shutil.copytree(out, public)
    print(f"Verified GitHub push run #{run_id}, commit {sha[:12]}, separate site {SITE}.")
    firebase = shutil.which("firebase.cmd") or shutil.which("firebase") or "firebase"
    subprocess.run([firebase, "deploy", "--config", str(root / "firebase.pwa.json"),
                    "--only", "hosting", "--project", PROJECT,
                    "--non-interactive"], cwd=root, check=True)
    print(f"SUCCESS: https://{SITE}.web.app")


if __name__ == "__main__":
    try:
        main()
    except (RuntimeError, subprocess.CalledProcessError, OSError, ValueError) as exc:
        print(f"PWA DEPLOYMENT BLOCKED: {exc}", file=sys.stderr)
        sys.exit(1)
