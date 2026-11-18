# ProofArc on your own machine

The whole ProofArc platform in Docker on one computer, for testing **your web app** with Playwright
UI tests and **your API** with API tests. Nothing connects in from outside, and your tests and
results stay on this machine.

| Service | What it does |
|---|---|
| `postgres`, `db-init` | the database; `db-init` creates it on the first start and updates it later |
| `security-agent` | the platform itself, API on port 8080 |
| `ui` | the web app, http://localhost:3000 |
| `mcp` | the MCP server, so Claude Code or another AI agent can work with ProofArc: http://localhost:8090/mcp |
| `playwright-agent` | runs web UI tests and crawls your site, with its own browser |
| `api-test-agent` | runs API tests |

(The `proofarc-local-agents` folder above this one is something else: agents that connect to a
ProofArc we host. You need only one of the two.)

## What you need

- **Docker Desktop** (Mac, Windows) or **Docker Engine with the Compose plugin** (Linux).
- **6 GB of memory for Docker.** In Docker Desktop: Settings → Resources → Memory 6 GB or more →
  Apply & restart. `./start.sh` stops and says so if Docker has less.
- **The pull token** we sent you, to download our images.
- About 3 GB of free disk for the images.
- On Windows, run the commands in **Git Bash** or **WSL**, not PowerShell.

An Intel/AMD machine is best. On an Apple Silicon Mac it works, but Docker runs our images emulated,
so the first start and the tests are slower.

## Start

```
cd local-platform
./start.sh
```

The first time, it creates `.env` and stops to ask for the pull token. Open `.env`, put the token on
the line `PROOFARC_PULL_TOKEN=`, and run `./start.sh` again. Everything else (passwords, keys) is
generated for you and kept in `.env`.

It then downloads the images, starts everything and waits until it is ready, which takes 2 to 5
minutes the first time. It ends with a check like this:

```
  ok    platform answers on http://localhost:8080
  ok    admin signs in with the password in .env
  ok    admin is an administrator
  ok    only admin and agent-service can sign in
  ok    playwright agent is connected
  ok    api-test agent is connected
  ok    web app opens on http://localhost:3000
  ok    MCP server listens on http://localhost:8090/mcp
All checks passed.
```

## Your login

| | |
|---|---|
| **user** | `admin` |
| **password** | generated on the first start; `./start.sh` prints it at the end, and it is kept in `.env` on the line `PROOFARC_ADMIN_PASSWORD=` |
| **role** | administrator: can create projects, environments, logins and tests, and manage everything |

Open http://localhost:3000 and sign in with it. The same login is used for MCP (below).

To pick your own password, put it on that line in `.env` before the first `./start.sh`, or change
it there later and run `./start.sh` again: it restarts the platform so the new password works at
once (about a minute).

Only two users can sign in: `admin` (you) and `agent-service` (the two test agents, which sign in by
themselves). The demo users in the starting data are switched off. The ports open on this machine
only, not to your network.

## The `.env` file

`./start.sh` creates it from `.env.example`. **You fill in one line, `PROOFARC_PULL_TOKEN=`**; the
script generates every password and key. Change a port only if `./start.sh` says it is taken.

## Set up your app: project, application, target, login

ProofArc needs four things before it can test your app. You set them up once:

| | what it is | example |
|---|---|---|
| **project** | the folder your tests live in | `My Shop` |
| **application** | your web app or your API; each gets a short tag | `shop-web`, `shop-api` |
| **environment and target** | where the app runs: the environment is a name, the target is the address | `local`, `http://host.docker.internal:4200` |
| **login** | the username and password the tests sign in with, saved in ProofArc and used in tests as `{{username}}` and `{{password}}` | tag `qa-user` |

### The address of your app

The tests run inside Docker, so **"localhost" there means the container, not your machine.**

| Your app runs... | Give ProofArc the address |
|---|---|
| on this machine, port 4200 | `http://host.docker.internal:4200` |
| on another machine in your network | its normal address, e.g. `http://10.0.5.12:8080` or `https://app.internal` |
| on the internet | its normal address |

An app on this machine must listen on all addresses, not only on 127.0.0.1, or Docker cannot reach
it. Most dev servers have a setting for this (`--host 0.0.0.0`).

### 1. Connect Claude Code (or another MCP client)

```
TOKEN=$(curl -s http://localhost:8080/api/auth/login -H 'Content-Type: application/json' \
  -d "{\"username\":\"admin\",\"password\":\"$(sed -n 's/^PROOFARC_ADMIN_PASSWORD=//p' .env)\"}" \
  | python3 -c 'import sys,json;print(json.load(sys.stdin)["token"])')
claude mcp add --transport http proofarc-local http://localhost:8090/mcp --header "Authorization: Bearer $TOKEN"
```

