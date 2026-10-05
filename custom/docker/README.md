# The fork's image and its deployment

The production image is this fork with `enterprise/` and `custom/`, built like fazer.ai's
`latest-ee` (`CW_EDITION=ee`), and published to the **private** package
`ghcr.io/mauromachadon1992/chatwoot`. fazer.ai's `ghcr.io/fazer-ai/chatwoot:latest` deletes
`enterprise/` at build time and carries none of `custom/`.

| Script | What it does |
| --- | --- |
| `build-ee [branch]` | Builds from a clean shallow clone of the branch: `flow-chatwoot:<sha>-ee` and `latest-ee`. |
| `ee-local up\|check\|logs\|down` | Runs that image on http://localhost:3100 with its own database and Redis. `check` prints the version, edition, extensions, plan and whether our code loaded. |
| `publish-ghcr` | Pushes the local `latest-ee` as `<sha>-ee` and `latest-ee` (token on stdin). |
| `coolify.compose.yaml` | The Coolify stack: rails, sidekiq, Baileys API, on the shared PostgreSQL and Redis. |

## Release

1. Commit and push the branch.
2. `custom/docker/build-ee feat/kanban`. Building runs for minutes: start it detached
   (`setsid nohup custom/docker/build-ee feat/kanban > /tmp/flow-build.log 2>&1 < /dev/null &`).
3. `custom/docker/ee-local up`, then `custom/docker/ee-local check`. A fresh database sends
   `/app/login` to `/installation/onboarding` until the first super admin exists.
4. From Windows: `gh auth token | wsl -d Ubuntu -u mauro -- ~/chatwoot/custom/docker/publish-ghcr`.
   The token needs `write:packages`; grant it once with
   `gh auth refresh -h github.com -s write:packages,read:packages`.
5. In Coolify, deploy with `FLOW_IMAGE_TAG` set to the new `<sha>-ee` (or leave `latest-ee`).

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
