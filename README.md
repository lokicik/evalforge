# EvalForge

EvalForge is a Rails app for prompt evaluation. It lets you version prompts, run them against curated test cases, score outputs with weighted rubrics, review failures, and compare prompt revisions over time.

The app is built for teams who want something more structured than ad hoc prompt tinkering: each project keeps its prompts, test cases, rubric criteria, runs, exports, and review history in one place.

## What you can do

- Create evaluation projects with their own prompt library, test cases, and rubrics
- Version prompts so you can compare revisions instead of overwriting them
- Launch manual or model-backed evaluation runs against selected test cases
- Review completed outputs and score them against weighted rubric criteria
- Track average score, pass rate, reviewed cases, and failure counts per run
- Compare prompt versions from the same project in a dedicated dashboard
- Export test cases, run summaries, model responses, and score data as CSV
- Upload reference files to a project with Active Storage
- Share a sanitized public summary for a run without exposing prompt text, raw outputs, or reviewer notes

## Core workflow

1. Create a project.
2. Add one or more prompts, each with versioned system and user prompt templates.
3. Add test cases with structured input variables and expected behavior.
4. Define a rubric with weighted criteria.
5. Launch an evaluation run for a specific prompt version and selected test cases.
6. Review model outputs, mark them `passed` or `failed`, and add criterion scores.
7. Use the comparison dashboard and CSV exports to inspect which prompt version is performing better.

## Domain model

- `Project`: the top-level workspace for a single evaluation suite
- `Prompt`: a named prompt family inside a project
- `PromptVersion`: a versioned system prompt + interpolated user prompt template
- `TestCase`: structured inputs, expected behavior, tags, difficulty, and notes
- `Rubric`: a scoring framework for a project
- `RubricCriterion`: a weighted scoring criterion within a rubric
- `EvaluationRun`: a run of one prompt version against selected test cases
- `ModelResponse`: one generated output for one test case in a run
- `Review`: a human decision plus notes and per-criterion scores

## Model execution

EvalForge currently supports three run modes:

- `manual`: creates local draft responses immediately so reviewers can score without calling an external provider
- `gpt-4o`: routed through OpenRouter
- `claude-3-5-sonnet`: routed through OpenRouter

If `OPENROUTER_API_KEY` is not set, non-manual runs fall back to mocked responses. That keeps the review flow usable in local development.

## Public sharing

Each evaluation run has a tokenized public summary page. The public view is intentionally limited to safe, high-level information:

- aggregate metrics
- reviewed case counts
- top failed criteria
- sanitized sample failure metadata

It does not expose private evaluation internals such as prompt bodies, raw test inputs, raw model outputs, or reviewer notes.

## Stack

- Ruby `3.4.9`
- Rails `8.0.5`
- PostgreSQL
- Hotwire (`Turbo` + `Stimulus`)
- Tailwind CSS
- Active Job
- Solid Queue
- Active Storage

## Local development

### Prerequisites

- Ruby `3.4.9`
- PostgreSQL running locally
- Bundler

The checked-in development database config expects:

- host: `localhost`
- port: `5432`
- username: `postgres`
- password: `postgres`

Adjust [`config/database.yml`](/C:/Users/LOKMAN/Desktop/personalProjects/evalforge/config/database.yml) if your local PostgreSQL setup differs.

### Setup

Install dependencies and prepare the database:

```powershell
bundle install
bin\rails db:prepare
```

Or use the setup script:

```powershell
bin\setup
```

### Start the app

```powershell
bin\dev
```

That starts:

- the Rails server
- the Tailwind watcher

Open [http://localhost:3000](http://localhost:3000).

### Background jobs

Evaluation runs enqueue `EvaluateTestCaseJob` jobs for non-manual model execution.

Production is configured to use `Solid Queue`. If you want to run a dedicated worker process locally in a production-like setup, start:

```powershell
bin\jobs
```

## Environment variables

- `OPENROUTER_API_KEY`: enables real OpenRouter-backed non-manual runs
- `EVALFORGE_DATABASE_PASSWORD`: used by the production database config

## Seed data

The repo includes demo seed data with:

- a sample user
- a benchmark project
- multiple prompt versions
- test cases
- rubric criteria
- completed runs with reviews and scores

Load it with:

```powershell
bin\rails db:seed
```

Demo login:

- email: `demo@evalforge.com`
- password: `password`

## Testing

Run the focused tests already present in the repo:

```powershell
bundle exec ruby -Itest test\services\llm_provider_service_test.rb
bundle exec ruby -Itest test\integration\evaluation_runs_security_test.rb
bundle exec ruby -Itest test\integration\project_exports_and_attachments_test.rb
bundle exec ruby -Itest test\models\evaluation_run_test.rb
bundle exec ruby -Itest test\models\model_response_test.rb
bundle exec brakeman -q
```

## Project structure

- [`app/controllers`](/C:/Users/LOKMAN/Desktop/personalProjects/evalforge/app/controllers): project CRUD, runs, exports, attachments, auth, and review flows
- [`app/models`](/C:/Users/LOKMAN/Desktop/personalProjects/evalforge/app/models): evaluation domain models and scoring helpers
- [`app/services/llm_provider_service.rb`](/C:/Users/LOKMAN/Desktop/personalProjects/evalforge/app/services/llm_provider_service.rb): model selection and OpenRouter integration
- [`app/jobs/evaluate_test_case_job.rb`](/C:/Users/LOKMAN/Desktop/personalProjects/evalforge/app/jobs/evaluate_test_case_job.rb): async test-case execution
- [`db/seeds.rb`](/C:/Users/LOKMAN/Desktop/personalProjects/evalforge/db/seeds.rb): demo dataset for local exploration

## Current product shape

The current UI centers on:

- project dashboards for prompts, test cases, rubrics, and evaluation runs
- a cross-project human review queue
- a prompt comparison dashboard
- per-run drill-down pages with scoring and CSV export
- project-level reference file uploads and exports

If you are extending the app, those are the workflows the current codebase is optimized around.