Restart Claude Code so it picks up the server. The token lasts 24 hours; run the two lines again
when it expires.

### 2. Create the project, applications and targets

Ask Claude, with your own names and addresses:

> Onboard a project "My Shop" with environment "local": a web app "shop-web" at
> http://host.docker.internal:4200 and an API "shop-api" at http://host.docker.internal:8081.

It calls `onboard_project` and should answer `SUCCESS` with 2 targets created.

### 3. Save the login your tests use

Ask Claude:

> Add a login with tag "qa-user" to environment "local", username qa@example.com, and make it the default.

and give it the password. If you would rather not type a password into a chat, save the login
with curl (use the environment's id; Claude can tell you it, or `GET /api/environments`):

```
curl -X POST http://localhost:8080/api/environments/<id>/auth-config/credentials \
  -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' \
  -d '{"tag":"qa-user","username":"qa@example.com","password":"...","isDefault":true}'
```

The password is stored encrypted in this machine's database and is never shown again.

### 4. Tell ProofArc how your app signs in

- **Your API** signs in with a login request that returns a token: tell Claude the request and where
  the token is, e.g. *"environment local signs in with POST /api/auth/login, the token is at
  $.token"* (`set_environment_auth_endpoint`). Each API test then names the login with
  `credentialTag: qa-user` and is signed in before its first step.
- **Your web app**: *"the shop-web target signs in at /login with the qa-user login"*
  (`set_target_auth`). The crawler uses it to get behind the login. A UI test signs in with its own
  steps, typing `{{username}}` and `{{password}}`.

### 5. Crawl, write the tests, run them

> Crawl shop-web, then write a UI test that signs in and checks the orders page, and run it.

> Write an API test for GET /api/orders that expects 200, and run it.

Claude crawls (1 to 2 minutes), writes the test from what the crawl found, runs it on the local
Playwright or API agent, and reports passed or failed. Runs show in the web app under **Runs**.

What an API test looks like:

```yaml
name: Orders list answers
appTag: shop-api
credentialTag: qa-user
baseUrl: "{{baseUrl}}"
steps:
  - name: List orders
    method: GET
    path: /api/orders
    expect: [200]
```

And a UI test:

```yaml
appTag: shop-web
steps:
  - action: NAVIGATE_TO
    url: "{{baseUrl}}/login"
  - action: WAIT_FOR_VISIBLE
    selector: 'input[name="username"]'
    timeout: 15000
  - action: CLEAR
    selector: 'input[name="username"]'
  - action: SEND_KEYS
    selector: 'input[name="username"]'
    value: "{{username}}"
  - action: CLEAR
    selector: 'input[name="password"]'
  - action: SEND_KEYS
    selector: 'input[name="password"]'
    value: "{{password}}"
  - action: CLICK
    selector: 'button[type="submit"]'
  - action: WAIT_FOR_INVISIBLE
    selector: 'input[name="password"]'
    timeout: 15000
  - action: VALIDATE_TEXT
    selector: 'main'
    expectedText: "Orders"
```

The selectors come from your app; the crawl lists them.

## Every day

| | |
|---|---|
| `./start.sh` | start again, or update after you change `PROOFARC_VERSION` in `.env` |
| `./check.sh` | is everything up? |
| `docker compose logs -f playwright-agent` | watch a service (any name from the table at the top) |
| `docker compose restart playwright-agent api-test-agent` | the agents connect once, when they start; restart them if the platform was restarted on its own |
| `docker compose down` | stop; your tests and runs are kept |
| `docker compose down -v` | stop and **delete everything**; the next start begins empty |

## If something goes wrong

| You see | What to do |
|---|---|
| `Port 8080 is already used by another program` | pick a free port in `.env` (`PROOFARC_API_PORT=8081`) and run `./start.sh` again; same for 3000 and 8090 |
| `ghcr.io refused the pull token` | the token was not copied whole, or has expired; ask us for a new one |
| `Docker has 4 GB of memory` | raise it in Docker Desktop (Settings → Resources) |
| a UI test cannot open your app | use `host.docker.internal` instead of `localhost`, and make the app listen on all addresses |
| a check fails | run the `docker compose logs` command it names and send us the output |

Your admin password is set from `.env` on every start, so if you change it in the web app it goes
back to the `.env` one at the next `./start.sh`. To change it for good, change it in `.env` and run
`./start.sh`.
**Never change `ENCRYPTION_KEY`** once you have saved logins for your apps: they are encrypted with
it.
