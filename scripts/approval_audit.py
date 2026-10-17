#!/usr/bin/env python3
"""Create an approval audit for merged PRs and environment deployments."""
from __future__ import annotations

import argparse
import csv
import json
import os
import subprocess
from pathlib import Path
from typing import Any, Dict, Iterable, List


def read_json(path: Path) -> Any:
    return json.loads(path.read_text())


def gh_json(endpoint: str) -> Any:
    result = subprocess.run(
        ["gh", "api", "--paginate", "--slurp", endpoint],
        check=True,
        capture_output=True,
        text=True,
    )
    return json.loads(result.stdout)


def list_items(value: Any) -> List[Dict[str, Any]]:
    if isinstance(value, list):
        result: List[Dict[str, Any]] = []
        for page in value:
            if isinstance(page, list):
                result.extend(page)
            elif isinstance(page, dict):
                result.append(page)
        return result
    return value if isinstance(value, list) else []


def collect_live(repo: str) -> Dict[str, Any]:
    prs = [pr for pr in list_items(gh_json(f"repos/{repo}/pulls?state=closed&base=main&per_page=100")) if pr.get("merged_at")]
    reviews: List[Dict[str, Any]] = []
    for pr in prs:
        for review in list_items(gh_json(f"repos/{repo}/pulls/{pr['number']}/reviews?per_page=100")):
            reviews.append({"pull_number": pr["number"], **review})
    deployments = list_items(gh_json(f"repos/{repo}/deployments?per_page=100"))
    for deployment in deployments:
        statuses = list_items(gh_json(f"repos/{repo}/deployments/{deployment['id']}/statuses?per_page=100"))
        deployment["statuses"] = statuses
    return {"prs": prs, "reviews": reviews, "deployments": deployments}


def collect_offline(fixtures: Path) -> Dict[str, Any]:
    return {
        "prs": read_json(fixtures / "prs.json"),
        "reviews": read_json(fixtures / "reviews.json"),
        "deployments": read_json(fixtures / "deployments.json"),
    }


def approval_rows(data: Dict[str, Any]) -> List[Dict[str, str]]:
    prs = {str(pr["number"]): pr for pr in data["prs"] if pr.get("merged_at")}
    rows: List[Dict[str, str]] = []
    for review in data["reviews"]:
        number = str(review.get("pull_number", review.get("number", "")))
        pr = prs.get(number)
        if not pr or review.get("state") != "APPROVED":
            continue
        user = review.get("user", {})
        rows.append({
            "kind": "pull_request",
            "pr": number,
            "title": pr.get("title", ""),
            "environment": "",
            "approver": user.get("login", review.get("approver", "")),
            "approved_at": review.get("submitted_at", review.get("approved_at", "")),
        })
    for deployment in data["deployments"]:
        number = str(deployment.get("pull_number", deployment.get("pr", "")))
        if number and number not in prs:
            continue
        environment = deployment.get("environment", "")
        approvals = deployment.get("approvals", [])
        if approvals:
            for approval in approvals:
                rows.append({
                    "kind": "deployment",
                    "pr": number,
                    "title": prs.get(number, {}).get("title", ""),
                    "environment": environment,
                    "approver": approval.get("user", {}).get("login", approval.get("approver", "")),
                    "approved_at": approval.get("approved_at", approval.get("created_at", "")),
                })
        else:
            # Deployment status is the API's durable record when an environment
            # approval is represented by a successful deployment status.
            for status in deployment.get("statuses", []):
                if status.get("state") == "success":
                    creator = status.get("creator", {})
                    rows.append({
                        "kind": "deployment",
                        "pr": number,
                        "title": prs.get(number, {}).get("title", ""),
                        "environment": environment,
                        "approver": creator.get("login", ""),
                        "approved_at": status.get("created_at", ""),
                    })
    return sorted(rows, key=lambda row: (row["pr"], 0 if row["kind"] == "pull_request" else 1, row["approver"]))


def write_reports(rows: Iterable[Dict[str, str]], output_prefix: Path) -> None:
    materialized = list(rows)
    csv_path = output_prefix.with_suffix(".csv")
    md_path = output_prefix.with_suffix(".md")
    csv_path.parent.mkdir(parents=True, exist_ok=True)
    fields = ["kind", "pr", "title", "environment", "approver", "approved_at"]
    with csv_path.open("w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fields)
        writer.writeheader()
        writer.writerows(materialized)
    lines = ["# Release approval audit", "", "| Kind | PR | Title | Environment | Approver | Approved at |", "| --- | ---: | --- | --- | --- | --- |"]
    for row in materialized:
        cells = [row[field].replace("|", "\\|") for field in fields]
        lines.append("| " + " | ".join(cells) + " |")
    md_path.write_text("\n".join(lines) + "\n")
    print(f"Wrote {md_path} and {csv_path} ({len(materialized)} approvals)")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo", default="")
    parser.add_argument("--offline", action="store_true")
    parser.add_argument("--fixtures", type=Path, default=Path("audit/fixtures"))
    parser.add_argument("--output-prefix", type=Path, default=Path("audit/report"))
    args = parser.parse_args()
    data = collect_offline(args.fixtures) if args.offline else collect_live(args.repo or os.environ["GITHUB_REPOSITORY"])
    write_reports(approval_rows(data), args.output_prefix)


if __name__ == "__main__":
    main()
