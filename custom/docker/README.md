# The fork's image and its deployment

The production image is this fork with `enterprise/` and `custom/`, built like fazer.ai's
`latest-ee` (`CW_EDITION=ee`), and published to the **private** package
`ghcr.io/mauromachadon1992/chatwoot`. fazer.ai's `ghcr.io/fazer-ai/chatwoot:latest` deletes
`enterprise/` at build time and carries none of `custom/`.

| Script | What it does |
| --- | --- |
| `build-ee [branch]` | Builds from a clean shallow clone of the branch: `flow-chatwoot:<version>-<sha>-ee`, `<sha>-ee` and `latest-ee`, with OCI labels. |
| `ee-local up\|check\|logs\|down` | Runs that image on http://localhost:3100 with its own database and Redis. `check` prints the version, edition, extensions, plan and whether our code loaded. |
| `publish-ghcr` | Pushes the local `latest-ee` with the tags below, through the WSL's `docker login ghcr.io` (or a token on stdin). |
| `coolify.compose.yaml` | The production Coolify stack: rails, sidekiq, Baileys API, on the shared PostgreSQL and Redis. |
| `coolify.staging.compose.yaml` | The staging stack: the same services with their own PostgreSQL and Redis, nothing shared. |

## Staging

`atendimento` → environment `staging` → service `chatwoot-staging`, on
https://chat-hml.freitascasaeconstrucao.com.br. Only rails has a domain; the Baileys API,
PostgreSQL and Redis have no port or domain. Every secret is a Coolify `SERVICE_*` variable.
`FLOW_IMAGE_TAG` (a service variable) picks the build: set it to the new
`<version>-<sha>-ee` and restart the service. The native WhatsApp connector runs inside
sidekiq, with its pairings in the `chatwoot_staging_whatsapp_connector` database.

## Tags

`<version>` is Chatwoot's (`config/app.yml`), `<sha>` the fork's commit, 9 characters. The
`-ee` suffix is the variant, as in fazer.ai's `latest-ee`.

| Tag | Example | Moves? |
| --- | --- | --- |
| `<version>-<sha>-ee` | `4.18.0-3bd220e2f-ee` | Never. Pin this one in production. |
| `<sha>-ee` | `3bd220e2f-ee` | Never. The same build, by commit alone. |
| `<version>-ee` | `4.18.0-ee` | The last build on that Chatwoot version. |
| `latest-ee` | | The last build published. |

`publish-ghcr` refuses to push an immutable tag that already exists. The image carries
`org.opencontainers.image.{title,version,revision,created,ref.name}`, but not `.source`:
that would link the package to the public repository.

## What `build-ee` hardens

It patches the clone, never fazer.ai's files in the repository, and fails the build when a
patch finds nothing to change (so an upstream rewrite cannot silently ship an unhardened image):

- **Base images by digest**, from `base-images.pins`. Move a pin deliberately (the file says how).
- **No compiler toolchain in the runtime stage** (`build-base`): the gems are compiled in the
  pre-builder. `gcc`, `make` and `cc` are not in the image.
- **No development tooling or agent configuration** (`.github`, `.claude`, `e2e`, `tests`,
  `AGENTS.md` and the like), through `.dockerignore`.

There is no `HEALTHCHECK` in the image on purpose: rails and sidekiq share it, and a web probe
would mark the worker unhealthy. Health is per service in each compose. Still open: the image
runs as root (as fazer.ai's does); a non-root user needs the `storage` volume and
`/app/log`, `/app/tmp` ownership settled first.

## Release

1. Commit and push the branch.
2. `custom/docker/build-ee feat/kanban`. Building runs for minutes: start it detached
   (`setsid nohup custom/docker/build-ee feat/kanban > /tmp/flow-build.log 2>&1 < /dev/null &`).
3. `custom/docker/ee-local up`, then `custom/docker/ee-local check`. A fresh database sends
   `/app/login` to `/installation/onboarding` until the first super admin exists.
4. From Windows: `wsl -d Ubuntu -u mauro -- ~/chatwoot/custom/docker/publish-ghcr`. It uses
   the WSL's `docker login ghcr.io`, made once with a classic PAT that has `write:packages`
   (`wsl -d Ubuntu -u mauro -- docker login ghcr.io -u mauromachadon1992`). The gh CLI's
   token was refused by ghcr.io.
5. In Coolify, set `FLOW_IMAGE_TAG` to the new `<version>-<sha>-ee` and deploy. Rolling back
   to a previous build is setting it back to that build's tag.

## Coolify, first switch from fazer.ai's image

The compose is a drop-in for the `chatwoot-baileys` service: same service names, same
`storage` volume, same variable names. Before replacing the compose:

1. **Let the server pull the private image.** On the Coolify server (root, Coolify's own
   Docker): `docker login ghcr.io -u mauromachadon1992` with a token that has `read:packages`
   only. Coolify pulls with that login.
2. **Variables** (Service → Environment Variables). Keep every existing value; add the ones
   the old compose had written inline:
   - `POSTGRES_USERNAME`, `POSTGRES_PASSWORD` (the shared `postgres-compartilhado`; its host
     defaults to its Coolify name, `nwg0cgo4s480c8g0kww84kkk`, override with `POSTGRES_HOST`);
   - `REDIS_URL` (the shared `redis-compartilhado`, e.g.
     `redis://default:<password>@v0g8sswg0g8k0wsgcss0wck8:6379/0`), and `REDIS_PASSWORD` if
     the URL does not carry it;
   - `SERVICE_PASSWORD_64_SECRETKEYBASE` **must be the secret the installation runs with
     today.** Sessions, signed links and encrypted columns depend on it. If the current
     compose reads `SECRET_KEY_BASE` instead, copy that value here.
3. **WhatsApp connector.** This image runs fazer.ai's native connector inside sidekiq by
   default (`WHATSAPP_CONNECTOR_ENABLED=true`), creating `<database>_whatsapp_connector` on
   the shared PostgreSQL. Baileys inboxes keep using `baileys-api`. Set it to `false` to keep
   the worker exactly as before.
4. **Enterprise plan.** Only with a Chatwoot Inc license attached to this installation:
   `CHATWOOT_HUB_SYNC=true` (see `custom/README.md` → Chatwoot Enterprise).
5. Paste `coolify.compose.yaml` into Edit Compose File, keep the domains already set on
   `rails` (chat.) and `baileys-api` (wapi.), and deploy. Migrations run on the rails start
   (`docker/entrypoints/rails.sh`); sidekiq waits for them.

**Rolling back**: set the `rails` and `sidekiq` images back to `ghcr.io/fazer-ai/chatwoot:latest`
and redeploy. Our tables (`flow_kanban_*`, `flow_login_pages`) are simply ignored by it.
