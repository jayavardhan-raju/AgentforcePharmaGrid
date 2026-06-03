---
layout: default
title: Live Demo Automation
parent: Setup
nav_order: 5
---

# Live Demo Automation

The live demo flow starts at [Launch Live Demo](../live-demo.html) and provisions a 30-day scratch org from the requester's Salesforce Dev Hub.

## Required Services

| Service | Purpose |
|---|---|
| GitHub Pages | Hosts the secure launch form |
| Cloudflare Worker + KV | Short-lived auth URL broker |
| GitHub Actions | Claims the auth URL once and provisions the demo org |
| Mailtrap | Sends login credentials, expiration date, GIF, and artifact link |

## Broker Deployment

The Worker source lives in `broker/cloudflare-worker/`.

```bash
cd broker/cloudflare-worker
wrangler kv namespace create AUTH_TOKENS
wrangler secret put GITHUB_TOKEN
wrangler secret put ACTIONS_BROKER_TOKEN
wrangler deploy
```

After deployment, make sure `docs/live-demo.md` points its form `data-broker-url` to the Worker's `/launch` URL.

## GitHub Settings

Add these settings to `jayavardhan-raju/AgentforcePharmaGrid`:

| Type | Name | Value |
|---|---|---|
| Repository variable | `DEMO_BROKER_CLAIM_URL` | Worker `/claim` URL |
| Repository secret | `DEMO_BROKER_ACTIONS_TOKEN` | Same value as the Worker `ACTIONS_BROKER_TOKEN` secret |
| Repository secret | `MAILTRAP_TOKEN` | Mailtrap API token |
| Repository variable | `MAILTRAP_FROM_EMAIL` | Verified Mailtrap sender |
| Repository variable | `MAILTRAP_FROM_NAME` | Sender display name |

## Security Contract

- The Salesforce Dev Hub auth URL is accepted only by the HTTPS broker.
- The broker dispatches GitHub Actions with a request id and one-time claim token, not the auth URL.
- GitHub Actions writes the auth URL only to `$RUNNER_TEMP/sfauth.txt`, masks it, logs in with Salesforce CLI, and deletes the file immediately.
- Uploaded artifacts contain screenshots, JSON summaries, and the demo GIF. They do not contain the Dev Hub auth URL or scratch org password.
- Mailtrap email contains the scratch org login URL, username, password, expiration date, run/artifact link, repository link, and docs link.

## Expected Run

1. Verify the requester fork belongs to the submitted GitHub username and is a fork of `jayavardhan-raju/AgentforcePharmaGrid`.
2. Claim the auth URL once from the broker.
3. Create an Agentforce-ready scratch org for 30 days using `config/project-scratch-def.json`.
4. Deploy source, run Apex tests, assign `IST_Ops_User`, and seed all six scenarios.
5. Verify Prompt Builder and the real Agentforce Grid setup.
6. Run the six Salesforce UI Transfer/Optimize scenarios, open the Transfer Log for each scenario, capture screenshots, generate a GIF, upload artifacts, and send the Mailtrap email.

If Prompt Builder or the real Agentforce Grid is unavailable, the workflow fails honestly and still uploads setup evidence for the email/run log.
