"""WAF association checks — verify WAF Web ACL is associated with the ALB.

AWS CLI equivalents for manual verification::

    # List WAF Web ACLs
    aws wafv2 list-web-acls --scope REGIONAL --region <region>

    # Get Web ACL details and check associated resources
    aws wafv2 get-web-acl \\
        --name <acl_name> --scope REGIONAL --id <acl_id> \\
        --region <region>

    # List resources associated with a Web ACL
    aws wafv2 list-resources-for-web-acl \\
        --web-acl-arn <web_acl_arn> \\
        --resource-type APPLICATION_LOAD_BALANCER \\
        --region <region>

SQLi test payload example (should be blocked by WAF)::

    curl -X POST "http://<alb_dns>/login" \\
        -d "username=admin' OR '1'='1&password=test"
"""

from __future__ import annotations

import boto3

from verification.checks.base import BaseCheck, CheckResult


class WAFAssociationCheck(BaseCheck):
    """Verify WAF Web ACL is associated with the target ALB and has managed rules."""

    @property
    def name(self) -> str:
        return "waf_associated"

    @property
    def description(self) -> str:
        return (
            "Verify WAF Web ACL is associated with the ALB "
            "and contains at least one managed rule group"
        )

    def run(self, session: boto3.Session, config: dict) -> list[CheckResult]:
        alb_arn = config.get("alb_arn")
        c1_region = config.get("c1_region", "us-east-1")

        if not alb_arn:
            return [
                CheckResult(
                    check_name=self.name,
                    passed=False,
                    resource_id="N/A",
                    details="No alb_arn provided in config",
                    remediation="Provide alb_arn in the configuration",
                )
            ]

        waf = session.client("wafv2", region_name=c1_region)
        return self._check_waf(waf, alb_arn)

    def _check_waf(self, waf_client, alb_arn: str) -> list[CheckResult]:
        """Query WAF Web ACLs and verify association + managed rules."""
        # List all regional Web ACLs
        acls = waf_client.list_web_acls(Scope="REGIONAL").get("WebACLs", [])
        for acl_summary in acls:
            acl_arn = acl_summary["ARN"]
            acl_detail = waf_client.get_web_acl(
                Name=acl_summary["Name"],
                Scope="REGIONAL",
                Id=acl_summary["Id"],
            ).get("WebACL", {})

            # Check association
            resources = waf_client.list_resources_for_web_acl(
                WebACLArn=acl_arn,
                ResourceType="APPLICATION_LOAD_BALANCER",
            ).get("ResourceArns", [])

            if alb_arn not in resources:
                continue

            # Found the ACL associated with our ALB — check for managed rules
            has_managed = any(
                rule.get("Statement", {}).get("ManagedRuleGroupStatement")
                for rule in acl_detail.get("Rules", [])
            )
            if has_managed:
                return [
                    CheckResult(
                        check_name=self.name,
                        passed=True,
                        resource_id=acl_arn,
                        details=(
                            f"WAF Web ACL {acl_arn} is associated with ALB "
                            f"{alb_arn} and has managed rule groups"
                        ),
                        remediation=None,
                    )
                ]
            else:
                return [
                    CheckResult(
                        check_name=self.name,
                        passed=False,
                        resource_id=acl_arn,
                        details=(
                            f"WAF Web ACL {acl_arn} is associated with ALB "
                            f"{alb_arn} but has no managed rule groups"
                        ),
                        remediation=(
                            "Add at least one managed rule group "
                            "(e.g. AWSManagedRulesCommonRuleSet) to the Web ACL"
                        ),
                    )
                ]

        # No ACL found associated with the ALB
        return [
            CheckResult(
                check_name=self.name,
                passed=False,
                resource_id=alb_arn,
                details=f"No WAF Web ACL is associated with ALB {alb_arn}",
                remediation=(
                    "Create a WAF Web ACL with managed rule groups and "
                    f"associate it with ALB {alb_arn}"
                ),
            )
        ]

    # ------------------------------------------------------------------
    # Pure-logic helper for property-based testing
    # ------------------------------------------------------------------

    @staticmethod
    def analyze_waf(web_acl: dict, target_alb_arn: str) -> list[CheckResult]:
        """Evaluate WAF configuration without calling AWS APIs.

        Args:
            web_acl: A dict representing the WAF Web ACL.  Expected keys:

                - ``ARN``: The Web ACL ARN.
                - ``AssociatedResources``: List of ALB ARNs associated with
                  this Web ACL.
                - ``Rules``: List of WAF rule dicts (each may contain a
                  ``ManagedRuleGroupStatement`` under ``Statement``).

            target_alb_arn: The ALB ARN that should be associated.

        Returns:
            A list with a single :class:`CheckResult`.
        """
        acl_arn = web_acl.get("ARN", "arn:aws:wafv2:::webacl/unknown")
        associated = web_acl.get("AssociatedResources", [])
        rules = web_acl.get("Rules", [])

        if target_alb_arn not in associated:
            return [
                CheckResult(
                    check_name="waf_associated",
                    passed=False,
                    resource_id=target_alb_arn,
                    details=f"No WAF Web ACL is associated with ALB {target_alb_arn}",
                    remediation=(
                        "Create a WAF Web ACL with managed rule groups and "
                        f"associate it with ALB {target_alb_arn}"
                    ),
                )
            ]

        has_managed = any(
            rule.get("Statement", {}).get("ManagedRuleGroupStatement")
            for rule in rules
        )
        if has_managed:
            return [
                CheckResult(
                    check_name="waf_associated",
                    passed=True,
                    resource_id=acl_arn,
                    details=(
                        f"WAF Web ACL {acl_arn} is associated with ALB "
                        f"{target_alb_arn} and has managed rule groups"
                    ),
                    remediation=None,
                )
            ]
        return [
            CheckResult(
                check_name="waf_associated",
                passed=False,
                resource_id=acl_arn,
                details=(
                    f"WAF Web ACL {acl_arn} is associated with ALB "
                    f"{target_alb_arn} but has no managed rule groups"
                ),
                remediation=(
                    "Add at least one managed rule group "
                    "(e.g. AWSManagedRulesCommonRuleSet) to the Web ACL"
                ),
            )
        ]
