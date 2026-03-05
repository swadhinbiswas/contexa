# Contributing to contexa

Thank you for your interest in contributing to **contexa** — git-inspired context management for LLM agents.

This is a polyglot monorepo with implementations in **Python, JavaScript/TypeScript, Rust, Go, Zig, Lua, and Elixir**. Contributions to any language are welcome.

## Table of Contents

- [Code of Conduct](#code-of-conduct)
- [Getting Started](#getting-started)
- [Development Setup](#development-setup)
- [Running Tests](#running-tests)
- [Submitting Changes](#submitting-changes)
- [Code Style](#code-style)
- [Labels](#labels)

## Code of Conduct

This project follows the [Contributor Covenant v2.1](CODE_OF_CONDUCT.md). By participating, you are expected to uphold this code.

## Getting Started

1. Fork the repository: <https://github.com/swadhinbiswas/Cortexa>
2. Clone your fork:
   ```bash
   git clone https://github.com/<your-username>/contexa.git
   cd contexa
   ```
3. Create a feature branch:
   ```bash
   git checkout -b feat/my-change
   ```
4. Make your changes, add tests, and ensure all tests pass.
5. Push and open a pull request against `main`.

## Development Setup

Each language lives in its own top-level directory. You only need to install tooling for the language(s) you are working on.

### Python (`PYTHON/`)

- **Requires**: Python 3.10+ and [uv](https://docs.astral.sh/uv/)
- **Setup**:
  ```bash
  cd PYTHON
  uv sync
  ```

### JavaScript / TypeScript (`JS/`)

- **Requires**: Node.js 18+ and npm
- **Setup**:
  ```bash
  cd JS
  npm install
  ```

### Rust (`RUST/`)

- **Requires**: Rust 1.70+ (stable toolchain)
- **Setup**:
  ```bash
  cd RUST
  cargo build
  ```

### Go (`GO/`)

- **Requires**: Go 1.21+
- **Setup**:
  ```bash
  cd GO
  go mod download
  ```

### Zig (`ZIG/`)

- **Requires**: Zig 0.14.0 (latest stable)
- **Setup**: No package manager needed; `zig build` handles everything.

### Lua (`LUA/`)

- **Requires**: Lua 5.3+ (5.4 recommended)
- **Setup**: No package manager needed for development. [LuaRocks](https://luarocks.org/) is only needed for publishing.

### Elixir (`ELIXIR/`)

- **Requires**: Elixir 1.15+ and Erlang/OTP 26+
- **Setup**:
  ```bash
  cd ELIXIR
  mix deps.get
  ```

## Running Tests

Run the tests for the language(s) you modified before submitting a PR.

| Language   | Command                                        |
|------------|------------------------------------------------|
| Python     | `cd PYTHON && uv run pytest -v`                |
| JavaScript | `cd JS && npm test`                            |
| Rust       | `cd RUST && cargo test`                        |
| Go         | `cd GO && go test ./...`                       |
| Zig        | `cd ZIG && zig build test`                     |
| Lua        | `cd LUA && lua test.lua`                       |
| Elixir     | `cd ELIXIR && mix test`                        |

CI runs all 7 language test suites on every pull request. Your PR must pass all checks before it can be merged.

## Submitting Changes

1. **One concern per PR.** Keep pull requests focused on a single change.
2. **Write tests.** If you add a feature or fix a bug, add or update the relevant tests.
3. **Update docs.** If you change the public API surface, update the language-specific `README.md`.
4. **Fill out the PR template.** Check the affected languages and ensure the checklist is complete.
5. **Keep commits clean.** Use clear, descriptive commit messages. Squash fixup commits before requesting review.

### Branch Naming Convention

- `feat/<description>` — new features
- `fix/<description>` — bug fixes
- `docs/<description>` — documentation changes
- `ci/<description>` — CI/build changes
- `refactor/<description>` — code refactoring

## Code Style

- **Python**: Follow [PEP 8](https://peps.python.org/pep-0008/). The project uses [ruff](https://docs.astral.sh/ruff/) for linting.
- **JavaScript/TypeScript**: Follow the existing style. Build with `tsup`.
- **Rust**: Run `cargo fmt` and `cargo clippy` before committing.
- **Go**: Run `gofmt` and `go vet`.
- **Zig**: Follow the [Zig style guide](https://ziglang.org/documentation/master/#Style-Guide).
- **Lua**: Follow the existing style in `LUA/contexa/`.
- **Elixir**: Run `mix format` before committing.

## Labels

Issues and PRs are categorized with the following labels:

### Language Labels

| Label           | Description                |
|-----------------|----------------------------|
| `lang:python`   | Python implementation      |
| `lang:js`       | JavaScript implementation  |
| `lang:rust`     | Rust implementation        |
| `lang:go`       | Go implementation          |
| `lang:zig`      | Zig implementation         |
| `lang:lua`      | Lua implementation         |
| `lang:elixir`   | Elixir implementation      |

### Type Labels

| Label              | Description                          |
|--------------------|--------------------------------------|
| `bug`              | Something isn't working              |
| `enhancement`      | New feature or request               |
| `documentation`    | Improvements or additions to docs    |
| `good first issue` | Good for newcomers                   |
| `help wanted`      | Extra attention is needed            |
| `ci`               | CI/CD and build system               |
| `question`         | Further information is requested     |

---

If you have questions, feel free to [open a discussion](https://github.com/swadhinbiswas/Cortexa/issues/new?template=question.yml) or reach out to [@swadhinbiswas](https://github.com/swadhinbiswas).
