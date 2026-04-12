# /harness-eject — Remove toolkit management

Remove harness-toolkit management from this project and give full ownership to the user.

## Instructions

1. Confirm with the user: "This will remove toolkit markers and metadata. Rule files, hooks, and state files will be kept. Continue?"

2. If confirmed:
```bash
~/.harness-toolkit/bin/harness eject
```

3. Report what was kept and what was removed.

## Important

- This is a one-way operation (though it can be reversed with `harness init --force`)
- All generated content is preserved — only management metadata is removed
- User can still manually maintain the files after ejecting
