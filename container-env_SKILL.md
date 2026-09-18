---
name: container-env
description: Use when setting up or starting a new or existing project in an opencode Docker container. Triggers on "new project", "existing project", "Docker", "Dockerfile", "docker-compose", "environment setup", or "how is this environment set up". Explains the container environment to the session and drafts the project's Dockerfile + docker-compose.yml using a single dev image model (no separate runtime image).
---

# container-env

## Purpose

Every opencode session runs inside a Docker container. Drafting the project's
container setup is part of the job whenever a new or existing project directory
is being worked on. This skill makes sure the session understands its own
environment before generating anything, and that the container config produced
matches the container model chosen for this machine.

## Environment facts and introspection

All LLM sessions run in an opencode Docker container. The exact base image and
toolchain can vary, so never assume anything.

Before doing anything else, verify the environment read-only:

- Working directory and how it is mounted (`pwd`, `/proc/self/mountinfo`,
  `ls -la`).
- Which tools actually exist: `node`, `npm`, `bun`, `python3`, `pip3`, `go`,
  `rustc`, `cargo`, `git`, `make`, `gcc`, `docker`.
- OS facts: `uname -a`, `/etc/os-release`.

The base image is typically minimal (a Debian-based opencode image with only a
few tools such as `git`). Do not assume package managers, runtimes, or the
`docker` CLI are available inside the container.

The `docker` CLI is generally NOT available inside the opencode container.
Image builds are triggered by the user on the host; the session writes the
config files and the user runs the build.

## Canonical container model: single dev image via docker compose

The model chosen for this environment. Use it for all projects; do not ask
again.

- **Authoring environment** = the opencode container the session runs in.
  Code is written, edited, and committed here.
- `Dockerfile` = the one and only project build file. Layered: the deps the
  project needs, derived from reading the code, pinned near the top of the file
  so build caching keeps rebuilds fast. App-code layers last.
- `docker-compose.yml` = runs that image as the **dev/test environment**,
  isolated from the opencode container, with the source directory mounted and
  ports exposed so the user can view progress of the code at runtime.

There is intentionally **no separate runtime image**. The project's run target
is the dev environment via compose. Add a standalone runtime/packaged image
only later, and only if the project is ever shipped, deployed, or handed off.

Reference file layout:

```
.
├── Dockerfile          # project image: deps layered on the opencode base
├── docker-compose.yml  # dev/test environment, source mounted, ports exposed
└── (project code)      # written in the opencode authoring container
```

## Dependency workflow: user-triggered, rebuild-only

Adding a package dependency over time is driven by the user, never ambient:

1. The session reads the code and derives which packages it requires.
2. The session updates the `Dockerfile` (and `docker-compose.yml` if needed)
   to add the dependency as a new layer.
3. The **user** manually triggers the build/update
   (`docker compose build` / `docker compose up`). The session does not run it.
4. The session does **not** install packages into the live opencode container
   as the authoritative change. Any such install is at most a temporary local
   probe and must be recorded back into the `Dockerfile`.

## Session start sequence

When starting work on a new or existing project directory:

1. **Explain the environment.** State concisely that this session runs in an
   opencode Docker container, and summarize the verified facts (cwd, mounts,
   available tools).
2. **Discuss the project's purpose with the user.** Ask what the directory is
   for before generating anything.
3. **Generate the container config only after the purpose discussion.**
   Produce the `Dockerfile` and `docker-compose.yml` following the canonical
   model above. No scaffolding of build files before the purpose is agreed.
4. Announce what was chosen and why (single dev image via compose, user-triggered
   rebuilds), and tell the user to run `docker compose build` / `docker compose up`
   when they want to build or view progress.

## Install notes

To install this as a live skill, place it at
`.opencode/skills/container-env/SKILL.md` (project scope) or
`~/.config/opencode/skills/container-env/SKILL.md` (global scope), then quit and
restart opencode for it to take effect.