"""
gcc-context — Python implementation of Git-Context-Controller (GCC)

Paper: "Git Context Controller: Manage the Context of LLM-based Agents like Git"
       arXiv:2508.00031v2, Junde Wu et al., 2025

GCC structures LLM agent memory as a versioned, hierarchical file system with
four core commands: COMMIT, BRANCH, MERGE, and CONTEXT.
"""

from .workspace import GCCWorkspace
from .models import (
    OTARecord,
    CommitRecord,
    BranchMetadata,
    ContextResult,
)

__version__ = "0.1.1"
__all__ = [
    "GCCWorkspace",
    "OTARecord",
    "CommitRecord",
    "BranchMetadata",
    "ContextResult",
]
