"""End-to-end connectivity check — verify ALB returns HTTP 200.

Curl equivalent for manual verification::

    curl -s -o /dev/null -w "%{http_code}" http://<alb_dns_name>/
"""

from __future__ import annotations

import requests
import boto3

from verification.checks.base import BaseCheck, CheckResult


class ConnectivityCheck(BaseCheck):
    """Send an HTTP request to the ALB endpoint and verify HTTP 200."""

    @property
    def name(self) -> str:
        return "connectivity_check"

    @property
    def description(self) -> str:
        return "Verify ALB endpoint returns HTTP 200"

    def run(self, session: boto3.Session, config: dict) -> list[CheckResult]:
        alb_dns_name = config.get("alb_dns_name")
        if not alb_dns_name:
            return [
                CheckResult(
                    check_name=self.name,
                    passed=False,
                    resource_id="N/A",
                    details="No alb_dns_name provided in config",
                    remediation="Provide alb_dns_name in the configuration",
                )
            ]

        url = (
            alb_dns_name
            if alb_dns_name.startswith("http")
            else f"http://{alb_dns_name}"
        )

        try:
            resp = requests.get(url, timeout=30)
            if resp.status_code == 200:
                return [
                    CheckResult(
                        check_name=self.name,
                        passed=True,
                        resource_id=alb_dns_name,
                        details=f"ALB endpoint {alb_dns_name} returned HTTP 200",
                        remediation=None,
                    )
                ]
            return [
                CheckResult(
                    check_name=self.name,
                    passed=False,
                    resource_id=alb_dns_name,
                    details=(
                        f"ALB endpoint {alb_dns_name} returned "
                        f"HTTP {resp.status_code} (expected 200)"
                    ),
                    remediation=(
                        "Verify the ALB target group has healthy targets "
                        "and the frontend service is running"
                    ),
                )
            ]
        except requests.RequestException as exc:
            return [
                CheckResult(
                    check_name=self.name,
                    passed=False,
                    resource_id=alb_dns_name,
                    details=f"Failed to connect to ALB endpoint {alb_dns_name}: {exc}",
                    remediation=(
                        "Verify the ALB DNS name is correct, the ALB is "
                        "active, and network connectivity is available"
                    ),
                )
            ]
