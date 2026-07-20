---
name: commit-summarizer
description: Generates a clear and concise git commit message based on currently staged changes. Use when the user says "commit this", "write a commit message", "summarize changes", "帮我写 commit", "提交代码", "generate commit message", or when reviewing staged changes before committing. Also use when the user asks "what changed?" or "review my staged changes".
---

# Commit Summarizer

Generate high-quality Conventional Commits messages by analyzing staged git changes.

## Architecture: Hybrid Mode

| Step | Owner | Tasks |
|------|-------|-------|
| 1. Stage analysis | **Script** | `analyze_staged.py` produces structured JSON: file stats, logical groupings, change-type inference, context detection |
| 2. Message composition | **LLM** | Reads structured data, writes the commit message with proper Conventional Commits format |

## Gotchas

These are known pitfalls. Read before composing the message.

- **Large diffs**: If `analyze_staged.py` reports `is_large_diff: true`, use the script's structured output (file list + stats) as the primary source. Do NOT paste the full `git diff` into context — it may exceed token limits.
- **Binary files**: If `binary_files` appears in warnings, mention them in the commit body but do not attempt to describe their content.
- **Merge commits**: If `is_merge` is true, the commit message should note it's a merge (e.g. `merge: ...` or `chore: merge ...`). Do not try to summarize all merged changes individually.
- **Many unrelated changes**: If the script reports `many_unrelated_changes: true`, consider suggesting the user split the commit into smaller logical units.
- **Renames masquerading as add+delete**: Heavy refactors often show as new files + deleted files. The script flags this; describe it as a refactor/move, not as "added X, deleted Y".
- **commitlint**: If `context.commitlint` is true, the generated message MUST conform to the project's commitlint rules. Check for `commitlint_config` in the output.
- **Scope inference**: Do not invent scopes. If the changes span multiple unrelated modules, omit the scope. If changes are concentrated in one directory/module, use that as scope.
- **Subject line length**: Keep the subject ≤ 72 characters. If it's longer, shorten it and move details to the body.

## Workflow

1. **Environmental Check**: Confirm the current directory is a git repository.
   - If not, inform the user and stop.

2. **Status Check**: Run `git status` to check for staged changes.
   - **If staged changes exist**: Proceed to Step 3.
   - **If NO staged changes exist**:
     - Check for unstaged changes. If they exist, suggest the user `git add` them first, then offer to help.
     - If the working tree is clean, inform the user there's nothing to commit.

3. **Analyze**: Run the analysis script to get structured data:
   ```bash
   uv run python3 $HOME/.agents/skills/commit-summarizer/scripts/analyze_staged.py
   ```
   This outputs JSON with file stats, logical groupings, change-type inference, and context hints.

4. **Review Diff** (if needed): For small diffs (< 200 lines changed), optionally run `git diff --staged` for full context. For large diffs, rely on the script's structured output.

5. **Analyze Intent**: Using the script's `change_type_inference.primary_type` as a starting point, determine if the change:
   - Adds **New Logic** (`feat`) — new files, new functionality
   - Fixes **Bugs** (`fix`) — bug fixes, error corrections
   - Changes **Structure** (`refactor`) — reorganization, extraction, renaming
   - Affects **Docs/Config/Tests only** — use `docs`, `chore`, `test` types
   - Note: New files alongside deletions often signify code extraction (refactor).

6. **Generate**: Use Conventional Commits format.

   > [!IMPORTANT]
   > - **Status-Logic Alignment.** The message MUST reflect physical facts in `git status` but summarized via **Logical Groups**. Do NOT list files individually if they belong to a single structural change.
   > - **Hierarchy & Essence.** The subject MUST capture the *Primary Intent*. Use bullet points to describe what *Logical Components* were created/modified, focusing on their collective purpose.
   > - **Component over Logic.** Describe what the added/changed units *are* in the project's architecture, not how they work internally.
   > - **Context for IDs only.** Use dialogue context ONLY for task IDs (#123). Ignore the conversation's iteration process.
   > - **Prefer Logical Names.** Use component/module names as bullet headers. Project-relative paths are acceptable when no better logical name exists (e.g., monorepo `packages/auth/` changes where the directory IS the component). **Never** use absolute paths (e.g., `/Users/...` or `/home/...`).
   > - **Clean List.** Start the list directly with dashed items (`-`).

   **Standard Format:**

   ```text
   <type>(<optional scope>): <subject_in_imperative_mood>

   <optional structured body:
   - Point 1
   - Point 2>
   ```

   **Common Types:**
   `feat` (new feature), `fix` (bug fix), `refactor` (code improvement), `docs` (documentation), `style` (formatting), `perf` (performance), `test` (testing), `chore` (maintenance).

7. **Present**: Provide the message in a code block and offer to run `git commit`.

## Context Awareness

Before generating, check for project-specific conventions:
- Look for `.gitmessage` template (via `git config --get commit.template`)
- Check for `commitlint` config in the project
- Read `package.json` / `Cargo.toml` / `pyproject.toml` to infer project type and language
- Adapt scope names to match the project's module/directory structure
