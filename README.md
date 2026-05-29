# EvalForge

EvalForge is a Rails dashboard for versioning prompts, running structured evaluations, reviewing model outputs, and comparing prompt performance over time.

## Stack

- Ruby `3.4.9`
- Rails `8`
- PostgreSQL
- Hotwire / Turbo
- Tailwind CSS
- Solid Queue

## Setup

1. Install Ruby `3.4.9` and PostgreSQL.
2. Install gems:
   ```powershell
   bundle install
   ```
3. Configure secrets:
   - Rails credentials or environment variables for your app secrets
   - `OPENROUTER_API_KEY` for real non-manual model runs
4. Prepare the database:
   ```powershell
   bin\rails db:prepare
   ```
5. Start the app:
   ```powershell
   bin\dev
   ```

## Model execution

- `manual` runs stay fully local and generate review templates immediately.
- `gpt-4o` and `claude-3-5-sonnet` are routed through OpenRouter behind the scenes.
- If `OPENROUTER_API_KEY` is missing, EvalForge falls back to mocked responses so the evaluation workflow still works for development.

## Tests

Run the focused test suite with:

```powershell
bundle exec ruby -Itest test\services\llm_provider_service_test.rb
bundle exec ruby -Itest test\integration\evaluation_runs_security_test.rb
bundle exec ruby -Itest test\models\evaluation_run_test.rb
bundle exec ruby -Itest test\models\model_response_test.rb
bundle exec brakeman -q
```
