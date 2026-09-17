# env-audit-skill — implementation instructions for a new project

This document is a specification you hand to a new project so it can implement
its own `env-audit` skill: a read-only ritual that establishes, once per
session and on demand, exactly what it takes to run, build, and test the
project in the current environment. It also encodes the project's standard
**dev sandbox structure** — a lean session container plus a separate dev
image/container you can start at any time to test without disturbing the base
container.

All project-specific values below are `$PLACEHOLDERS`. Replace them with the
new project's real values when instantiating.

---

## 1. Purpose

Provider of a single, empirical answer to the recurring questions:

- "What is needed to run this project here?"
- "Why won't it start?"
- "Does this environment have X?"
- "What must a toolchain image/container provide?"

The skill's output is a requirement list plus an exact entry-point runbook
(dev / build / test), derived by **probing what exists** — never by reading
Dockerfiles, consuming the base image as a source of truth, or trusting prior
session notes.

## 2. Invocation

The skill is **manual**. It is NOT auto-triggered by request phrasing and has
no trigger-phrase rules. The user calls it explicitly whenever they need to:

- establish a run/build/test environment from scratch,
- re-verify an environment after changes (new device, new container, new deps),
- debug an environment problem ("why won't it start").

When invoked, run the full procedure below from top to bottom and report the
findings + resulting commands. Never run partial probes and guess the rest.

## 3. Core principle (existence-first)

- Every requirement must be answered by an **existence check** plus a
  `--version` call on the thing in question. Never infer installation from a
  Dockerfile or documentation.
- The base image/secondary images are **not sources of truth** for what is
  installed. Requirement discovery happens in the live environment only.
- A decision established today must be **re-derived on each session** — verify
  the probes, then re-verify the record; never copy the record forward blind.
- When a probe is ambiguous, run the binary's `--version`; don't guess.

## 4. Skill anatomy

A project MUST place the implemented skill at:

```
.opencode/skills/<skill-name>/SKILL.md
```

with YAML frontmatter:

```yaml
---
name: <skill-name>
description: <one-line summary of its read-only, manual nature>
---
```

The `SKILL.md` body MUST contain these sections, in order:

### 4.1 Core principle
As per section 3 — state it verbatim or paraphrased: requirements are
discovered by probing, not reading; re-derive per session.

### 4.2 Procedure (all read-only; no test/dev/build runs)

Run these probes in order and build the requirement list from the results:

1. **Platform** — read `/etc/os-release`, `uname -m`, `id`. Picks the correct
   package source and binary architecture.
2. **Runtime toolchain** — `command -v <runtime> <package-manager> <runner>`,
   then `<runtime> --version`. Record the minimum version the project needs and
   the version actually present.
3. **Repo / dependencies** — is the repo mounted at `$PROJECT_DIR`? Is
   `node_modules` (or language equivalent) present? Presence of `.cmd` / `.ps1`
   shims in `<project-directory>/node_modules/.bin` means a Windows-populated
   volume (pure-language deps are fine; `npm install` reconciles platform
   binaries without wiping host shims).
4. **Migrations vs generated client** — does the newest schema object exist in
   the generated client? Any unapplied migrations in the migrations directory? →
   regenerate + migrate deploy before run/test.
5. **Infrastructure reachability** — database ready check (e.g. `pg_isready`),
   and a **docker socket check** (`command -v docker`,
   `test -S /var/run/docker.sock`) which decides whether docker-dependent
   entry commands (e.g. an auto-starting DB) work inside the current
   environment, or must degrade.
6. **Environment presence** — SET/EMPTY booleans only, NEVER values, for the
   project's env vars (secrets, API keys, bucket + credential pairs). Note
   which vars must be present for the deployment-relevant paths.
7. **Ports / listeners** — which of the project's ports are currently bound,
   and whether the host browser can reach the app (ports must be published to
   the host).

### 4.3 Decision map (finding → action)

A table, one row per likely finding, mapping each to an exact action. Examples
of rows a project will typically need:

