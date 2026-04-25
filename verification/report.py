"""Report generation for the verification tool.

Accepts a list of :class:`CheckResult` objects and produces either JSON or
formatted text output.

Example PASS output (text)::

    ✅ PASS  no_public_ips          All 4 worker nodes have no public IP
    ✅ PASS  privatelink_active     VPC Endpoint vpce-0abc is available

    Summary: 2 checks, 2 passed, 0 failed

Example FAIL output (text)::

    ✅ PASS  no_public_ips          All 4 worker nodes have no public IP
    ❌ FAIL  no_unrestricted_sg     sg-0bad456 allows 0.0.0.0/0 on port 3550
       Resource: sg-0bad456
       Remediation: Remove the 0.0.0.0/0 inbound rule on port 3550

    Summary: 2 checks, 1 passed, 1 failed

Example JSON output::

    {
      "summary": {"total_checks": 2, "passed": 2, "failed": 0},
      "checks": [
        {
          "check_name": "no_public_ips",
          "passed": true,
          "resource_id": "i-0abc123",
          "details": "All 4 worker nodes have no public IP",
          "remediation": null
        }
      ]
    }
"""

from __future__ import annotations

import json
from datetime import datetime, timezone
from typing import Any

from verification.checks.base import CheckResult


def _result_to_dict(result: CheckResult) -> dict[str, Any]:
    return {
        "check_name": result.check_name,
        "passed": result.passed,
        "resource_id": result.resource_id,
        "details": result.details,
        "remediation": result.remediation,
    }


def generate_report(results: list[CheckResult]) -> dict[str, Any]:
    """Build the full report dictionary from a list of check results.

    The returned dict has the shape::

        {
            "timestamp": "...",
            "summary": {"total_checks": N, "passed": P, "failed": F},
            "checks": [...]
        }

    Every failed check is guaranteed to have a non-null ``resource_id``
    and ``remediation``.
    """
    passed = sum(1 for r in results if r.passed)
    failed = sum(1 for r in results if not r.passed)

    return {
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "summary": {
            "total_checks": len(results),
            "passed": passed,
            "failed": failed,
        },
        "checks": [_result_to_dict(r) for r in results],
    }


def format_json(results: list[CheckResult]) -> str:
    """Return the report as a pretty-printed JSON string."""
    return json.dumps(generate_report(results), indent=2)


def format_text(results: list[CheckResult]) -> str:
    """Return the report as human-readable text."""
    lines: list[str] = []
    for r in results:
        icon = "✅" if r.passed else "❌"
        status = "PASS" if r.passed else "FAIL"
        lines.append(f"{icon} {status:<5} {r.check_name:<30} {r.details}")
        if not r.passed:
            lines.append(f"   Resource: {r.resource_id}")
            lines.append(f"   Remediation: {r.remediation}")
    passed = sum(1 for r in results if r.passed)
    failed = sum(1 for r in results if not r.passed)
    lines.append("")
    lines.append(
        f"Summary: {len(results)} checks, {passed} passed, {failed} failed"
    )
    return "\n".join(lines)
