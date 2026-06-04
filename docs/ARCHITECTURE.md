# EvalForge Architecture

EvalForge is a Rails app built around one core question: "Which prompt version performs better against a known benchmark?"

## Main workflow

1. A `Project` groups a benchmark domain.
2. Each project owns versioned `Prompt` + `PromptVersion` records.
3. `TestCase` records define the benchmark dataset.
4. `Rubric` and `RubricCriterion` records define how outputs are scored.
5. An `EvaluationRun` binds one prompt version to a chosen model and a selected set of test cases.
6. Each test case produces one `ModelResponse`.
7. Humans grade responses through `Review` and `Score` records.
8. Reporting surfaces compare runs, summarize failures, and export data.

## Important boundaries

- Owner scoping:
  All project CRUD flows resolve through `Current.user.projects.find(...)` or equivalent joins.

- Public sharing:
  Public reports are tokenized through `share_token` and intentionally summary-only.

- Model execution:
  Non-manual runs go through `LlmProviderService`, which currently maps curated app labels to OpenRouter models.

- Review workflow:
  Pending responses can be claimed, reviewed, edited later, and audited through `ReviewAuditEvent`.

## Key application layers

- Controllers:
  `ProjectsController`, `EvaluationRunsController`, `ReviewsController`, `ProjectExportsController`, `ProjectAttachmentsController`

- Service:
  `LlmProviderService` owns external model selection and request normalization.

- Job:
  `EvaluateTestCaseJob` performs async response generation for non-manual runs.

- Models with the most product logic:
  `EvaluationRun`, `ModelResponse`, `Project`

## Current product strengths

- Prompt version comparison
- Structured benchmark datasets
- Weighted human scoring
- Sanitized public reporting
- CSV export surfaces
- Project-level model configuration
- Review claims and audit history

## Known local limitation

The repo still has an unresolved local Ruby `3.4.9` runtime issue on this Windows machine, so syntax checks are reliable here but full Rails boot verification is still incomplete until Phase 1 is fully finished.