| Finding | Action |
|---|---|
| Runtime missing / wrong major | Install the pinned runtime, or use the project's dev image |
| No docker socket | Docker-dependent entry commands won't run here — use the socket-less test command + a host DB |
| Secret/var missing | Set it — document the exact failure it causes |
| Storage bucket set but no credential | Fail loudly — pass the credential at runtime |
| Generated client stale | Regenerate (+ migrate deploy) |
| Database unreachable locally | Use the compose `db` service; point the app at the service name |
| No compose `dev` service in the repo | Project lacks a test sandbox — scaffold `Dockerfile.dev` + `dev` service (section 5) |
| Dev sandbox ports not published | Host browser can't reach the app — publish `$APP_PORT`/`$WS_PORT` |

### 4.4 Reference — last known good entry point

Established empirically (run the entry once successfully, then record it). Do
not re-derive it from memory — only re-verify the section-4.2 probes differ.

Contains:

- The exact run command for the dev/up path.
- The exact build command.
- The exact test command, including its docker-socket degradation variant.
- Any one-time bootstrap steps that differ from the steady state (first-run
  native-binary reconciliation, initial DB seed).

### 4.5 Guardrails

- Read-only probes only. Never run test/dev/build/migrate/seed scripts — in
  whole or in part — unless the user explicitly asks.
- Never print secret values — only set/empty booleans.
- Render the base image / secondary Dockerfiles off-limits for determining
  requirements; existence wins.
- When a probe is ambiguous, run the binary's `--version`, don't guess.

## 5. Reference structure — dev sandbox (recommended default)

The project's standard testing architecture: **two images, two containers**.

### 5.1 The split

- **Session container** — a LEAN container from the bare base image
  (e.g. `$BASE_IMAGE`). It is the LLM/agent session's workspace. No project
  runtime/toolchain is baked into it. The session startup script runs the base
  image directly **when no root `Dockerfile` exists** — so keep the repo root
  `Dockerfile` absent (or deliberately minimal) to keep the session image
  toolchain-free.
- **Dev container** — a SEPARATE image (`$DEV_IMAGE`) built from a project
  root `Dockerfile.dev`: `FROM $BASE_IMAGE` + the pinned runtime (e.g.
  `ARG $RUNTIME_VERSION`, installed from the official binary tarball) +
  `ENV PATH` + `EXPOSE $APP_PORT $WS_PORT`. It is brought up on demand through
  a compose `dev` service. Running it NEVER affects the session container.

### 5.2 Compose topology (one file, one project, one network)

```
services:
  db:
    image: <db-image:tag>
    ports: ["$DB_PORT:5432"]            # optional host exposure
    volumes: [<db-data-volume>:<db-data-path>]
    healthcheck: <db healthcheck>
  dev:
    build: { context: ., dockerfile: Dockerfile.dev }
    image: $DEV_IMAGE
    entrypoint: []
    command: ["<runner>", "$DEV_ENTRY"]   # the supervisor — section 5.3
    working_dir: $PROJECT_DIR
    environment:
      DATABASE_URL: <db-service-name>:5432/...
      <...project env vars...>
    volumes:
      - .:$PROJECT_DIR
    ports:
      - "$APP_PORT:$APP_PORT"
      - "$WS_PORT:$WS_PORT"
    depends_on:
      db:
        condition: service_healthy
```

Notes baked into the pattern:

- `entrypoint: []` **clears the base image's inherited entrypoint** so the
  `command` runs as PID 1 (correct signal handling).
- The dev service joins the same compose network as `db`, so the app reaches
  the database by **service name**, not by `host.docker.internal`.
- `depends_on: condition: service_healthy` makes `docker compose up dev` wait
  for the DB before starting the app.
- The repo is bind-mounted (`.:/workspace`), so `.env.local` / secrets ride
  along; compose `environment:` only overrides what it lists.

### 5.3 Two processes, never one

`$DEV_ENTRY` is a small supervisor script (e.g. `scripts/dev.mjs`) run as the
container's PID 1. It spawns the two processes the stack needs — the app dev
server and the companion service (e.g. a voice-pod WebSocket server) — both
inheriting stdio, and on exit/SIGINT/SIGTERM kills both children and propagates
the exit code. Never run the two as two separate compose services; keep them
one container, two children.

