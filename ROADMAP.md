# EvalForge Roadmap

This roadmap is ordered for two goals:

- make the app more useful as a real prompt evaluation tool
- make the repo stronger as a portfolio-quality Rails product

The sequence assumes the current baseline already exists:

- project / prompt / prompt version / test case / rubric CRUD
- manual and OpenRouter-backed runs
- review queue and scoring
- comparison dashboard
- CSV exports
- sanitized public reports
- project reference file uploads

## Phase 1: Stabilize The Rails Runtime

Goal: get the local and deployable runtime into a fully working, repeatable state.

Why first:
- this blocks reliable testing and future iteration
- the current Ruby `3.4.9` setup still needs a clean native gem toolchain

Deliverables:
- finish RubyInstaller `ridk` / MSYS2 setup on Windows
- run `bundle install` successfully under Ruby `3.4.9`
- run migrations cleanly, including Active Storage
- run the focused test suite and `brakeman`
- confirm `bin\dev` and background jobs boot without local setup surprises

Success criteria:
- a fresh machine can follow the repo docs and boot the app
- all current tests pass
- no unresolved environment-specific blockers remain

## Phase 2: Improve Evaluation Operations

Goal: make evaluation runs easier to manage and recover when using real models.

Deliverables:
- retry failed model responses from the run detail page
- rerun an entire evaluation run against the same prompt version and test cases
- add run filters by status, model, and date
- add search for projects, prompts, and runs
- show clearer job-state feedback for running, failed, and partial runs

Why this matters:
- this is the fastest path from “demo app” to “real operations tool”
- users need control over failed jobs and growing run histories

Success criteria:
- a user can recover from failed provider calls without manual database cleanup
- large project histories stay navigable

## Phase 3: Add Dataset Import And Better Inputs

Goal: make it easier to load and maintain realistic evaluation datasets.

Deliverables:
- CSV import for test cases
- validation and error reporting for malformed rows
- downloadable import template
- optional bulk edit / bulk delete tools for test cases
- better structured tagging and filtering for datasets

Why this matters:
- CSV import is one of the highest-signal usability features for this product
- it reduces manual setup friction more than almost any other feature

Success criteria:
- a user can import a benchmark dataset in one pass
- import errors are actionable and row-specific

## Phase 4: Deepen Reporting And Sharing

Goal: make reporting stronger for both internal use and public demos.

Deliverables:
- report token management: regenerate / revoke public report links
- optional report expiry
- PDF export for public reports
- richer internal run analytics:
  - cost by run
  - token usage by run
  - failure trends by criterion
  - model comparison across runs

Why this matters:
- this improves both security posture and portfolio presentation
- it turns existing data into clearer product value

Success criteria:
- public sharing is user-controllable
- stakeholders can consume results without needing app access

## Phase 5: Project-Level Model Configuration

Goal: move from a fixed shortlist toward configurable evaluation infrastructure.

Deliverables:
- project-level provider settings UI
- configurable OpenRouter model choices per project
- default model selection per project
- provider validation and clearer missing-key messaging
- optional per-run overrides from project defaults

Why this matters:
- the app currently supports only a small hardcoded model set
- real usage needs different models for different projects

Success criteria:
- users can configure model behavior without code changes
- the run form stays simple while becoming more flexible

## Phase 6: Team Workflow Features

Goal: make EvalForge usable by more than one reviewer in a structured way.

Deliverables:
- reviewer attribution in the queue and dashboards
- review assignment or claiming
- audit trail for review changes
- project collaborator roles if multi-user support is desired

Why this matters:
- this is what pushes the app from solo-tool utility toward team software

Success criteria:
- multiple reviewers can work without stepping on each other
- review history becomes trustworthy and inspectable

## Phase 7: Portfolio-Grade Polish

Goal: package the app as a stronger showcase project.

Deliverables:
- seed data and screenshots that tell a clearer product story
- tighter onboarding flow for first-time users
- better empty states and guidance text
- deployment validation on the intended host
- short architecture and product docs in-repo

Why this matters:
- strong functionality is necessary, but presentation decides how legible the project feels to other engineers and hiring teams

Success criteria:
- a reviewer can clone, run, understand, and demo the app quickly
- the app feels intentional rather than just feature-complete

## Recommended Immediate Order

If you want the best next sequence from here:

1. Finish Phase 1 completely
2. Build retry / rerun controls from Phase 2
3. Build CSV import from Phase 3
4. Add report revoke / expiry from Phase 4
5. Add project-level model configuration from Phase 5

## Nice-To-Haves After Core Work

- attachment previews for images and PDFs
- saved dashboard filters
- benchmark snapshots over time
- background export generation for large datasets
- rubric templates reusable across projects

## Things To Avoid Too Early

- adding multiple AI providers before project-level model settings exist
- overbuilding collaboration/permissions before single-user workflows are friction-free
- building a React frontend rewrite
- adding complex automation before rerun, retry, and import basics are solid
