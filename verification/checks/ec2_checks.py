"""EC2 security checks — verify no EKS worker nodes have public IPs.

AWS CLI equivalent for manual verification::

    aws ec2 describe-instances \\
        --filters "Name=tag:kubernetes.io/cluster/<cluster_name>,Values=owned" \\
        --query "Reservations[].Instances[].[InstanceId,PublicIpAddress]" \\
        --region <region>
"""

from __future__ import annotations

import boto3

from verification.checks.base import BaseCheck, CheckResult


class NoPublicIPCheck(BaseCheck):
    """Verify that no EKS worker node has a public IP address."""

    @property
    def name(self) -> str:
        return "no_public_ips_on_worker_nodes"

    @property
    def description(self) -> str:
        return "Verify no EKS worker node has a public IP address"

    def run(self, session: boto3.Session, config: dict) -> list[CheckResult]:
        results: list[CheckResult] = []
        clusters = []
        if config.get("c1_cluster") and config.get("c1_region"):
            clusters.append((config["c1_region"], config["c1_cluster"]))
        if config.get("c2_cluster") and config.get("c2_region"):
            clusters.append((config["c2_region"], config["c2_cluster"]))

        for region, cluster_name in clusters:
            ec2 = session.client("ec2", region_name=region)
            results.extend(
                self._check_cluster(ec2, cluster_name)
            )

        if not results:
            results.append(
                CheckResult(
                    check_name=self.name,
                    passed=True,
                    resource_id=None,
                    details="No EC2 instances found for the given clusters",
                    remediation=None,
                )
            )
        return results

    def _check_cluster(
        self, ec2_client, cluster_name: str
    ) -> list[CheckResult]:
        """Query instances tagged for *cluster_name* and check for public IPs."""
        paginator = ec2_client.get_paginator("describe_instances")
        page_iter = paginator.paginate(
            Filters=[
                {
                    "Name": f"tag:kubernetes.io/cluster/{cluster_name}",
                    "Values": ["owned", "shared"],
                }
            ]
        )

        checked: list[CheckResult] = []
        for page in page_iter:
            for reservation in page.get("Reservations", []):
                for inst in reservation.get("Instances", []):
                    instance_id = inst["InstanceId"]
                    public_ip = inst.get("PublicIpAddress")
                    if public_ip:
                        checked.append(
                            CheckResult(
                                check_name=self.name,
                                passed=False,
                                resource_id=instance_id,
                                details=(
                                    f"Instance {instance_id} has public IP {public_ip}"
                                ),
                                remediation=(
                                    f"Remove public IP from instance {instance_id} "
                                    "by launching in a private subnet with "
                                    "MapPublicIpOnLaunch=false"
                                ),
                            )
                        )
                    else:
                        checked.append(
                            CheckResult(
                                check_name=self.name,
                                passed=True,
                                resource_id=instance_id,
                                details=(
                                    f"Instance {instance_id} has no public IP"
                                ),
                                remediation=None,
                            )
                        )
        return checked

    # ------------------------------------------------------------------
    # Classmethod helpers for unit / property-based testing
    # ------------------------------------------------------------------

    @staticmethod
    def analyze_instances(instances: list[dict]) -> list[CheckResult]:
        """Pure-logic evaluation of EC2 instance dicts.

        Each dict is expected to have at least ``InstanceId`` and optionally
        ``PublicIpAddress``.  This is the function exercised by property tests.
        """
        results: list[CheckResult] = []
        for inst in instances:
            instance_id = inst.get("InstanceId", "unknown")
            public_ip = inst.get("PublicIpAddress")
            if public_ip:
                results.append(
                    CheckResult(
                        check_name="no_public_ips_on_worker_nodes",
                        passed=False,
                        resource_id=instance_id,
                        details=f"Instance {instance_id} has public IP {public_ip}",
                        remediation=(
                            f"Remove public IP from instance {instance_id} "
                            "by launching in a private subnet with "
                            "MapPublicIpOnLaunch=false"
                        ),
                    )
                )
            else:
                results.append(
                    CheckResult(
                        check_name="no_public_ips_on_worker_nodes",
                        passed=True,
                        resource_id=instance_id,
                        details=f"Instance {instance_id} has no public IP",
                        remediation=None,
                    )
                )
        return results
