# Project Documentation Template

Use this structure for new or substantially revised files under `docs/projects/`.

```markdown
# Project Name

## Status

State whether the project is complete, ongoing, exploratory, archived, or blocked. Include the current documentation and code quality state if relevant.

## Research Purpose

Describe the research question, empirical object, and why the project exists.

## Scope And Unit Of Analysis

Define the unit of analysis, cycles/years, offices, firms, committees, people, or markets covered. Note exclusions.

## Upstream Dependencies

| Script or data | Role |
| --- | --- |
| `path/to/script_or_data` | Explain how it feeds this project. |

## Project Scripts

| Script | Role | Inputs | Outputs |
| --- | --- | --- | --- |
| `path/to/script` | What this script does for this project. | Main paths or objects read. | Main paths or objects written. |

## Key Data Inputs

| Data path | Type | Role |
| --- | --- | --- |
| `data/...` | raw/external/processed | Explain how the project uses it. |

## Generated Outputs

| Output path | Type | Role |
| --- | --- | --- |
| `data/processed/...` or `outputs/...` | processed/model/figure/table/log | Explain what it contains and who consumes it. |

## Workflow

1. List the minimum run order from raw/source data to final outputs.
2. Include commands when they are stable and known.
3. Mark manual review gates explicitly.

## Validation

List parse checks, row-count checks, schema checks, regenerated artifact checks, or model/table/figure checks that should be run.

## Assumptions And Manual Decisions

Document hand-coded decisions, exclusions, matching assumptions, ambiguous cases, and known caveats.

## Open Work

List path cleanup, missing validation, unclear scripts, pending manual review, or future modeling work.
```

Adapt headings when needed, but preserve the replication logic: purpose, scope, scripts, data, outputs, workflow, validation, assumptions, and open work.

