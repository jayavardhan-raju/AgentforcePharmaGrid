import { parseArgs } from "node:util";

import { ensureDir, getOrgOpenUrl, querySalesforce, writeJsonFile } from "./lib.mjs";

const PROMPT_API_NAME = "IST_Inventory_Recommendation";
const PROMPT_NAME = "IST Inventory Recommendation";
const PROMPT_TEXT = `You are a US retail pharmacy inventory analyst assistant.
Analyse the inventory record below and generate a concise, actionable
recommendation in 1-2 sentences maximum.

INVENTORY RECORD:
- Record ID: {!$Input:Inventory_Position__c.Id}
- Store: {!$Input:Inventory_Position__c.Store__r.Name}
- Medication: {!$Input:Inventory_Position__c.Medication__r.Name}
- DEA Schedule: {!$Input:Inventory_Position__c.Medication__r.DEA_Schedule__c}
- Cold Chain Required: {!$Input:Inventory_Position__c.Medication__r.Cold_Chain_Required__c}
- Current Quantity: {!$Input:Inventory_Position__c.Quantity__c}
- Safety Stock Level: {!$Input:Inventory_Position__c.Safety_Stock__c}
- Expiry Date: {!$Input:Inventory_Position__c.Expiry_Date__c}
- Status: {!$Input:Inventory_Position__c.Status__c}

RULES YOU MUST FOLLOW:
1. If DEA Schedule is "II" output exactly:
"Schedule II: Manual DEA Form 222 transfer required. No automated action available."
2. If Status is "Critical" or "OUT_OF_STOCK" and DEA Schedule is not "II" output:
"Critical stock. Recommend initiating inter-store transfer via Transfer/Optimize action."
3. If stock is adequate but below double safety stock output:
"Stock adequate but approaching reorder threshold. Monitor closely."
4. If stock is healthy output:
"Stock levels healthy. No action required at this time."
5. If Expiry Date is within 30 days from today prefix your output with "EXPIRY ALERT: ".
6. Never recommend specific transfer quantities in this column.
7. Keep the entire output under 150 characters.

OUTPUT ONLY THE RECOMMENDATION TEXT.`;

const { values } = parseArgs({
  options: {
    "target-org": { type: "string" },
    artifacts: { type: "string" },
  },
});

if (!values["target-org"] || !values.artifacts) {
  throw new Error("Usage: node configure-prompt-builder.mjs --target-org <alias> --artifacts <dir>");
}

await ensureDir(`${values.artifacts}/screenshots`);

const before = await findPrompt(values["target-org"]);
if (before.records.length > 0 && isActive(before.records[0])) {
  await writeJsonFile(`${values.artifacts}/prompt-builder.json`, {
    status: "already_active",
    prompt: before.records[0],
  });
  console.log(`${PROMPT_API_NAME} already exists and is active`);
  process.exit(0);
}

const { chromium } = await import("playwright");
const browser = await chromium.launch({ headless: true });
const page = await browser.newPage({ viewport: { width: 1440, height: 1000 } });

try {
  const promptHomeUrl = await getOrgOpenUrl(
    values["target-org"],
    "/lightning/setup/EinsteinGPTPromptTemplates/home",
  );
  await page.goto(promptHomeUrl, { waitUntil: "domcontentloaded", timeout: 120000 });
  await page.screenshot({ path: `${values.artifacts}/screenshots/PB-001-home.png`, fullPage: true });

  await clickFirst(page, [/new prompt template/i, /^new$/i]);
  await page.waitForTimeout(3000);
  await page.screenshot({ path: `${values.artifacts}/screenshots/PB-002-new-template.png`, fullPage: true });

  await fillFirst(page, [/name/i], PROMPT_NAME);
  await fillFirst(page, [/api name/i, /developer name/i], PROMPT_API_NAME);
  await fillFirst(page, [/description/i], "Analyzes inventory rows and generates pharmacy IST recommendations.");
  await fillFirst(page, [/system prompt/i, /prompt/i, /instructions/i], PROMPT_TEXT);
  await page.screenshot({ path: `${values.artifacts}/screenshots/PB-003-filled-template.png`, fullPage: true });

  await clickFirst(page, [/save/i, /create/i]);
  await page.waitForTimeout(5000);
  await page.screenshot({ path: `${values.artifacts}/screenshots/PB-004-saved-template.png`, fullPage: true });

  await clickIfPresent(page, [/activate/i]);
  await page.waitForTimeout(3000);
  await page.screenshot({ path: `${values.artifacts}/screenshots/PB-005-activation-attempt.png`, fullPage: true });
} finally {
  await browser.close();
}

const after = await findPrompt(values["target-org"]);
await writeJsonFile(`${values.artifacts}/prompt-builder.json`, {
  status: after.records.length > 0 && isActive(after.records[0]) ? "active" : "not_active",
  query_error: after.error,
  prompt: after.records[0] || null,
});

if (after.records.length === 0 || !isActive(after.records[0])) {
  throw new Error(
    `Prompt Builder template ${PROMPT_API_NAME} is not active. Setup evidence screenshots were captured.`,
  );
}

console.log(`${PROMPT_API_NAME} created and active`);

async function findPrompt(targetOrg) {
  try {
    const records = await querySalesforce(
      targetOrg,
      `SELECT Id, DeveloperName, MasterLabel, ActiveVersion FROM AiPrompt WHERE DeveloperName = '${PROMPT_API_NAME}' LIMIT 1`,
    );
    return { records };
  } catch (error) {
    return { records: [], error: error.message };
  }
}

function isActive(record) {
  return Number(record.ActiveVersion || 0) > 0;
}

async function clickFirst(page, labels) {
  for (const label of labels) {
    const locator = page.getByRole("button", { name: label }).first();
    if (await locator.count()) {
      await locator.click({ timeout: 10000 });
      return true;
    }

    const link = page.getByRole("link", { name: label }).first();
    if (await link.count()) {
      await link.click({ timeout: 10000 });
      return true;
    }
  }

  throw new Error(`Could not find a clickable control matching: ${labels.join(", ")}`);
}

async function clickIfPresent(page, labels) {
  try {
    return await clickFirst(page, labels);
  } catch {
    return false;
  }
}

async function fillFirst(page, labels, value) {
  for (const label of labels) {
    const byLabel = page.getByLabel(label).first();
    if (await byLabel.count()) {
      await byLabel.fill(value, { timeout: 10000 });
      return true;
    }

    const placeholder = page.getByPlaceholder(label).first();
    if (await placeholder.count()) {
      await placeholder.fill(value, { timeout: 10000 });
      return true;
    }
  }

  throw new Error(`Could not find a field matching: ${labels.join(", ")}`);
}
