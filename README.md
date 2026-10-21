# Proofarc agents — step by step

One Proofarc test agent, run with Docker on any machine. It connects **out** to your Proofarc
platform over HTTPS and runs tests from there. Nothing connects in to this machine.

| Service | What it does |
|---|---|
| `playwright` | UI tests on Playwright, and crawls with Playwright (its own browser is built in) |

WebDriver (Selenium) tests and the HtmlUnit crawler are not part of this setup.

---

## What you need before you start

- [ ] A machine with **Docker Desktop** (Mac/Windows) or **Docker Engine + Compose** (Linux).
      An Intel/AMD machine or Linux is best — see the note on Apple Silicon at the end.
- [ ] **2 CPUs and 4 GB of memory** for Docker. In Docker Desktop: Settings → Resources → set
      Memory to at least 4 GB and CPUs to at least 2. The agent runs two browser jobs at once and
      may use up to 3 GB; on a smaller machine set `PROOFARC_MAX_JOBS=1` in `.env`.
- [ ] Outbound **HTTPS (443)** from this machine to:
  - your Proofarc address (for example `ui-outpostqa.proofarc.ai`)
  - `ghcr.io` (our agent image)
- [ ] Network access from this machine to the application you want tested.
- [ ] From Proofarc, three things, each sent to you separately:
  1. a **pull token** — to download our images
  2. an **agent token** — for the agents to sign in to your Proofarc
  3. your **Proofarc address**

---

## Step 1 — Start Docker

Open Docker Desktop and wait until it says it is running. To check, in a terminal:

```
docker info
```

It should print details, not `Cannot connect to the Docker daemon`.

**Give Docker enough room.** In Docker Desktop open **Settings → Resources** and set
**Memory to at least 4 GB** and **CPUs to at least 2**, then **Apply & restart**. The agent runs a
real browser, two jobs at once, and uses up to 3 GB; with less, a heavy page can stall or crash it.
(Docker Engine on Linux has no such setting; the machine just needs that much free.)

## Step 2 — Go to this folder

```
cd /path/to/proofarc-local-agents
```

## Step 3 — Put in your settings

```
cp .env.example .env
```

Open `.env` in a text editor and fill in:

```
PROOFARC_URL=https://ui-outpostqa.proofarc.ai      # your Proofarc address, no trailing /
PROOFARC_AGENT_TOKEN=<the agent token>
PROOFARC_PULL_TOKEN=<the pull token>
PROOFARC_SITE=outpostqa                            # a short name for this site
PROOFARC_VERSION=v4.8.35                           # leave as sent
```

These three can stay as they are — they set how much the agent may use:

```
PROOFARC_CPUS=2          # CPUs the agent may use
PROOFARC_MEMORY=3g       # memory the agent may use
PROOFARC_MAX_JOBS=2      # browser jobs at once; set 1 on a small machine
```

Leave `PROOFARC_AGENT_USERNAME` and `PROOFARC_AGENT_PASSWORD` empty — the token replaces them.

`.env` holds secrets. Keep it on this machine; do not email it or commit it anywhere.

## Step 4 — Start the agents

Linux or Mac:

```
./start.sh
```

Windows (PowerShell):

```
powershell -ExecutionPolicy Bypass -File .\start.ps1
```

This signs in to our image registry with the pull token, downloads the image, and starts the
agent. The first time takes a few minutes. It should end without `denied` or `unauthorized`.

To do the same by hand: `docker login ghcr.io -u proofarc --password-stdin` (paste the pull
token, Enter, `Ctrl-D`), then `docker compose pull` and `docker compose up -d`.

## Step 5 — Check it connected

```
docker compose logs playwright
```

You should see:

- `Signing in with the configured token (valid until …)` — note the date; that is when the token
  runs out.
- `registered`

Then open your Proofarc in a browser, go to **Agents**, and look for
`<site>-playwright-001` (for example `outpostqa-playwright-001`).

## Step 6 — Run something

In Proofarc, run a UI test on **Playwright**, or a crawl, on the environment this agent serves.
When it finishes, open the run: the agent shows `<site>-playwright-001` when this agent ran it.

To watch the agent while it works:

```
docker compose logs -f playwright
```

`Ctrl-C` stops watching; the agent keeps running.

---

## Everyday commands

| To | Run |
|---|---|
| See what is running | `docker compose ps` |
| Watch the logs | `docker compose logs -f playwright` |
| Stop everything | `docker compose down` |
| Start again | `./start.sh` (Windows: `powershell -ExecutionPolicy Bypass -File .\start.ps1`) |
| Get our latest setup (settings, fixes to these files) | `git pull`, then `./start.sh` |
| Update to a new version | change `PROOFARC_VERSION` in `.env`, then start again |
| Run one job at a time (small machine) | set `PROOFARC_MAX_JOBS=1` in `.env`, then `./start.sh` |
| See how much it is using | `docker stats --no-stream` |
| Put in a new pull token | replace `PROOFARC_PULL_TOKEN` in `.env`, then start again |
| Put in a new agent token | replace `PROOFARC_AGENT_TOKEN` in `.env`, then `docker compose up -d` |

Stopping the containers cuts the connection immediately; Proofarc simply stops giving them work.

---

## If something goes wrong

| You see | What it means | What to do |
|---|---|---|
| `Cannot connect to the Docker daemon` | Docker is not running | Start Docker Desktop (step 1) |
| Jobs stay **Pending** and the agent shows **Offline** | The agent stopped — the machine slept, Docker quit, or the container was stopped | `docker compose ps`; then `./start.sh`. Waiting jobs are picked up within 15 seconds |
| The agent restarts during a crawl; `docker compose logs playwright` shows `Killed`, or `docker compose ps` shows exit code 137 | It ran out of memory | Give Docker Desktop more memory (Settings → Resources, at least 4 GB), or set `PROOFARC_MAX_JOBS=1` in `.env`, then `./start.sh` |
| `denied` or `unauthorized` while pulling | the pull token is missing from `.env` or has expired | check `PROOFARC_PULL_TOKEN` in `.env` (step 3); ask for a new pull token if it still fails |
| `AGENT_NO_CREDENTIALS` in the logs | no agent token in `.env` | Step 3; then `docker compose up -d` |
| `AGENT_TOKEN_REJECTED` in the logs | the agent token expired or was withdrawn | ask for a new agent token; put it in `.env`; `docker compose up -d` |
| the agent never says `registered` | this machine cannot reach your Proofarc address, or the address in `.env` is wrong | check `PROOFARC_URL`; check that `https://<your address>` opens from this machine |
| a test fails at the first page with `there is no site called …` | the address being tested cannot be reached from this machine | check this machine can open the application under test |

---

## Notes

- **Apple Silicon Macs:** our agent images are built for Intel/AMD, so Docker has to emulate them.
  That is untested. A Linux or Intel/AMD machine is the safe choice.
- **What leaves this machine:** test results — steps, pass/fail, screenshots, page details —
  sent to your Proofarc. Nothing else.
- **What the tokens can do:** the pull token can only download our images. The agent token can only
  do what an agent does — ask for work and report results — and stops working the moment the
  account behind it is switched off in Proofarc.
