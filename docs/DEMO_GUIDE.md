# EvalForge Demo Guide

This is the fastest way to show EvalForge to another engineer, recruiter, or teammate.

## Recommended setup

1. Run `bin\rails db:seed`
2. Sign in with:
   - `demo@evalforge.com`
   - `password`

## Demo story

Use these two projects:

- `Humanize Benchmark`
  Shows prompt iteration, comparison data, and sanitized public reporting.

- `Customer Support Escalation QA`
  Shows project-level model configuration, pending review claims, and review history.

## Suggested click path

1. Open the projects index and point out the product positioning:
   versioned prompts, test cases, rubrics, runs, exports, and review workflows in one app.

2. Enter `Humanize Benchmark`:
   - show prompt versions
   - show rubric criteria
   - open the comparison dashboard
   - open a run and show run analytics plus the public summary controls

3. Open the public report:
   - explain that it is tokenized
   - highlight that it shares metrics and sanitized failure samples only

4. Enter `Customer Support Escalation QA`:
   - show project-level enabled/default models
   - open the review queue
   - point out the claimed response
   - open the edited review and show the audit history

5. Mention exports:
   - test cases
   - model responses
   - scores
   - run summary

## Strong talking points

- The app treats prompt iteration as a product workflow, not just a text field.
- Evaluation runs are tied to specific prompt versions and datasets.
- Reviews are auditable and can be claimed to avoid reviewer collisions.
- Public reports are useful for demos without leaking private prompt or output data.
- The repo demonstrates Rails modeling, background jobs, data exports, and human-in-the-loop evaluation design.
