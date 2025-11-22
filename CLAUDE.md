# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Opengrep is a fork of Semgrep under the LGPL 2.1 license - a fast static analysis tool for searching code patterns with semantic grep capabilities. It supports 30+ programming languages and performs pattern matching at the AST level while leveraging semantic information (types, control flow, taint analysis).

The project consists of two main components:
- **OCaml core** (`src/`) - The pattern matching engine (`opengrep-core`) and CLI (`opengrep-cli`)
- **Python wrapper** (`cli/`) - Higher-level CLI interface that orchestrates the core binary

## Build Commands

### Initial Setup
```bash
git submodule update --init --recursive
make setup        # Install dependencies (run infrequently)
make              # Build everything
```

### Development Build
```bash
make core                    # Build OCaml core binaries
make copy-core-for-cli       # Copy core binary to Python CLI
cd cli && pipenv shell       # Enter Python environment
opengrep --help              # Test local installation
```

Or use the convenience function:
```bash
# Add to ~/.bashrc for quick testing without installation
opengrep-dev() {
  PIPENV_PIPFILE=~/opengrep/cli/Pipfile pipenv run opengrep "$@"
}
```

### Building Specific Components
```bash
make minimal-build           # Build only essential binaries (faster)
make build-core-test         # Build test executable without running tests
make core-bc                 # Build bytecode version for ocamldebug
```

### Docker
```bash
make build-docker            # Build semgrep:latest Docker image
```

## Testing

### OCaml Core Tests
```bash
make core-test              # Run all OCaml tests
make build-core-test        # Build test.exe
./test --help               # See testo test options
./test <filter>             # Run specific tests by name/pattern
make retest                 # Re-run only failed tests
```

The test executable (`./test`) uses the testo framework. To approve test output changes, use `./test approve`.

### Python CLI Tests
```bash
cd cli
make test                   # Run all Python tests (includes typecheck)
make test-dev               # Run tests in order: quick → kinda_slow → slow
make ci-test                # CI-compatible tests (no typecheck)
make e2e                    # End-to-end tests only
make osemgrep-e2e           # E2E tests using osemgrep instead of pysemgrep
PYTEST_USE_OSEMGREP=true pytest tests/default/e2e/test_output.py  # Run single test with osemgrep
```

Python tests are marked by speed: `@pytest.mark.quick`, `@pytest.mark.kinda_slow`, or `@pytest.mark.slow`. The `make check-markers` target verifies all tests are properly marked.

### Running Single OCaml Tests
```bash
./test -j0 <test-name>      # Run specific test (e.g., "./test -j0 test_analyzer")
dune runtest src/engine     # Run inline tests in specific directory
```

## Architecture

### High-Level Flow
1. **Rule parsing** (`src/rule/`) - Parse Semgrep YAML rules into internal representation
2. **Target identification** (`src/targeting/`) - Find and filter files to scan
3. **Parsing** (`src/parsing/`, `languages/`) - Parse source code to Generic AST using tree-sitter
4. **Analysis** (`src/analyzing/`) - Build control flow graphs, dataflow analysis, constant propagation
5. **Pattern matching** (`src/matching/`, `src/engine/`) - Match patterns against AST
6. **Reporting** (`src/reporting/`) - Generate findings in various output formats (JSON, SARIF, text)

### Core Components

**Generic AST** (`src/core/`, `libs/ast_generic/`)
- Unified AST representation supporting 30+ languages
- Allows language-agnostic pattern matching and analysis
- Tree-sitter-based parsers in `languages/` convert language-specific ASTs to Generic AST

**Pattern Matching Engine** (`src/matching/`, `src/engine/`)
- `Generic_vs_generic.ml` - Core AST pattern matching (~150KB, heart of the engine)
- `Match_patterns.ml` - High-level pattern matching coordination
- `Match_search_mode.ml` - Standard search pattern matching
- `Match_tainting_mode.ml` - Taint analysis mode
- Supports metavariables ($X, $...ARGS), ellipsis patterns, and equivalences

**Taint Analysis** (`src/tainting/`, `src/engine/Match_tainting_mode.ml`)
- Tracks data flow from sources to sinks
- `--taint-intrafile` enables cross-function intrafile analysis:
  - Builds call graph and sorts functions topologically
  - Extracts function signatures (how taint flows through parameters/returns)
  - Instantiates signatures at call sites for interprocedural analysis
  - See `INTRA_FUNCTION_IMPLEMENTATION.md` for detailed architecture

