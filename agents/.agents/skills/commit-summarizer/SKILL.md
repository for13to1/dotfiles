---
name: commit-summarizer
description: Generates a clear and concise git commit message based on the currently staged changes. Use this skill when the user asks to summarize staged changes, write a commit message, or review what is about to be committed.
---

# Commit Summarizer

Generate high-quality commit messages by analyzing staged git changes.

## Workflow

1. **Environmental Check**: Confirm the current directory is a git repository.
   - If not, inform the user and stop.

2. **Status Check**: Run `git status` to check for staged changes.
   - **If staged changes exist**: Proceed to Step 3.
   - **If NO staged changes exist**:
     - Check for unstaged changes. If they exist, suggest the user `git add` them first, then offer to help.
     - If the working tree is clean, inform the user there's nothing to commit.

3. **Review Diff**: Run `git diff --staged` (or use `--staged --stat` if the diff is massive) to understand the logical changes.

4. **Analyze Intent**: Determine if the change adds **New Logic** (feat/init) or merely changes **Structure** (refactor).
   - Note: New files alongside deletions often signify code extraction (refactor).

5. **Generate**: Use Conventional Commits format.

   > [!IMPORTANT]
   > - **Status-Logic Alignment.** The message MUST reflect physical facts in `git status` but summarized via **Logical Groups**. Do NOT list files individually if they belong to a single structural change.
   > - **Hierarchy & Essence.** The subject MUST capture the *Primary Intent*. Use bullet points to describe what *Logical Components* were created/modified, focusing on their collective purpose.
   > - **Component over Logic.** Describe what the added/changed units *are* in the project's architecture, not how they work internally.
   > - **Context for IDs only.** Use dialogue context ONLY for task IDs (#123). Ignore the conversation's iteration process.
   > - **Strict Ban on Paths.** Do NOT use physical file names or paths as bullet point headers.
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

6. **Present**: Provide the message in a code block and offer to run `git commit`.
