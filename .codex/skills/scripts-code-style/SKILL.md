---
name: scripts-code-style
description: Repository-local code style guidance for writing, editing, or reviewing code under scripts/. Use when Codex creates or modifies Python, R, or notebook-adjacent script code in this repository and should keep code succinct, readable, object-oriented where appropriate, and well commented for future maintenance.
---

# Scripts Code Style

## Core Approach

Write code in `scripts/` for future readers who need to understand the pipeline quickly. Keep implementations concise, direct, and aligned with the surrounding file's style.

Prefer object-oriented structure when a script has reusable state, configuration, staged processing, or a clear domain object such as a scraper, processor, matcher, parser, or model runner. Use plain functions for small stateless transformations or one-off glue code. Do not add classes solely to wrap trivial helpers.

## Code Organization

Keep code blocks and generated snippets short enough to scan. Extract repeated logic into small named functions or methods, but avoid deep abstraction for simple pipeline steps.

For Python, use 4-space indentation, `snake_case` functions and variables, and `PascalCase` classes. For R, use readable object names and keep data pipeline steps grouped by purpose. Prefer explicit file paths rooted in the repository layout, especially `data/raw/`, `data/processed/`, and `outputs/`.

## Commenting

If a file contains one main functionality, add a short module-level comment or docstring describing what the file does and what it reads or writes.

If a file contains multiple functionalities, add a brief comment before each major functionality section, such as scraping, matching, aggregation, modeling, or output writing.

Do not write comments for very simple helper functions when the name and code are already self-explanatory. Use comments to explain intent, data assumptions, or non-obvious workflow choices.

## Review Before Finishing

Before completing code changes, check that the script is easier to follow than before, names reflect domain concepts, comments describe meaningful functionality, and the implementation avoids unnecessary helper commentary or boilerplate.
