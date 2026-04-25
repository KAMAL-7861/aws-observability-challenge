"""Security group checks — detect unrestricted inbound rules on application ports.

Application ports checked: 3550 (gRPC), 8080 (frontend), 30550 (NodePort).

AWS CLI equivalents for manual verification::

    # List security groups for EKS nodes
    aws ec2 describe-instances \\
        --filters "Name=tag:kubernetes.io/cluster/<cluster>,Values=owned" \\
        --query "Reservations[].Instances[].SecurityGroups[]" \\
        --region <region>

    # Inspect a specific security group's inbound rules
    aws ec2 describe-security-groups \\
        --group-ids <sg_id> \\
        --query "SecurityGroups[].IpPermissions" \\
        --region <region>
"""

from __future__ import annotations

import boto3

from verification.checks.base import BaseCheck, CheckResult

APPLICATION_PORTS = {3550, 8080, 30550}


class UnrestrictedSGCheck(BaseCheck):
    """Check that no SG on EKS nodes allows 0.0.0.0/0 or ::/0 on app ports."""

    @property
    def name(self) -> str:
        return "no_unrestricted_sg_ingress"

    @property
    def description(self) -> str:
        return (
            "Verify no security group on EKS worker nodes allows "
            "unrestricted inbound access on application ports"
        )

    def run(self, session: boto3.Session, config: dict) -> list[CheckResult]:
        results: list[CheckResult] = []
        clusters = []
        if config.get("c1_cluster") and config.get("c1_region"):
            clusters.append((config["c1_region"], config["c1_cluster"]))
        if config.get("c2_cluster") and config.get("c2_region"):
            clusters.append((config["c2_region"], config["c2_cluster"]))

        for region, cluster_name in clusters:
            ec2 = session.client("ec2", region_name=region)
            results.extend(self._check_cluster(ec2, cluster_name))

        if not results:
            results.append(
                CheckResult(
                    check_name=self.name,
                    passed=True,
                    resource_id=None,
                    details="No security groups found for the given clusters",
                    remediation=None,
                )
            )
        return results

    def _check_cluster(self, ec2_client, cluster_name: str) -> list[CheckResult]:
        """Collect SG IDs from EKS nodes and inspect their inbound rules."""
        paginator = ec2_client.get_paginator("describe_instances")
        page_iter = paginator.paginate(
            Filters=[
                {
                    "Name": f"tag:kubernetes.io/cluster/{cluster_name}",
                    "Values": ["owned", "shared"],
                }
            ]
        )

        sg_ids: set[str] = set()
        for page in page_iter:
            for reservation in page.get("Reservations", []):
                for inst in reservation.get("Instances", []):
                    for sg in inst.get("SecurityGroups", []):
                        sg_ids.add(sg["GroupId"])

        if not sg_ids:
            return []

        resp = ec2_client.describe_security_groups(GroupIds=list(sg_ids))
        sg_rules = resp.get("SecurityGroups", [])
        return self.analyze_security_groups(sg_rules)

    # ------------------------------------------------------------------
    # Pure-logic helper for property-based testing
    # ------------------------------------------------------------------

    @staticmethod
    def analyze_security_groups(
        security_groups: list[dict],
        app_ports: list[int] | None = None,
    ) -> list[CheckResult]:
        """Evaluate security group rules without calling AWS APIs.

        Args:
            security_groups: List of SG dicts as returned by
                ``describe_security_groups``.  Each must have ``GroupId``
                and ``IpPermissions``.
            app_ports: Application ports to check.  Defaults to
                ``APPLICATION_PORTS`` (3550, 8080, 30550).
        """
        target_ports = set(app_ports) if app_ports else APPLICATION_PORTS
        results: list[CheckResult] = []
        seen_violations: set[str] = set()
        has_any_violation = False

        for sg in security_groups:
            sg_id = sg.get("GroupId", "unknown")
            for perm in sg.get("IpPermissions", []):
                from_port = perm.get("FromPort")
                to_port = perm.get("ToPort")
                protocol = perm.get("IpProtocol", "")

                # protocol -1 means all traffic
                if protocol == "-1":
                    ports_match = True
                elif from_port is not None and to_port is not None:
                    ports_match = any(
                        from_port <= p <= to_port for p in target_ports
                    )
                else:
                    ports_match = False

                if not ports_match:
                    continue

                # Check IPv4 ranges
                for ip_range in perm.get("IpRanges", []):
                    cidr = ip_range.get("CidrIp", "")
                    if cidr == "0.0.0.0/0":
                        key = f"{sg_id}:{from_port}-{to_port}:ipv4"
                        if key not in seen_violations:
                            seen_violations.add(key)
                            has_any_violation = True
                            port_desc = (
                                "all ports"
                                if protocol == "-1"
                                else f"ports {from_port}-{to_port}"
                            )
                            results.append(
                                CheckResult(
                                    check_name="no_unrestricted_sg_ingress",
                                    passed=False,
                                    resource_id=sg_id,
                                    details=(
                                        f"Security group {sg_id} allows "
                                        f"0.0.0.0/0 on {port_desc}"
                                    ),
                                    remediation=(
                                        f"Remove the 0.0.0.0/0 inbound rule on "
                                        f"{port_desc} from security group {sg_id}"
                                    ),
                                )
                            )

                # Check IPv6 ranges
                for ip_range in perm.get("Ipv6Ranges", []):
                    cidr = ip_range.get("CidrIpv6", "")
                    if cidr == "::/0":
                        key = f"{sg_id}:{from_port}-{to_port}:ipv6"
                        if key not in seen_violations:
                            seen_violations.add(key)
                            has_any_violation = True
                            port_desc = (
                                "all ports"
                                if protocol == "-1"
                                else f"ports {from_port}-{to_port}"
                            )
                            results.append(
                                CheckResult(
                                    check_name="no_unrestricted_sg_ingress",
                                    passed=False,
                                    resource_id=sg_id,
                                    details=(
                                        f"Security group {sg_id} allows "
                                        f"::/0 on {port_desc}"
                                    ),
                                    remediation=(
                                        f"Remove the ::/0 inbound rule on "
                                        f"{port_desc} from security group {sg_id}"
                                    ),
                                )
                            )

        if not has_any_violation:
            # Summarize as a single pass result
            sg_ids_str = ", ".join(sg.get("GroupId", "?") for sg in security_groups)
            results.append(
                CheckResult(
                    check_name="no_unrestricted_sg_ingress",
                    passed=True,
                    resource_id=sg_ids_str or None,
                    details=(
                        "No unrestricted inbound rules on application ports "
                        f"found in security groups: {sg_ids_str}"
                        if sg_ids_str
                        else "No security groups to evaluate"
                    ),
                    remediation=None,
                )
            )

        return results
