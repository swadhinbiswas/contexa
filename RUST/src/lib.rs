//! # cortexa
//!
//! Git-inspired context management for LLM agents. COMMIT, BRANCH, MERGE, and
//! CONTEXT operations over a persistent versioned memory workspace.
//!
//! ## Example
//! ```rust,no_run
//! use cortexa::GCCWorkspace;
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
