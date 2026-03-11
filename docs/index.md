---
layout: default
title: Home
nav_order: 1
---

# AgentforceGrid Documentation

**Agentforce-powered inter-store inventory transfer system for pharmacy networks.**

---

## What Is AgentforceGrid?

Pharmacy networks face a constant operational challenge: individual stores run out of critical medications while other stores in the same district hold surplus. Traditional rebalancing requires manual phone calls, spreadsheet tracking, and no compliance enforcement — leading to slow response times and regulatory risk.

AgentforceGrid solves this by embedding an automated inter-store transfer (IST) engine directly into the Salesforce Agentforce Grid. An operations user sees a real-time inventory dashboard, identifies a critical stock row, and triggers a transfer recommendation with a single click. The system finds the best source store, validates DEA compliance and cold-chain logistics, calculates the optimal transfer quantity, and either recommends or executes the transfer — all within a two-step conversational agent workflow.

Schedule II controlled substances are automatically blocked with a hard compliance stop and an immutable audit log. Every action — successful or denied — is recorded in a `Transfer_Log__c` for DEA audit trail purposes.

---

## Documentation

| Section | Description |
|---------|-------------|
| [Architecture Overview](architecture/overview.html) | Layered architecture, data flow, and security model |
| [Data Model](architecture/data-model.html) | Custom objects, fields, relationships, and ER diagram |
| [Transfer Engine](architecture/transfer-engine.html) | Quantity calculation, source selection, compliance logic |
| [Apex API Reference](api-reference/apex-classes.html) | ApexDox-style documentation for all Apex classes |
| [Deployment Guide](setup/deployment.html) | Prerequisites, deploy commands, data loading scripts, post-deployment steps |
| [Testing Guide](setup/testing.html) | Test classes, coverage map, and how to run tests |

---

## Quick Start

```bash
git clone https://github.com/jayavardhan-raju/AgentforceGrid.git
cd AgentforceGrid
sf project deploy start --target-org <your-org>
sf org assign permset -n IST_Ops_User -o <your-org>
```

See the [Deployment Guide](setup/deployment.html) for full instructions.
