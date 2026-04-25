#!/usr/bin/env python3
"""Verification tool CLI — validates AWS security posture and connectivity.

Example usage::

    # Run all checks with text output
    python -m verification.verify \\
        --c1-region us-east-1 --c1-cluster obs-challenge-c1 \\
        --c2-region us-west-2 --c2-cluster obs-challenge-c2 \\
        --alb-url http://my-alb-1234.us-east-1.elb.amazonaws.com \\
        --output text

    # Run all checks with JSON output
    python -m verification.verify \\
        --c1-region us-east-1 --c1-cluster obs-challenge-c1 \\
        --c2-region us-west-2 --c2-cluster obs-challenge-c2 \\
        --output json

Exit codes:
    0 — all checks passed
    1 — one or more checks failed
    2 — execution error (timeout, invalid args)

AWS CLI equivalents for each check (gap report 3.2):

  # NoPublicIPCheck — verify no EKS worker nodes have public IPs
  aws ec2 describe-instances \\
      --filters "Name=tag:kubernetes.io/cluster/<cluster>,Values=owned" \\
      --query "Reservations[].Instances[].[InstanceId,PublicIpAddress]" \\
      --region <region>

  # PrivateLinkStateCheck — verify VPC Endpoint state
  aws ec2 describe-vpc-endpoints \\
      --vpc-endpoint-ids <vpce_id> \\
      --query "VpcEndpoints[].State" --region <c1_region>
  aws ec2 describe-vpc-endpoint-service-configurations \\
      --service-ids <svc_id> \\
      --query "ServiceConfigurations[].ServiceState" --region <c2_region>

  # WAFAssociationCheck — verify WAF is associated with ALB
  aws wafv2 list-web-acls --scope REGIONAL --region <region>
  aws wafv2 get-web-acl --name <name> --scope REGIONAL --id <id> --region <region>
  aws wafv2 list-resources-for-web-acl \\
      --web-acl-arn <arn> --resource-type APPLICATION_LOAD_BALANCER --region <region>

  # UnrestrictedSGCheck — verify no unrestricted SG rules on app ports
  aws ec2 describe-security-groups \\
      --group-ids <sg_id> \\
      --query "SecurityGroups[].IpPermissions" --region <region>

  # ConnectivityCheck — verify ALB returns HTTP 200
  curl -s -o /dev/null -w "%{http_code}" http://<alb_dns>/
"""

from __future__ import annotations

import signal
import sys
import time
from typing import Any

import boto3
import click

from verification.checks import ALL_CHECKS
from verification.checks.base import CheckResult
from verification.report import format_json, format_text

DEFAULT_TIMEOUT = 120  # seconds
MAX_RETRIES = 3
INITIAL_BACKOFF = 1  # seconds


def _run_check_with_retry(
    check_instance, session: boto3.Session, config: dict
) -> list[CheckResult]:
    """Run a single check with exponential-backoff retry on API failures.

    Retries up to MAX_RETRIES times with exponential backoff starting at
    INITIAL_BACKOFF seconds.
    """
    last_exc: Exception | None = None
    for attempt in range(MAX_RETRIES):
        try:
            return check_instance.run(session, config)
        except Exception as exc:  # noqa: BLE001
            last_exc = exc
            if attempt < MAX_RETRIES - 1:
                wait = INITIAL_BACKOFF * (2 ** attempt)
                click.echo(
                    f"  ⚠ {check_instance.name} failed (attempt {attempt + 1}), "
                    f"retrying in {wait}s …",
                    err=True,
                )
                time.sleep(wait)

    # All retries exhausted
    return [
        CheckResult(
            check_name=check_instance.name,
            passed=False,
            resource_id="N/A",
            details=f"Check failed after {MAX_RETRIES} retries: {last_exc}",
            remediation="Verify AWS credentials and permissions, then retry",
        )
    ]


def _timeout_handler(signum, frame):
    """Handle SIGALRM — abort with exit code 2 when the 120s limit is hit."""
    click.echo("ERROR: Verification timed out (120s limit exceeded)", err=True)
    sys.exit(2)


@click.command(
    help=(
        "AWS security posture and connectivity verification tool.\n\n"
        "Runs all checks against the specified EKS clusters and reports "
        "pass/fail results.\n\n"
        "Examples:\n\n"
        "  python verify.py --c1-region us-east-1 --c1-cluster obs-c1 "
        "--c2-region us-west-2 --c2-cluster obs-c2 --output text\n\n"
        "  python verify.py --c1-region us-east-1 --c1-cluster obs-c1 "
        "--c2-region us-west-2 --c2-cluster obs-c2 "
        "--alb-url http://my-alb.elb.amazonaws.com --output json"
    )
)
@click.option("--c1-region", required=True, help="AWS region for cluster C1 (e.g. us-east-1)")
@click.option("--c1-cluster", required=True, help="EKS cluster name for C1")
@click.option("--c2-region", required=True, help="AWS region for cluster C2 (e.g. us-west-2)")
@click.option("--c2-cluster", required=True, help="EKS cluster name for C2")
@click.option(
    "--alb-url",
    default=None,
    help="ALB URL for connectivity check (e.g. http://my-alb.elb.amazonaws.com)",
)
@click.option(
    "--vpc-endpoint-id", default=None, help="VPC Endpoint ID for PrivateLink check"
)
@click.option(
    "--endpoint-service-id",
    default=None,
    help="VPC Endpoint Service ID for PrivateLink check",
)
@click.option(
    "--alb-arn", default=None, help="ALB ARN for WAF association check"
)
@click.option(
    "--output",
    "output_format",
    type=click.Choice(["json", "text"], case_sensitive=False),
    default="text",
    help="Output format (json or text)",
)
def main(
    c1_region: str,
    c1_cluster: str,
    c2_region: str,
    c2_cluster: str,
    alb_url: str | None,
    vpc_endpoint_id: str | None,
    endpoint_service_id: str | None,
    alb_arn: str | None,
    output_format: str,
) -> None:
    """Run all verification checks and produce a report."""
    # Set 120-second timeout (SIGALRM not available on Windows)
    if hasattr(signal, "SIGALRM"):
        signal.signal(signal.SIGALRM, _timeout_handler)
        signal.alarm(DEFAULT_TIMEOUT)

    config: dict[str, Any] = {
        "c1_region": c1_region,
        "c1_cluster": c1_cluster,
        "c2_region": c2_region,
        "c2_cluster": c2_cluster,
        "alb_dns_name": alb_url,
        "vpc_endpoint_id": vpc_endpoint_id,
        "endpoint_service_id": endpoint_service_id,
        "alb_arn": alb_arn,
    }

    session = boto3.Session()
    all_results: list[CheckResult] = []

    for check_cls in ALL_CHECKS:
        check = check_cls()
        click.echo(f"Running: {check.name} — {check.description}", err=True)
        results = _run_check_with_retry(check, session, config)
        all_results.extend(results)

    # Cancel timeout
    if hasattr(signal, "SIGALRM"):
        signal.alarm(0)

    # Output
    if output_format == "json":
        click.echo(format_json(all_results))
    else:
        click.echo(format_text(all_results))

    # Exit code: 0 = all passed, 1 = at least one failure
    any_failed = any(not r.passed for r in all_results)
    sys.exit(1 if any_failed else 0)


if __name__ == "__main__":
    main()
