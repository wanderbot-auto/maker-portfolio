# Repository Guidelines

## Project Structure & Module Organization
This repository is a Swift Package Manager workspace targeting macOS 14+. Source code lives under `Sources/` and is split by layer:

- `Sources/MakerDomain`: core models and rules
- `Sources/MakerApplication`: use cases, queries, repository/service protocols
- `Sources/MakerAdapters`: runtime adapter abstractions and local process adapters
- `Sources/MakerInfrastructure`: SQLite, filesystem scanning, daemon, secrets, composition root
- `Sources/MakerCLI`: `maker` executable
- `Sources/MakerDesktop`: SwiftUI desktop app
- `Sources/MakerSupport`: shared errors and log/event helpers

Tests mirror the modules in `Tests/`. Reference docs and prototypes live in `docs/`.

## Build, Test, and Development Commands
- `swift build`: build all targets.
- `swift test`: run the full test suite.
- `swift build --product maker-desktop`: build only the desktop app.
- `swift run maker help`: run the CLI directly through SwiftPM.
- `./.build/debug/maker doctor --json`: inspect local setup using the built CLI.

Use `maker paths show` when working with local app-support, database, log, or daemon paths.

## Coding Style & Naming Conventions
Follow existing Swift conventions: 4-space indentation, `UpperCamelCase` for types, `lowerCamelCase` for functions/properties, and small focused structs/extensions. Keep layer boundaries strict: do not import infrastructure into domain or application code. Prefer value types and pure helpers where possible. No formatter or linter is configured; match the surrounding style and keep comments minimal and explanatory. When changing `MakerDesktop`, match the existing SwiftUI spacing, typography, and component patterns instead of introducing a second visual language.

## Desktop UI & Design System
`MakerDesktop` uses a restrained workspace-console aesthetic. Treat `WorkspacePalette` as the source of truth: neutral canvas/panel surfaces, slate text, and a small set of accent colors for status and charts. Prefer white cards on a light canvas, 1px soft borders, subtle shadows, and the current radius system: `14` for cards, `12` for inner tiles/panels, `8` for pills, `4` for compact buttons.

Typography is compact and structured: large page titles, uppercase section labels with tracking, and dense `9-13pt` metadata/body text. Reuse existing primitives such as `CardContainer`, `ActionChipButton`, `StatusPill`, `GitSummaryTile`, `DetailMetaPill`, and `EmptyStateCard` before creating new ones.

Charts should feel embedded in the dashboard, not like standalone marketing graphics. Keep them compact, data-dense, and placed inside existing card sections using the same light inset backgrounds already used by summary tiles and empty states.

## Testing Guidelines
Tests use Apple’s `Testing` framework (`import Testing`, `@Test`, `#expect`). Name test files by module and behavior, for example `RuntimeAndEnvUseCaseTests.swift`. Prefer targeted doubles/stubs inside the test file when the dependency is local to one behavior. Run `swift test` before opening a PR; for scoped work, run the relevant target with `swift test --filter <name>`.

## Commit & Pull Request Guidelines
Recent history mixes short summaries (`update by codex`) and imperative subjects (`Add CLI JSON contracts and milestone management`). Prefer clear imperative commit messages: `Add git activity pulse to desktop detail view`. Keep the subject to one change. PRs should include:

- a short problem/solution summary
- affected modules or commands
- test/build results
- screenshots for `MakerDesktop` UI changes

When working as an agent, create a `git commit` after each self-contained milestone before continuing to the next phase. Treat a milestone as work that leaves the repository in a runnable, reviewable, or otherwise coherent state. Use a clear imperative commit message, avoid amending earlier commits unless explicitly requested, and do not sweep unrelated user changes into the commit. If the worktree contains unrelated modifications that make an isolated commit unsafe, stop and ask before proceeding. Run relevant tests before committing when feasible, and report when testing could not be completed.

## Security & Configuration Tips
Do not commit local app data, tokens, database files, or secrets. Use `MAKER_APP_SUPPORT_DIR` and `MAKER_LAUNCH_AGENTS_DIR` to isolate local development or tests when needed.
