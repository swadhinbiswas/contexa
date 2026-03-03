"""
GCC(Git-Context-Controller) Data Models Code by @swadhinbiswas

Based on: arXiv:2508.00031v2 - "Git Context Controller: Manage the Context of
LLM-based Agents like Git" by Junde Wu et al.

The paper defines agent memory as a versioned, hierarchical file system with
four core commands: COMMIT, BRANCH, MERGE, and CONTEXT.

"""

from dataclasses import dataclass, field
from datetime import datetime
from typing import Dict, Optional
import yaml


@dataclass
class OTARecord:
    """
    Observation-Thought-Action record (OTA cycle).
    The paper logs continuous OTA cycles in log.md for each branch.
    """

    timestamp: str
    observation: str
    thought: str
    action: str
    step: int

    def to_markdown(self) -> str:
        return (
            f"### Step {self.step}-{self.timestamp}\n"
            f"**Observation:** {self.observation}\n\n"
            f"**Thought:** {self.thought}\n\n"
            f"**Action:** {self.action}\n\n"
            "--------\n"
        )

    @staticmethod
    def from_dict(d: Dict) -> "OTARecord":
        return OTARecord(
            timestamp=d["timestamp"],
            observation=d["observation"],
            thought=d["thought"],
            action=d["action"],
            step=d["step"],
        )


@dataclass
class CommitRecord:
    commit_id: str
    branch_name: str
    branch_purpose: str
    previous_progress_summary: str
    this_commit_contribution: str
    timestamp: str

    def to_markdown(self) -> str:
        return (
            f"## Commit `{self.commit_id}`\n"
            f"**Timestamp:** {self.timestamp}\n\n"
            f"**Branch Purpose:** {self.branch_purpose}\n\n"
            f"**Previous Progress Summary:** {self.previous_progress_summary}\n\n"
            f"**This Commit's Contribution:** {self.this_commit_contribution}\n\n"
            "---\n"
        )


@dataclass
class BranchMetadata:
    """
    Structured metadata stored in metadata.yaml per branch.
    Records architectural intent and motivation (per paper S3.1).
    """

    name: str
    purpose: str
    created_from: str
    created_at: str
    status: str = "active"
    merged_into: Optional[str] = None
    merged_at: Optional[str] = None

    def to_yaml(self) -> str:
        d = {
            "name": self.name,
            "purpose": self.purpose,
            "created_from": self.created_from,
            "created_at": self.created_at,
            "status": self.status,
            "merged_into": self.merged_into,
            "merged_at": self.merged_at,
        }
        return yaml.dump(d, default_flow_style=False)

    @staticmethod
    def from_yaml(text: str) -> "BranchMetadata":
        d = yaml.safe_load(text)
        return BranchMetadata(
            name=d["name"],
            purpose=d["purpose"],
            created_from=d["created_from"],
            created_at=d["created_at"],
            status=d.get("status", "active"),
            merged_into=d.get("merged_into"),
            merged_at=d.get("merged_at"),
        )


@dataclass
class ContextResult:
    """
    Result returned by the CONTEXT command.
    The paper specifies hierarchical retrieval at varying resolutions
    (K = number of recent commit records to reveal; default K=1).
    """

    branch_name: str
    k: int
    commits: list[CommitRecord] = field(default_factory=list)
    ota_records: list[OTARecord] = field(default_factory=list)
    main_roadmap: str = ""
    metadata: Optional[BranchMetadata] = None

    def summary(self) -> str:
        lines = [f"# CONTEXT — branch `{self.branch_name}` (K={self.k})\n"]
        lines.append("## Global Roadmap\n" + self.main_roadmap + "\n")
        lines.append(f"## Last {self.k} Commit(s)\n")
        for c in self.commits:
            lines.append(c.to_markdown())
        if self.ota_records:
            lines.append(f"## Recent OTA steps ({len(self.ota_records)} total)\n")
            for rec in self.ota_records[-5:]:
                lines.append(rec.to_markdown())
        return "\n".join(lines)
