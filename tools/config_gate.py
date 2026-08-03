#!/usr/bin/env python3
import json
import sys
from pathlib import Path


def parse_config(path: str) -> dict[str, str]:
    result: dict[str, str] = {}
    for raw in Path(path).read_text(encoding="utf-8").splitlines():
        if raw.startswith("CONFIG_") and "=" in raw:
            key, value = raw.split("=", 1)
            result[key] = value
        elif raw.startswith("# CONFIG_") and raw.endswith(" is not set"):
            result[raw[2:-11]] = "n"
    return result


def main() -> int:
    if len(sys.argv) != 4:
        print("usage: config_gate.py BASELINE BUILT REPORT", file=sys.stderr)
        return 2

    baseline_path, built_path, report_path = sys.argv[1:]
    baseline = parse_config(baseline_path)
    built = parse_config(built_path)

    changes = []
    for symbol in sorted(set(baseline) | set(built)):
        before = baseline.get(symbol)
        after = built.get(symbol)
        if before != after:
            changes.append({"symbol": symbol, "before": before, "after": after})

    # The source already contains real manual hooks. KernelSU forks expose
    # different auxiliary KSU symbols, so only the CONFIG_KSU* namespace may
    # differ from the embedded V55 baseline.
    unexpected = [
        change for change in changes
        if not change["symbol"].startswith("CONFIG_KSU")
    ]

    required = {
        "CONFIG_OVERLAY_FS": "y",
        "CONFIG_KSU": "y",
        "CONFIG_KSU_SUSFS": "y",
        "CONFIG_KSU_SUSFS_SUS_MOUNT": "y",
        "CONFIG_KSU_SUSFS_SUS_KSTAT": "y",
        "CONFIG_KSU_SUSFS_SUS_OVERLAYFS": "y",
        "CONFIG_KSU_SUSFS_TRY_UMOUNT": "y",
        "CONFIG_KSU_SUSFS_SPOOF_UNAME": "y",
        "CONFIG_KSU_SUSFS_SUS_PATH": "n",
        "CONFIG_KSU_SUSFS_SUS_SU": "n",
        "CONFIG_KSU_SUSFS_ENABLE_LOG": "n",
    }
    profile_errors = [
        {"symbol": symbol, "expected": expected, "actual": built.get(symbol, "n")}
        for symbol, expected in required.items()
        if built.get(symbol, "n") != expected
    ]

    report = {
        "baseline": baseline_path,
        "built": built_path,
        "all_changes": changes,
        "unexpected_changes": unexpected,
        "profile_errors": profile_errors,
        "pass": not unexpected and not profile_errors,
    }
    Path(report_path).write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")

    if unexpected or profile_errors:
        print(json.dumps(report, indent=2), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
