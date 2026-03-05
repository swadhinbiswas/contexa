//! # cortexa-gcc
//!
//! Git-inspired context management for LLM agents. COMMIT, BRANCH, MERGE, and
//! CONTEXT operations over a persistent versioned memory workspace.
//!
//! Paper: *"Git Context Controller: Manage the Context of LLM-based Agents like Git"*
//! arXiv:2508.00031 — Junde Wu et al., 2025
//!
//! ## File System Layout
//! ```text
//! .GCC/
//! ├── main.md                 # Global roadmap / planning artifact
//! └── branches/
//!     ├── main/
//!     │   ├── log.md          # Continuous OTA trace (Observation-Thought-Action)
//!     │   ├── commit.md       # Milestone-level commit summaries
//!     │   └── metadata.yaml   # Branch intent, status, creation info
//!     └── <branch>/
//!         └── ...
//! ```
//!
//! ## Example
//! ```rust,no_run
//! use cortexa_gcc::GCCWorkspace;
//!
//! let mut ws = GCCWorkspace::new("/path/to/project");
//! ws.init("Build a production REST API").unwrap();
//!
//! ws.log_ota("dir is empty", "scaffold first", "create_file(main.rs)").unwrap();
//! ws.commit("Scaffolded project", None, None).unwrap();
//!
//! ws.branch("jwt-auth", "Explore JWT vs session auth").unwrap();
//! ws.commit("JWT middleware implemented", None, None).unwrap();
//! ws.merge("jwt-auth", None, "main").unwrap();
//!
//! let ctx = ws.context(None, 1).unwrap();
//! println!("{}", ctx.summary());
//! ```

pub mod error;
pub mod models;
pub mod workspace;

pub use models::{BranchMetadata, CommitRecord, ContextResult, OTARecord};
pub use workspace::GCCWorkspace;