### 5.4 Running the sandbox

1. From the **host**, in the repo directory: `docker compose up dev` — builds
   `$DEV_IMAGE` once (cached after), waits for `db` healthy, boots the stack,
   ports `$APP_PORT`/`$WS_PORT` published to the host.
2. **First run only** — reconcile platform-native binaries into the
   (possibly Windows-populated) mounted `node_modules`:
   `docker compose run --rm dev <package-manager> install`.
3. Verify the supervisor's log markers, then open `http://localhost:$APP_PORT`
   from the **host browser**.
4. Teardown without touching the session: `docker compose down` (all) or
   `docker compose stop dev` (dev only).

### 5.5 Why this structure

- **Isolation** — `docker compose down dev` / restarts never disturb the
  session container's processes (which are children of the session, not of
  this compose project).
- **Declarative + reproducible** — ports, env, DB wiring, and entry live in a
  tracked `docker-compose.yml` / `Dockerfile.dev`, not in ad-hoc `docker run`
  flags or attacker-specific session launches.
- **Reachability** — ports are guaranteed published; the host browser can
  always reach the app and its WebSocket companion.
- **Portability** — the sandbox builds itself wherever compose runs; no
  dependency on an image cached from some other machine.
- **No daemon access needed from the session** — compose runs on the host;
  sessions with no docker socket are never blocked.

### 5.6 Guardrails for the sandbox

- Run compose **from the host, in the repo directory**. Running it from inside
  a container is broken by design: bind-mount paths resolve on the **host
  daemon**, so `.:/workspace` would target a nonexistent host path.
- Keep the session image **toolchain-free**. Deliberately do not add a root
  `Dockerfile`, so the startup script runs the bare base image. All project
  tooling belongs in `Dockerfile.dev`.
- Never run the docker-dependent test entry (e.g. auto-starting the DB from a
  container) inside a container — the docker socket decides; degrade to the
  socket-less test command + host DB.
- Never bake `.env`, credentials, or secrets into any image.

## 6. Per-project instantiation

Numbered bootstrap for the new project:

1. Create `.opencode/skills/<skill-name>/SKILL.md` from section 4, replacing
   every `$PLACEHOLDER` and generic example with the project's real stack:
   - probe 1: the OS/flavor it targets, its arch, and package source;
   - probe 2: its runtime/package-manager names + minimum/pinned version;
   - probe 5: its database and the project's dev/test entry commands (with and
     without a docker socket);
   - probe 6: the deployment-relevant env vars to check as booleans;
   - probe 7: the actual app + companion ports.
2. If the feature set includes a dev/test runtime (web app, CLI dev loop,
   integration suite), scaffold the sandbox from section 5:
   - create `Dockerfile.dev` (base + pinned runtime + `EXPOSE`),
   - create the compose `dev` service (and `db` service if needed) with a
     healthy-gated `depends_on`,
   - create the `$DEV_ENTRY` supervisor ("two processes, never one").
3. Establish the **last known good entry point** empirically: run the dev,
   build, and test commands once successfully, in the real environment, and
   record the exact commands in section 4.4. Include the first-run bootstrap
   steps as a distinct list.
4. Verify reachability once: host browser → `$APP_PORT` and the WebSocket
   companion → `$WS_PORT`.
5. Confirm the suite's socket-less degradation works (test command + host DB)
   from a no-socket context.

## 7. Maintenance

- **When to update**: every time the dev/build/test entry point changes —
  new deps, new companion service, new port, new DB — the skill's reference
  must be updated in the same change request.
- **How to re-verify, not re-derive**: on each session, run the section-4.2
  probes; only if they differ from the recorded reference, adjust the
  reference. Never rebuild the reference from memory wholesale.
- **Relationship to AGENTS.md**: the skill complements `AGENTS.md`; it does not
  replace it. `AGENTS.md` carries process/governance rules; the skill carries
  environment requirements and the entry-point runbook, discovered empirically.