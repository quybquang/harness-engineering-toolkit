# /harness-init — Initialize harness for current project

Initialize AI agent harness for this project.

## Instructions

Run the harness initialization pipeline for the current project. This will:

1. **Discover** — Scan the project filesystem to detect stack, infrastructure, and structure
2. **Classify** — Determine the complexity tier (minimal/standard/full/enterprise) and select appropriate patterns
3. **Generate** — Create conventions, risk rules, workflow protocols, and hook scripts
4. **Write** — Write generated content to CLAUDE.md and project files
5. **Validate** — Check everything is properly set up

## Steps

1. First, run the discovery script:
```bash
~/.harness-toolkit/bin/harness discover
```

2. Run classification:
```bash
~/.harness-toolkit/bin/harness classify
```

3. Read the generated prompts from `.claude/harness/.prompts/` and process each one:
   - Read `.claude/harness/.prompts/conventions-prompt.md` → generate conventions → save to `.claude/harness/rules/conventions.md`
   - Read `.claude/harness/.prompts/risk-rules-prompt.md` → generate risk rules → save to `.claude/harness/rules/risk-rules.md`
   - If tier is standard+: Read `.claude/harness/.prompts/workflow-prompt.md` → generate → save to `.claude/harness/rules/workflow.md`
   - If tier is full+: Read `.claude/harness/.prompts/architecture-prompt.md` → generate → save to `.claude/harness/rules/architecture.md`

4. Run the write step:
```bash
~/.harness-toolkit/bin/harness write
```

5. Run validation:
```bash
~/.harness-toolkit/bin/harness validate
```

6. Report results to the user with a summary of what was created.

## Important

- Follow each prompt template exactly — do not add extra content beyond what the template asks for
- Output raw markdown without code fences for each generated file
- Temperature 0 for all generation calls — consistency matters
- If discover or classify fails, stop and report the error
