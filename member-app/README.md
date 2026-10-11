# member-app: the training log for gym members

`opengym/` is [openGym](https://github.com/DuarteSantos8/openGym) (AGPL-3.0-or-later), copied unchanged except for
the files listed below. The native Gymmie member app ports its training log to Dart; this directory is the **source it was ported
from**, the host of the **exercise pictures** (`exercise-media/`, served by the `web` image) and an optional web version of the same log
(single sign-on, see below).

**Licence boundary.** Everything under `member-app/opengym/` is AGPL-3.0-or-later (see `opengym/LICENSE`,
`opengym/NOTICE.md`). It runs as its own containers and talks to the rest of Gymmie only over HTTP, so Gymmie's own code
is not part of that work. Because users interact with the modified server over a network, AGPL §13 requires offering
them its source: publish this directory and pass its URL to the app build as `--dart-define=OPENGYM_SOURCE_URL=...`
(shown in the member app under *My gym*).

## Changes against upstream openGym

| File | Change |
|---|---|
| `opengym/api/sso.js` (new) | Verifies Gymmie's signed, single-use, 60-second assertion; replay guard; the list of routes SSO-only mode closes. |
| `opengym/api/server.js` | `POST /api/sso/redeem`, `POST /api/sso/revoke`, `sso_only` in `/api/config`, 404 for passkey/password/pairing routes when `GYMMIE_SSO_ONLY=1`. |
| `opengym/api/openapi.yaml`, `Dockerfile` | The two routes; `sso.js` on the COPY line. |
| `opengym/api/test/sso.test.js` (new) | Module, route and SSO-only tests. |
| `opengym/frontend/src/views/Login.jsx`, `Login.sso.test.jsx` | On an SSO-only server the login screen says to reopen from the Gymmie app. |
| `opengym/frontend/src/lib/audit.js`, `locales/*.js` | Audit labels for the SSO events; one new string in all 18 locales. |

## Run it

```bash
cd member-app && cp .env.example .env     # fill the origin and OPENGYM_SSO_SECRET
docker compose up -d --build
```

Then give the Gymmie backend `OPENGYM_PUBLIC_URL`, `OPENGYM_API_URL`, `OPENGYM_SSO_SECRET` and switch **Member App**
on for a gym (Settings → App Features). Check everything without Docker or a phone:

```bash
node member-app/scripts/e2e-sso.mjs
```

See [`docs/MEMBER_APP.md`](../docs/MEMBER_APP.md) for the architecture, security model, test plan and rollback.
