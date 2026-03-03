"""
GCC Workspace — core file-system layer.
Based on arXiv:2508.00031v2.

The paper specifies a .GCC/ root directory containing:
  main.md              — global roadmap / planning artifact
  branches/
    <branch_name>/
      log.md           — continuous OTA (Observation-Thought-Action) trace
      commit.md        — milestone-level commit summaries
      metadata.yaml    — branch intent, status, creation info

All four commands (COMMIT, BRANCH, MERGE, CONTEXT) operate on this structure.
"""

import os
import uuid
from datetime import datetime, timezone
from pathlib import Path
from typing import Optional

from .models import (
    BranchMetadata,
    CommitRecord,
    ContextResult,
    OTARecord,
)


MAIN_BRANCH = "main"
GCC_DIR = ".GCC"


def _now() -> str:
    return datetime.now(timezone.utc).isoformat()


def _short_id() -> str:
    return str(uuid.uuid4())[:8]


class GCCWorkspace:
    """
    Manages the .GCC/ directory structure for one agent project.

    Usage
    -----
    ws = GCCWorkspace("/path/to/project")
    ws.init("Build a REST API service")

    # agent logs OTA steps
    ws.log_ota("file list returned", "need to read main.py", "read_file main.py")

    # agent commits a milestone
    ws.commit("Implement GET /users endpoint")

    # agent branches to explore alternative
    ws.branch("auth-jwt", "Explore JWT-based auth vs session auth")

    # agent merges branch back
    ws.merge("auth-jwt")

    # retrieve context (K=1 by default, per paper experiments)
    ctx = ws.context(k=1)
    print(ctx.summary())
    """

    def __init__(self, project_root: str):
        self.root = Path(project_root)
        self.gcc_dir = self.root / GCC_DIR
        self._current_branch: str = MAIN_BRANCH

    def _branch_dir(self, branch: str) -> Path:
        return self.gcc_dir / "branches" / branch

    def _log_path(self, branch: str) -> Path:
        return self._branch_dir(branch) / "log.md"

    def _commit_path(self, branch: str) -> Path:
        return self._branch_dir(branch) / "commit.md"

    def _meta_path(self, branch: str) -> Path:
        return self._branch_dir(branch) / "metadata.yaml"

    def _main_md(self) -> Path:
        return self.gcc_dir / "main.md"

    def _read(self, path: Path) -> str:
        if path.exists():
            return path.read_text(encoding="utf-8")
        return ""

    def _append(self, path: Path, text: str) -> None:
        with open(path, "a", encoding="utf-8") as f:
            f.write(text)

    def _write(self, path: Path, text: str) -> None:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text, encoding="utf-8")

    def _read_commits(self, branch: str) -> list[CommitRecord]:
        """Parse commit.md into a list of CommitRecord objects."""
        text = self._read(self._commit_path(branch))
        records: list[CommitRecord] = []
        if not text:
            return records
        for block in text.split("---\n"):
            block = block.strip()
            if not block:
                continue
            lines = block.splitlines()
            commit_id = branch_purpose = prev_summary = contribution = ts = ""
            for line in lines:
                if line.startswith("## Commit"):
                    commit_id = line.split("`")[1] if "`" in line else ""
                elif line.startswith("**Timestamp:**"):
                    ts = line.split("**Timestamp:**")[-1].strip()
                elif line.startswith("**Branch Purpose:**"):
                    branch_purpose = line.split("**Branch Purpose:**")[-1].strip()
                elif line.startswith("**Previous Progress Summary:**"):
                    prev_summary = line.split("**Previous Progress Summary:**")[
                        -1
                    ].strip()
                elif line.startswith("**This Commit's Contribution:**"):
                    contribution = line.split("**This Commit's Contribution:**")[
                        -1
                    ].strip()

            if commit_id:
                records.append(
                    CommitRecord(
                        commit_id=commit_id,
                        branch_name=branch,
                        branch_purpose=branch_purpose,
                        previous_progress_summary=prev_summary,
                        this_commit_contribution=contribution,
                        timestamp=ts,
                    )
                )

        return records

    def _read_ota(self, branch: str) -> list[OTARecord]:
        text = self._read(self._log_path(branch))
        records: list[OTARecord] = []
        if not text:
            return records
        for block in text.split("--------\n"):
            block = block.strip()
            if not block:
                continue
            lines = block.splitlines()
            step = 0
            ts = obs = thought = action = ""
            for line in lines:
                if line.startswith("### Step"):
                    header = line.replace("### Step", "").strip()
                    parts = header.split("-", 1)
                    try:
                        step = int(parts[0].strip())
                    except ValueError:
                        step = 0
                    ts = parts[1].strip() if len(parts) > 1 else ""
                elif line.startswith("**Observation:**"):
                    obs = line.split("**Observation:**")[-1].strip()
                elif line.startswith("**Thought:**"):
                    thought = line.split("**Thought:**")[-1].strip()
                elif line.startswith("**Action:**"):
                    action = line.split("**Action:**")[-1].strip()
            if obs or thought or action:
                records.append(OTARecord(ts, obs, thought, action, step))

        return records

    def init(self, project_roadmap: str = "") -> None:
        """
        Initialise a new GCC workspace. Creates .GCC/ structure with a
        'main' branch, main.md roadmap, and initial metadata.
        """
        if self.gcc_dir.exists():
            raise FileExistsError(f"GCC workspace already exists at {self.gcc_dir}")
        main_branch_dir = self._branch_dir(MAIN_BRANCH)
        main_branch_dir.mkdir(parents=True)
        roadmap_content = (
            f"# Project Roadmap\n\n**Initialized:** {_now()}\n\n{project_roadmap}\n"
        )
        self._write(self._main_md(), roadmap_content)
        self._write(
            self._log_path(MAIN_BRANCH), f"# OTA Log — branch `{MAIN_BRANCH}`\n\n"
        )
        self._write(
            self._commit_path(MAIN_BRANCH),
            f"# Commit History — branch `{MAIN_BRANCH}`\n\n",
        )

        meta = BranchMetadata(
            name=MAIN_BRANCH,
            purpose="Primary reasoning trajectory",
            created_from="",
            created_at=_now(),
            status="active",
        )
        self._write(self._meta_path(MAIN_BRANCH), meta.to_yaml())

        self._current_branch = MAIN_BRANCH

    def load(self) -> None:
        """Load an existing GCC workspace (no-op if already in memory)."""
        if not self.gcc_dir.exists():
            raise FileNotFoundError(f"No GCC workspace found at {self.gcc_dir}")
        # Determine current branch from active metadata
        self._current_branch = MAIN_BRANCH

    def log_ota(self, observation: str, thought: str, action: str) -> OTARecord:
        """
        Append an OTA step to the current branch's log.md.
        The paper logs continuous OTA cycles: Observation-Thought-Action.
        """
        existing = self._read_ota(self._current_branch)
        step = len(existing) + 1
        record = OTARecord(
            timestamp=_now(),
            observation=observation,
            thought=thought,
            action=action,
            step=step,
        )
        self._append(self._log_path(self._current_branch), record.to_markdown())
        return record

    def commit(
        self,
        contribution: str,
        previous_summary: Optional[str] = None,
        update_roadmap: Optional[str] = None,
    ) -> CommitRecord:
        """
        COMMIT command (paper S3.2).

        Persists a milestone checkpoint to commit.md. Fields per paper:
          - Branch Purpose (from metadata)
          - Previous Progress Summary
          - This Commit's Contribution

        Optionally updates main.md global roadmap.
        """
        meta_text = self._read(self._meta_path(self._current_branch))
        meta = BranchMetadata.from_yaml(meta_text) if meta_text else None
        branch_purpose = meta.purpose if meta else ""

        # Auto-summarise previous progress from last commit if not provided
        if previous_summary is None:
            commits = self._read_commits(self._current_branch)
            if commits:
                previous_summary = commits[-1].this_commit_contribution
            else:
                previous_summary = "Initial state — no prior commits."

        record = CommitRecord(
            commit_id=_short_id(),
            branch_name=self._current_branch,
            branch_purpose=branch_purpose,
            previous_progress_summary=previous_summary,
            this_commit_contribution=contribution,
            timestamp=_now(),
        )
        self._append(self._commit_path(self._current_branch), record.to_markdown())

        # Optionally update the global roadmap in main.md
        if update_roadmap:
            self._append(
                self._main_md(),
                f"\n## Update ({record.timestamp})\n{update_roadmap}\n",
            )

        return record

    def branch(self, name: str, purpose: str) -> "GCCWorkspace":
        """
        BRANCH command (paper S3.3).

        Creates an isolated workspace for alternative plans or experimental
        reasoning. Mathematically: B_t^(name) = BRANCH(M_{t-1}).

        Initialises empty OTA trace (log.md) and commit.md for the branch,
        carrying forward the parent's last committed state as starting context.
        """
        branch_dir = self._branch_dir(name)
        if branch_dir.exists():
            raise FileExistsError(f"Branch '{name}' already exists.")

        branch_dir.mkdir(parents=True)

        # Initialise empty OTA log (fresh execution trace)
        self._write(self._log_path(name), f"# OTA Log — branch `{name}`\n\n")
        self._write(self._commit_path(name), f"# Commit History — branch `{name}`\n\n")

        # metadata.yaml records intent and motivation (paper S3.3)
        meta = BranchMetadata(
            name=name,
            purpose=purpose,
            created_from=self._current_branch,
            created_at=_now(),
            status="active",
        )
        self._write(self._meta_path(name), meta.to_yaml())

        # Switch current branch
        self._current_branch = name
        return self

    def merge(
        self,
        branch_name: str,
        summary: Optional[str] = None,
        target: str = MAIN_BRANCH,
    ) -> CommitRecord:
        """
        MERGE command (paper S3.4).

        Integrates a completed branch back into the target (default: main),
        merging summaries and execution traces to produce a unified,
        consistent state. Creates a merge commit on the target branch.
        """
        # Gather branch commits and synthesise
        branch_commits = self._read_commits(branch_name)
        branch_ota = self._read_ota(branch_name)
        meta_text = self._read(self._meta_path(branch_name))
        meta = BranchMetadata.from_yaml(meta_text) if meta_text else None

        if not summary:
            contributions = " | ".join(
                c.this_commit_contribution for c in branch_commits
            )
            summary = f"Merged branch `{branch_name}` ({len(branch_commits)} commits). Contributions: {contributions}"

        # Append branch OTA to target log (merge trace)
        if branch_ota:
            merge_header = f"\n## Merged from `{branch_name}` ({_now()})\n\n"
            self._append(self._log_path(target), merge_header)
            for rec in branch_ota:
                self._append(self._log_path(target), rec.to_markdown())

        # Create merge commit on target
        self._current_branch = target
        merge_commit = self.commit(
            contribution=summary,
            previous_summary=f"Merging branch `{branch_name}` with purpose: {meta.purpose if meta else ''}",
            update_roadmap=f"Merged `{branch_name}`: {summary}",
        )

        # Mark branch as merged in metadata
        if meta:
            meta.status = "merged"
            meta.merged_into = target
            meta.merged_at = _now()
            self._write(self._meta_path(branch_name), meta.to_yaml())

        return merge_commit

    def context(self, branch: Optional[str] = None, k: int = 1) -> ContextResult:
        """
        CONTEXT command (paper S3.5).

        Retrieves historical context at varying resolutions. The paper fixes
        K=1 in experiments (only the most recent commit record is revealed).

        Parameters
        ----------
        branch : branch to retrieve context from (default: current branch)
        k      : number of recent commit records to surface (paper default K=1)
        """
        target = branch or self._current_branch
        commits = self._read_commits(target)
        ota = self._read_ota(target)
        roadmap = self._read(self._main_md())
        meta_text = self._read(self._meta_path(target))
        meta = BranchMetadata.from_yaml(meta_text) if meta_text else None

        return ContextResult(
            branch_name=target,
            k=k,
            commits=commits[-k:] if commits else [],
            ota_records=ota,
            main_roadmap=roadmap,
            metadata=meta,
        )

    @property
    def current_branch(self) -> str:
        return self._current_branch

    def switch_branch(self, name: str) -> None:
        """Switch the active branch without creating a new one."""
        if not self._branch_dir(name).exists():
            raise FileNotFoundError(f"Branch '{name}' does not exist.")
        self._current_branch = name

    def list_branches(self) -> list[str]:
        branches_root = self.gcc_dir / "branches"
        if not branches_root.exists():
            return []
        return [d.name for d in branches_root.iterdir() if d.is_dir()]

    def update_roadmap(self, content: str) -> None:
        """Overwrite or append to main.md global roadmap."""
        self._append(self._main_md(), f"\n{content}\n")
