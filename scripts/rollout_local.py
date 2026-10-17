#!/usr/bin/env python3
"""Apply a named rollout stage to the local FeatureManagement settings."""
from __future__ import annotations

import argparse
import json
from pathlib import Path


def stage_values(stage: str) -> dict[str, object]:
    if stage == "internal":
        return {
            "FeatureManagement:VolumeDiscounts": {"EnabledFor": [{"Name": "Targeting", "Parameters": {"Audience": {"Groups": ["internal"], "DefaultRolloutPercentage": 0}}}]},
            "FeatureManagement:RegionalTax": {"EnabledFor": [{"Name": "Targeting", "Parameters": {"Audience": {"Groups": ["internal"], "DefaultRolloutPercentage": 0}}}]},
            "FeatureManagement:KillSwitch": False,
        }
    if stage == "10":
        return {
            "FeatureManagement:VolumeDiscounts": {"EnabledFor": [{"Name": "Targeting", "Parameters": {"Audience": {"Groups": ["internal"], "DefaultRolloutPercentage": 10}}}]},
            "FeatureManagement:RegionalTax": {"EnabledFor": [{"Name": "Targeting", "Parameters": {"Audience": {"Groups": ["internal"], "DefaultRolloutPercentage": 10}}}]},
            "FeatureManagement:KillSwitch": False,
        }
    if stage == "100":
        return {"FeatureManagement:VolumeDiscounts": True, "FeatureManagement:RegionalTax": True, "FeatureManagement:KillSwitch": False}
    if stage == "kill":
        return {"FeatureManagement:KillSwitch": True}
    raise ValueError("stage must be internal, 10, 100, or kill")


def apply(path: Path, stage: str) -> None:
    document = json.loads(path.read_text())
    feature_management = document.setdefault("FeatureManagement", {})
    for key, value in stage_values(stage).items():
        feature_management[key.split(":")[-1]] = value
    path.write_text(json.dumps(document, indent=2) + "\n")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("stage", choices=["internal", "10", "100", "kill"])
    parser.add_argument("--file", type=Path, default=Path("src/PricingApi/appsettings.json"))
    args = parser.parse_args()
    apply(args.file, args.stage)
    print(f"Applied {args.stage} to {args.file}")


if __name__ == "__main__":
    main()
