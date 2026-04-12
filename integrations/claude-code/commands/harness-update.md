# /harness-update — Update harness for current project

Update the existing harness after project changes.

## Instructions

1. Run rediscovery:
```bash
~/.harness-toolkit/bin/harness discover
```

2. Check if project context has changed:
```bash
~/.harness-toolkit/bin/harness classify
```

3. If the context hash changed or --force was specified:
   - Read the generated prompts from `.claude/harness/.prompts/`
   - Process each prompt and save output to the corresponding rule file
   - Run write and validate steps

4. If unchanged:
   - Report "Project unchanged" and run validate only

## Important

- Backup is created automatically before writing
- Zone B state files (progress.md, learnings.md) are NEVER overwritten
- User content outside HARNESS markers in CLAUDE.md is preserved
