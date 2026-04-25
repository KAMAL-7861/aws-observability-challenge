"""Base check interface and result dataclass for the verification tool.

All security and connectivity checks inherit from BaseCheck and return
CheckResult instances.
"""

from abc import ABC, abstractmethod
from dataclasses import dataclass
from typing import Optional

import boto3


@dataclass
class CheckResult:
    """Result of a single verification check.

    Attributes:
        check_name: Machine-readable identifier for the check.
        passed: True if the check passed, False if a violation was found.
        resource_id: AWS resource identifier relevant to the result.
            Must be non-null when ``passed`` is False.
        details: Human-readable description of what was found.
        remediation: Suggested fix. Must be non-null when ``passed`` is False.
    """

    check_name: str
    passed: bool
    resource_id: Optional[str]
    details: str
    remediation: Optional[str]


class BaseCheck(ABC):
    """Abstract base class for all verification checks."""

    @property
    @abstractmethod
    def name(self) -> str:
        """Machine-readable check name."""
        ...

    @property
    @abstractmethod
    def description(self) -> str:
        """Human-readable description of what this check validates."""
        ...

    @abstractmethod
    def run(self, session: boto3.Session, config: dict) -> list[CheckResult]:
        """Execute the check and return one or more results.

        Args:
            session: A configured boto3 Session for AWS API calls.
            config: Dictionary containing runtime configuration such as
                cluster names, regions, and resource identifiers.

        Returns:
            A list of CheckResult instances (one per evaluated resource).
        """
        ...
