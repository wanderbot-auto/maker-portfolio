# Maker Portfolio Roadmap

## Goal

Build a macOS-first local development control core in Swift. The near-term goal is a stable backend architecture for project metadata management, runtime orchestration, local persistence, and future desktop integration.

## Principles

- Swift-only implementation across core modules and future desktop shell
- Domain and application layers remain independent from system APIs
- Runtime execution flows through adapter abstractions
- Sensitive configuration is isolated from general persistence
- Start with a CLI/debuggable core before attaching a desktop UI

## Phase 0: Core Foundation

- Define package boundaries and dependency rules
- Establish domain entities and application protocols
- Add compile-ready test targets
- Document architecture and implementation conventions

## Phase 1: Persistence and Configuration

- Add SQLite-backed repositories for projects, runtime profiles, sessions, milestones, and notes
- Add migrations and app path management
- Add encrypted secrets storage abstraction with a replaceable key provider
- Add project scanning for local directory metadata

## Phase 2: Runtime Execution

- Implement local process runtime adapter
- Support start, stop, restart, status checks, and log streaming
- Persist run session lifecycle and recent history
- Introduce health-check abstractions for future runtime expansion

## Phase 3: CLI and Integration Harness

- Expose core use cases via a lightweight CLI
- Add commands for listing projects, scanning paths, and inspecting architecture wiring
- Add fixtures and integration tests for local runtime orchestration

## Phase 4: macOS Desktop Shell

- Create a SwiftUI app shell that depends on the core package
- Add composition root, view models, and event subscriptions
- Keep UI thin and route all state changes through application use cases

## Deferred

- Team collaboration and remote sync
- External service integrations
- Device simulator and VM controls
- Multi-profile coordinated startup