**Dataflow Analysis** (`src/analyzing/`)
- `Dataflow_core.ml` - Generic fixed-point dataflow framework
- `Dataflow_tainting.ml` - Taint-specific dataflow implementation
- `CFG_build.ml` - Control flow graph construction from IL
- `AST_to_IL.ml` - Convert Generic AST to intermediate language (IL)

**Rule System** (`src/rule/`)
- Parse and validate Semgrep rule YAML files
- Support for `pattern`, `pattern-not`, `pattern-either`, `pattern-inside`, etc.
- Metavariable analysis, regex matching, focus-metavariable

**Python CLI** (`cli/src/semgrep/`)
- Orchestrates `opengrep-core` invocation
- Handles configuration resolution, authentication, metrics
- Output formatting (text, JSON, SARIF, GitLab SAST)
- Git integration for diff-aware scanning

### Testing Architecture
- OCaml tests use **testo** framework (custom in-house tool in `libs/testo/`)
- Python tests use **pytest** with parallel execution (`-n auto`)
- Snapshot testing for CLI output validation
- E2E tests can run with either pysemgrep or osemgrep via `PYTEST_USE_OSEMGREP`

### Build System
- **Dune** for OCaml compilation (version 3.8+)
- OCaml 5.2.1+ required (was 4.14, now updated)
- Tree-sitter runtime built via `libs/ocaml-tree-sitter-core`
- Static linking on macOS requires special flags (`src/main/flags.sh`)
- Python uses pipenv for dependency management

## Development Workflow

### Adding a New Language
1. Add tree-sitter parser in `languages/<lang>/`
2. Create Generic AST converter
3. Add parser to `src/parsing/Parse_target.ml`
4. Add test cases in `tests/rules/<lang>/`

### Running the Pattern Matching Engine
```bash
./bin/opengrep-core -lang python -rules_file rule.yaml target.py
./bin/opengrep-cli scan -f rule.yaml target.py  # OCaml CLI
cd cli && pipenv run opengrep scan -f rule.yaml target.py  # Python CLI
```

### Debugging
```bash
make core-bc                         # Build bytecode version
dune utop                            # OCaml REPL with semgrep libs loaded
make install-semgrep-libs            # Install libs to opam for use in scripts
```

## Common Development Patterns

### Metavariable Convention
- `$X`, `$VAR` - Single expression/identifier
- `$...ARGS` - Zero or more arguments
- `$...BODY` - Sequence of statements
- Metavariables must be uppercase after the `$`

### Opam Package Management
```bash
make install-opam-deps              # Install OCaml dependencies
opam update -y                      # Update package lists
```
The project uses multiple `.opam` files in `opam/` directory, auto-generated from `dune-project`.

### Git Workflow
- Use semi-linear history with merge commits
- Rebase PRs on target branch (usually `main`) before merging
- Clean, informative commit messages
- Mention issue numbers in commits
- All new features require tests

### Performance Testing
```bash
make perf-bench                     # Run full benchmark suite
make perf-matching                  # Run matching performance tests
make report-perf-matching           # Post results to dashboard (CI only)
```

## File Organization

- `src/analyzing/` - Dataflow, CFG, constant propagation, IL conversion
- `src/core/` - Core types (matches, errors, results)
- `src/engine/` - Pattern matching modes (search, taint, join, SCA)
- `src/matching/` - AST pattern matching logic
- `src/parsing/` - Language parsers and Generic AST conversion
- `src/rule/` - Rule parsing and validation
- `src/tainting/` - Taint analysis infrastructure
- `cli/src/semgrep/` - Python CLI implementation
- `languages/` - Tree-sitter parsers for each language
- `libs/` - Vendored libraries (commons, tree-sitter-core, spacegrep, etc.)
- `tests/` - OCaml test suites
- `cli/tests/` - Python test suites

## Key External Dependencies

- **tree-sitter** - Parsing infrastructure
- **dune** - OCaml build system
- **menhir** - Parser generator (pinned to version 20230608)
- **pcre/pcre2** - Regular expressions
- **lwt** - Concurrency for OCaml
- **cmdliner** - CLI argument parsing
- **yojson** - JSON handling
- **atdgen** - Type-safe JSON/serialization
