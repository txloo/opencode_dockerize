# AGENTS.md — opencode_dockerize

Instructions for agent sessions working on this repo. Read this every session
before editing; it records hard-won project rules so future work stays safe.

## What this project is

Runs the opencode CLI inside a Docker container from a Windows host. Key files:

| File | Role |
| --- | --- |
| `Dockerfile` | Debian-based image: git/curl/openssh-client, opencode binary, entrypoint hook |
| `entrypoint.sh` | Personal runtime script (ssh-agent, key load, GitHub check). **Gitignored** — per-machine; derive from `entrypoint_example.sh` |
| `setup_opencode.ps1` | Windows launcher: sets `.gitignore`/`.dockerignore`, installs the skill, injects `auth.json`, runs `docker run` with XDG env vars |
| `container-env_SKILL.md` | Master template for the `container-env` skill |
| `auth_example.json` | Template only. Real credentials live in `auth.json` (**gitignored**, never committed, never echoed/logged) |
| `userful_commands.md` | Build/exec command snippets (note the typo in the filename; do not rename casually) |

## CRITICAL: `setup_opencode.ps1` must stay pure 7-bit ASCII

- No emojis, no smart quotes, no non-ASCII characters **anywhere** in the file.
- Why: the file is UTF-8 without BOM. Windows PowerShell 5.1 reads a no-BOM
  file as ANSI (Windows-1252). Emoji bytes then decode into smart-quote
  characters (e.g. `💡` = `F0 9F 92 A1` → byte `0x92` → `'`), and PowerShell
  treats smart quotes as string delimiters, producing a hard parse failure:
  `The string is missing the terminator: '.`
- Use ASCII labels instead: `[SETUP]`, `[INFO]`, `[START]`, `[SKIP]`, `[WARN]`.
- After any edit, verify with a byte audit: no byte `>= 0x80` may remain.

## Line-ending policy

- `setup_opencode.ps1` is **CRLF** (Windows-native). Keep it CRLF.
- Everything else in the repo is LF.
- Match the file's existing endings. Prefer byte-safe edits (perl/`-Encoding`-
  aware tools) over naive re-writes that can flip endings.
- This repo has a history of whole-file diffs that are pure CRLF noise. Always
  read diffs with `git diff --ignore-all-space` to see the real changes before
  reporting or committing.

## Secrets

- `entrypoint.sh` (personal SSH identity) and `auth.json` (API keys) are
  `.gitignore`-d. Never remove them from the ignore list, never commit them,
  never print their contents, never put them in a `Dockerfile` layer.
- `entrypoint_example.sh` and `auth_example.json` are the only safe templates.

## Ignore-files contract

- `.gitignore` and `.dockerignore` must each contain `.opencode_data/` (open
  `setup_opencode.ps1` recreates/keeps it on every project run). Do not bypass.
- `.dockerignore` also prevents `.opencode_data/` leaking into image builds.

## The `container-env` skill

- `container-env_SKILL.md` is the master source. It is **not** copied by
  `setup_opencode.ps1` into a running container — `setup_opencode.ps1` copies
  it into the **project** at `.opencode/skills/container-env/SKILL.md`
  ("copy only if missing", so local project edits win).
- If the skill file is renamed or moved, update `setup_opencode.ps1`
  (the `$SkillSrc` / `$SkillDir` block) in the same change.
- Install path for opencode to actually load it: project scope
  `.opencode/skills/container-env/SKILL.md` or global
  `~/.config/opencode/skills/container-env/SKILL.md`. Skills load at session
  start; a running session will not pick up changes until restart.

## Container model & dependency workflow

- Follow `container-env_SKILL.md`: single dev image run via docker compose.
  No separate runtime image unless the project is shipped.
- `Dockerfile` layering: dependencies near the top (build caching), app code
  last.
- The `docker` CLI is NOT available inside this container. Builds/updates are
  **user-triggered on the host** (`docker compose build` / `docker compose up`).
  Never install packages into the live container as the authoritative change —
  record them in the `Dockerfile` and let the user rebuild.

## Useful commands

```bash
docker build -t custom-opencode:latest      # build the base image (repo dir)
docker exec -it <container> bash            # extra shell into a running container
docker compose run --rm dev npm run test:ci # run a one-off test via compose
```

## Known inconsistencies (fix deliberately, don't propagate)

- `userful_commands.md` references `docker compose run --rm dev`, but no
  `docker-compose.yml` exists in this repo yet.
- `setup_opencode.ps1`'s gitignore/dockerignore checks use two different regex
  patterns (`\.opencode_data` vs `\.opencode_data/`) and a silent skip when the
  entry already exists; the "already present" branch has no log message.