"""Verification checks package — exports all check classes.

Usage::

    from verification.checks import ALL_CHECKS

    for check_cls in ALL_CHECKS:
        check = check_cls()
        results = check.run(session, config)
"""

from verification.checks.ec2_checks import NoPublicIPCheck
from verification.checks.privatelink_checks import PrivateLinkStateCheck
from verification.checks.waf_checks import WAFAssociationCheck
from verification.checks.security_group_checks import UnrestrictedSGCheck
from verification.checks.connectivity_checks import ConnectivityCheck

ALL_CHECKS = [
    NoPublicIPCheck,
    PrivateLinkStateCheck,
    WAFAssociationCheck,
    UnrestrictedSGCheck,
    ConnectivityCheck,
]

__all__ = [
    "NoPublicIPCheck",
    "PrivateLinkStateCheck",
    "WAFAssociationCheck",
    "UnrestrictedSGCheck",
    "ConnectivityCheck",
    "ALL_CHECKS",
]
