---
layout: default
title: Home
nav_order: 1
---

# Pharmacy Inter-Store Transfer (IST) Documentation

Welcome to the documentation for **Pharmacy IST** — an Agentforce-powered inter-store inventory transfer system for US retail pharmacy, built on native Apex with DEA compliance, cold-chain validation, and atomic two-step execution.

---

## Quick Navigation

| Section | Description |
|---------|-------------|
| [Architecture](architecture/overview.md) | Layered design, data flow, and decision logic |
| [Data Model](architecture/data-model.md) | Custom objects, fields, formulas, and relationships |
| [Transfer Engine](architecture/transfer-engine.md) | Compliance gates, eligibility filters, and quantity calculation |
| [API Reference](api-reference/apex-classes.md) | ApexDox-style documentation for all Apex classes |
| [Agentforce Config](agentforce/configuration.md) | Prompt template, agent script, and Grid setup |
| [Deployment](setup/deployment.md) | Deploy, configure, and load test data |
| [Testing](setup/testing.md) | Test coverage map and test case scenarios |

---

## What Is Pharmacy IST?

In US retail pharmacy, when a store's stock of a medication hits zero, operations staff need to initiate an inter-store transfer from a nearby store that has surplus. This process is complicated by strict regulatory requirements — DEA Schedule II controlled substances cannot be transferred without a manual DEA Form 222, cold-chain medications need verified storage capability at both ends, and near-expiry stock must be excluded.

Pharmacy IST automates this entire workflow through an Agentforce Grid agent. The agent evaluates inventory, checks compliance, finds the best source store, calculates the right quantity, and executes the transfer — all with explicit user confirmation and a full audit trail. The system is built entirely on native Salesforce (Apex, Flows, custom objects) with zero middleware.
