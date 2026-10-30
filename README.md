# Kong AI Demo: from AI factory to production

A 30-minute pitch and live demo of **Kong AI Gateway** for GNB, a fictional Tier-1 UAE bank.

GNB has built an on-prem AI factory: 64 GPUs, open-weight Arabic-capable models, embeddings and a vector store. It has 12 AI use cases, 7 generative and 5 agentic, and none of them is in production. Every use case needs the same controls before it can go live: security, governance and cost control.

The deck's argument: Kong AI Gateway is the missing layer between the factory and production. With it in place, going to production becomes a decision about each use case, not about missing infrastructure.

## What's in the deck

| Part | What it covers |
|---|---|
| **The story** | Where AI stalls between the factory and production, and what production means for the CIO, the Platform Owner and the Lead Architect |
| **How** | Where Kong sits: the data path stays on-prem, and Konnect (SaaS) holds only configuration and metadata. Also the demo's reference architecture |
| **Live demo** | Four acts. **Connect:** one endpoint, failover to the DR site. **Secure it:** PII redaction, prompt and response guards, audit. **Govern tokens:** semantic routing, semantic cache, token budgets, cost per use case. **Agents:** MCP tools with per-identity access |
| **Proof** | Why Kong, the value to the bank, build vs extend, one platform for APIs, events and AI, and next steps |
| **Appendix** (hidden slides) | Capabilities, use cases, the UAE and GCC governance mapping, and the configuration as code |

## Demo stack

- Kong AI Gateway 2.2 data plane in Docker, with a Konnect control plane (hybrid mode)
- Qwen 2.5 7B and 1.5B on Ollama, standing in for the bank's vLLM, plus `nomic-embed-text` for embeddings
- OpenAI for the agent act, with the local 7B model as its fallback
- Redis 8 for vector search (semantic routing, cache and guards), Kong's AI PII service, and a mock card-services API that Kong exposes as an MCP server
- GNB Assist, the bank's chat app: Open WebUI branded as GNB, calling Kong for every message
- Configuration as code with `kongctl`

## Run the demo

### What you need

- A Mac with Apple silicon, [Homebrew](https://brew.sh), Docker Desktop and Google Chrome
- `brew install --formula ollama node python kong/kongctl/kongctl` (kongctl 1.20.2 or later, Node 22 or later)
- A Konnect account (a trial works) and an OpenAI API key for the agent in Act 4
- About 16 GB free: 6 GB of models and 10 GB of container images

### Set up once

1. **In Konnect**, create an AI Gateway with runtime version **2.2**, used only for this demo. Each start syncs `kong/` to it, which removes any demo object that isn't in `kong/`.
2. On the gateway's **Data plane nodes** page, add a node. Konnect generates a certificate and key: save them as `certs/cluster.crt` and `certs/cluster.key`, and note the control plane endpoint (`<id>.<region>.cp.konghq.com`).
3. Create a **personal access token** in Konnect.
4. Run `./setup.sh`. It checks the tools, asks for the token, the gateway ID, the endpoint and the OpenAI key, and writes `.env`. It also generates the demo's API keys, checks the certificate and your gateway, pulls the models and builds the **GNB demo** launcher with `3-cli-ui-webui/launcher/build.sh`. Run it again until everything is ✓; it keeps what's already set.

### Run it

Double-click **GNB demo** in this folder. The app isn't in Git: `setup.sh` builds it, and `3-cli-ui-webui/launcher/build.sh` rebuilds it on its own if it's missing. It opens the **Run tab**, the run of show as a runbook: **Start the demo**, then **Pre-flight**, then each act step by step. The first start downloads the container images, builds GNB Assist's image from `3-cli-ui-webui/webui/Dockerfile` and applies `kong/` to Konnect. Sign in to Konnect once in the Konnect window it opens.

| Page | Address |
|---|---|
| Run tab (keep it off the shared screen) | http://localhost:8098/?run |
| Live panes: what each site's model received, what Kong decided | http://localhost:8098 |
| GNB Assist (five test personas, with a "Sign in as" picker) | http://localhost:3000 |
| Architecture page, built from the deployed config by `arch/build.py` | http://localhost:8099 |
| Kong data plane (AI traffic, MCP) | http://localhost:8000 |

The same from a terminal: `3-cli-ui-webui/scripts/start.sh`, `preflight.sh`, `reset.sh` (back to baseline) and `shutdown.sh` (stops everything, deletes nothing).

## What's in the repo

| Path | What it is |
|---|---|
| `Kong_Panel_GNB_30min_v2.pptx` | The deck (PowerPoint, 16:9), speaker notes removed |
| `setup.sh`, `.env.example` | One-time setup, and the settings it writes to `.env` |
| `kong/` | The AI Gateway configuration as code (`kongctl`): providers, vault, auth, consumers, groups, models, policies, MCP server |
| `onboard/` | The 13th use case, onboarded live with one file |
| `docker-compose.yml` | Kong's data plane, Redis, the PII service, the card-services mock and the egress proxy |
| `factory/` | The two "data centre" nodes in front of Ollama (DC1 primary, DC2 for DR) |
| `mocks/card-services/` | The card-services API that Kong turns into MCP tools |
| `egress/` | The data plane's only route to Konnect: stopping it is the "unplug Konnect" finale |
| `scripts/` | The shared stack's scripts: factory, reset, pre-flight, act scripts, Konnect cut |
| `3-cli-ui-webui/` | The scenario: GNB Assist (`webui/`), the live panes and Run tab (`panes/`), the stage scripts (`scripts/`) and the launcher (`launcher/build.sh` builds **GNB demo**) |
| `arch/` | The architecture page: `build.py` builds it from your gateway's deployed config, and `live.py` serves it |
| `agent/`, `app/` | The card-ops agent the act scripts run, and the six-line app example |
| `examples/` | An OIDC auth strategy, shown as config only |

---

GNB, its staff and all the data are fictional; the Emirates ID in the demo is a test value. This is a personal project, not an official Kong document. Product names belong to their owners. GNB Assist rebrands Open WebUI v0.11.4, whose licence allows that for deployments with no more than 50 users in a rolling 30 days; this demo has five test personas.
