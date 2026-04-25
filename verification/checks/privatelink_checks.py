"""PrivateLink state checks — verify VPC Endpoint and Endpoint Service are available.

AWS CLI equivalents for manual verification::

    # Check VPC Endpoint state
    aws ec2 describe-vpc-endpoints \\
        --vpc-endpoint-ids <vpc_endpoint_id> \\
        --query "VpcEndpoints[].State" \\
        --region <c1_region>

    # Check VPC Endpoint Service state
    aws ec2 describe-vpc-endpoint-service-configurations \\
        --service-ids <endpoint_service_id> \\
        --query "ServiceConfigurations[].ServiceState" \\
        --region <c2_region>
"""

from __future__ import annotations

import boto3

from verification.checks.base import BaseCheck, CheckResult


class PrivateLinkStateCheck(BaseCheck):
    """Verify VPC Endpoint and Endpoint Service are both in 'available' state."""

    @property
    def name(self) -> str:
        return "privatelink_active"

    @property
    def description(self) -> str:
        return (
            "Verify VPC Endpoint and VPC Endpoint Service are in 'available' state"
        )

    def run(self, session: boto3.Session, config: dict) -> list[CheckResult]:
        results: list[CheckResult] = []

        vpc_endpoint_id = config.get("vpc_endpoint_id")
        endpoint_service_id = config.get("endpoint_service_id")
        c1_region = config.get("c1_region", "us-east-1")
        c2_region = config.get("c2_region", "us-west-2")

        if vpc_endpoint_id:
            results.append(self._check_vpc_endpoint(session, c1_region, vpc_endpoint_id))
        if endpoint_service_id:
            results.append(
                self._check_endpoint_service(session, c2_region, endpoint_service_id)
            )

        if not results:
            results.append(
                CheckResult(
                    check_name=self.name,
                    passed=False,
                    resource_id="N/A",
                    details="No vpc_endpoint_id or endpoint_service_id provided in config",
                    remediation="Provide vpc_endpoint_id and endpoint_service_id in the configuration",
                )
            )
        return results

    def _check_vpc_endpoint(
        self, session: boto3.Session, region: str, vpc_endpoint_id: str
    ) -> CheckResult:
        ec2 = session.client("ec2", region_name=region)
        resp = ec2.describe_vpc_endpoints(VpcEndpointIds=[vpc_endpoint_id])
        endpoints = resp.get("VpcEndpoints", [])
        if not endpoints:
            return CheckResult(
                check_name=self.name,
                passed=False,
                resource_id=vpc_endpoint_id,
                details=f"VPC Endpoint {vpc_endpoint_id} not found",
                remediation=f"Verify VPC Endpoint {vpc_endpoint_id} exists",
            )
        state = endpoints[0].get("State", "unknown")
        if state == "available":
            return CheckResult(
                check_name=self.name,
                passed=True,
                resource_id=vpc_endpoint_id,
                details=f"VPC Endpoint {vpc_endpoint_id} is in '{state}' state",
                remediation=None,
            )
        return CheckResult(
            check_name=self.name,
            passed=False,
            resource_id=vpc_endpoint_id,
            details=f"VPC Endpoint {vpc_endpoint_id} is in '{state}' state (expected 'available')",
            remediation=f"Investigate VPC Endpoint {vpc_endpoint_id} — current state is '{state}'",
        )

    def _check_endpoint_service(
        self, session: boto3.Session, region: str, endpoint_service_id: str
    ) -> CheckResult:
        ec2 = session.client("ec2", region_name=region)
        resp = ec2.describe_vpc_endpoint_service_configurations(
            ServiceIds=[endpoint_service_id]
        )
        configs = resp.get("ServiceConfigurations", [])
        if not configs:
            return CheckResult(
                check_name=self.name,
                passed=False,
                resource_id=endpoint_service_id,
                details=f"Endpoint Service {endpoint_service_id} not found",
                remediation=f"Verify Endpoint Service {endpoint_service_id} exists",
            )
        state = configs[0].get("ServiceState", "unknown")
        if state == "Available":
            return CheckResult(
                check_name=self.name,
                passed=True,
                resource_id=endpoint_service_id,
                details=f"Endpoint Service {endpoint_service_id} is in '{state}' state",
                remediation=None,
            )
        return CheckResult(
            check_name=self.name,
            passed=False,
            resource_id=endpoint_service_id,
            details=f"Endpoint Service {endpoint_service_id} is in '{state}' state (expected 'Available')",
            remediation=f"Investigate Endpoint Service {endpoint_service_id} — current state is '{state}'",
        )

    # ------------------------------------------------------------------
    # Pure-logic helpers for property-based testing
    # ------------------------------------------------------------------

    @staticmethod
    def analyze_states(
        endpoint_state: str,
        service_state: str,
        endpoint_id: str = "vpce-test",
        service_id: str = "vpces-test",
    ) -> list[CheckResult]:
        """Evaluate PrivateLink states without calling AWS APIs.

        Args:
            endpoint_state: State of the VPC Endpoint (e.g. 'available').
            service_state: State of the VPC Endpoint Service (e.g. 'Available').
            endpoint_id: VPC Endpoint ID for result reporting.
            service_id: VPC Endpoint Service ID for result reporting.
        """
        results: list[CheckResult] = []

        if endpoint_state == "available":
            results.append(
                CheckResult(
                    check_name="privatelink_active",
                    passed=True,
                    resource_id=endpoint_id,
                    details=f"VPC Endpoint {endpoint_id} is in '{endpoint_state}' state",
                    remediation=None,
                )
            )
        else:
            results.append(
                CheckResult(
                    check_name="privatelink_active",
                    passed=False,
                    resource_id=endpoint_id,
                    details=f"VPC Endpoint {endpoint_id} is in '{endpoint_state}' state (expected 'available')",
                    remediation=f"Investigate VPC Endpoint {endpoint_id} — current state is '{endpoint_state}'",
                )
            )

        if service_state == "Available":
            results.append(
                CheckResult(
                    check_name="privatelink_active",
                    passed=True,
                    resource_id=service_id,
                    details=f"Endpoint Service {service_id} is in '{service_state}' state",
                    remediation=None,
                )
            )
        else:
            results.append(
                CheckResult(
                    check_name="privatelink_active",
                    passed=False,
                    resource_id=service_id,
                    details=f"Endpoint Service {service_id} is in '{service_state}' state (expected 'Available')",
                    remediation=f"Investigate Endpoint Service {service_id} — current state is '{service_state}'",
                )
            )

        return results
