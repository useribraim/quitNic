#!/usr/bin/env python3
"""Enforce the documented simulator baselines plus a 20 percent regression ceiling."""

from __future__ import annotations

import re
import sys
from pathlib import Path


BUDGETS = {
    "ApplicationFirstFramePresentationResponsive": (1.80, "s"),
    "SettingsPresentation": (0.01992, "s"),
    "QuickLogPresentation": (0.03984, "s"),
    "JourneyPresentation": (0.18, "s"),
    "CoachPresentation": (0.10, "s"),
    "Scroll_DraggingAndDeceleration": (3.07968, "s"),
    "Memory Physical": (51697.0, "kB"),
}

DURATION_PATTERN = re.compile(
    r"measured \[Duration \((?P<name>[^)]+)\), s\] average: (?P<value>[0-9.]+)"
)
MEMORY_PATTERN = re.compile(
    r"measured \[(?P<name>Memory Physical) \([^)]+\), kB\] average: (?P<value>[0-9.]+)"
)


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: check_performance_budgets.py XCODEBUILD_LOG")
        return 2
    log = Path(sys.argv[1]).read_text(errors="replace")
    measurements = {
        match.group("name"): float(match.group("value"))
        for pattern in (DURATION_PATTERN, MEMORY_PATTERN)
        for match in pattern.finditer(log)
    }
    errors: list[str] = []
    for name, (maximum, unit) in BUDGETS.items():
        value = measurements.get(name)
        if value is None:
            errors.append(f"missing metric: {name}")
        elif value > maximum:
            errors.append(f"{name}: {value:g} {unit} exceeds {maximum:g} {unit}")
        else:
            print(f"{name}: {value:g}/{maximum:g} {unit}")
    if errors:
        print("Performance budget check failed:")
        for error in errors:
            print(f"- {error}")
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
