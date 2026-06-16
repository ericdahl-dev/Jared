# Issue tracker: GitHub

Issues and PRDs for this repo live as GitHub issues on `ericdahl-dev/Jared`. Use the `gh` CLI for all operations.

## Conventions

- **Create an issue**: `gh issue create --repo ericdahl-dev/Jared --title "..." --body "..."`. Use a heredoc for multi-line bodies.
- **Read an issue**: `gh issue view <number> --repo ericdahl-dev/Jared --comments`, filtering comments by `jq` and also fetching labels.
- **List issues**: `gh issue list --repo ericdahl-dev/Jared --state open --json number,title,body,labels,comments --jq '[.[] | {number, title, body, labels: [.labels[].name], comments: [.comments[].body]}]'` with appropriate `--label` and `--state` filters.
- **Comment on an issue**: `gh issue comment <number> --repo ericdahl-dev/Jared --body "..."`
- **Apply / remove labels**: `gh issue edit <number> --repo ericdahl-dev/Jared --add-label "..."` / `--remove-label "..."`
- **Close**: `gh issue close <number> --repo ericdahl-dev/Jared --comment "..."`

When run inside this clone, `gh` infers the repo from `git remote -v`; prefer explicit `--repo ericdahl-dev/Jared` in scripts.

## When a skill says "publish to the issue tracker"

Create a GitHub issue.

## When a skill says "fetch the relevant ticket"

Run `gh issue view <number> --repo ericdahl-dev/Jared --comments`.
