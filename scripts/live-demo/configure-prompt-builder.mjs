import { parseArgs } from "node:util";

import { ensureDir, getOrgOpenUrl, querySalesforce, sfJson, writeJsonFile } from "./lib.mjs";

const PROMPT_API_NAME = "IST_Inventory_Recommendation";
const PROMPT_NAME = "IST Inventory Recommendation";
const PROMPT_METADATA_API_VERSION = "66.0";
const PROMPT_METADATA_SOURCE_DIR = "metadata/prompt-builder/genAiPromptTemplates";
const PROMPT_BUILDER_HOME_PATHS = [
  "/lightning/setup/EinsteinPromptStudio/home",
  "/lightning/setup/EinsteinGPTPromptTemplates/home",
];
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

const metadataDeploy = await deployPromptTemplateMetadata(values["target-org"]);
if (metadataDeploy.ok) {
  const afterMetadataDeploy = await waitForPrompt(values["target-org"], { active: true, timeoutMs: 60000 });
  if (afterMetadataDeploy.records.length > 0 && isActive(afterMetadataDeploy.records[0])) {
    await writeJsonFile(`${values.artifacts}/prompt-builder.json`, {
      status: "active",
      configured_by: "metadata_deploy",
      prompt: afterMetadataDeploy.records[0],
    });
    console.log(`${PROMPT_API_NAME} deployed and active from metadata`);
    process.exit(0);
  }
}

const { chromium } = await import("playwright");
const browser = await chromium.launch({ headless: true });
const page = await browser.newPage({ viewport: { width: 1440, height: 1000 } });

try {
  await openPromptBuilderAndClickNew(page);
  await page.waitForTimeout(3000);
  await page.screenshot({ path: `${values.artifacts}/screenshots/PB-002-new-template.png`, fullPage: true });

  await completeTemplateTypeStep(page);
  await page.screenshot({ path: `${values.artifacts}/screenshots/PB-003-template-editor.png`, fullPage: true });

  await fillFirst(page, [/name/i], PROMPT_NAME);
  await fillIfPresent(page, [/api name/i, /developer name/i], PROMPT_API_NAME, { timeoutMs: 10000 });
  await fillIfPresent(page, [/description/i], "Analyzes inventory rows and generates pharmacy IST recommendations.", {
    timeoutMs: 10000,
  });

  if (!(await fillIfPresent(page, [/system prompt/i, /prompt/i, /instructions/i], PROMPT_TEXT, { timeoutMs: 10000 }))) {
    await clickIfPresent(page, [/^next$/i, /continue/i], { timeoutMs: 15000 });
    await page.waitForTimeout(3000);
    await fillFirst(page, [/system prompt/i, /prompt/i, /instructions/i], PROMPT_TEXT);
  }

  await page.screenshot({ path: `${values.artifacts}/screenshots/PB-004-filled-template.png`, fullPage: true });

  await saveOrAdvancePromptTemplate(page);
  await page.screenshot({ path: `${values.artifacts}/screenshots/PB-005-saved-template.png`, fullPage: true });

  await clickIfPresent(page, [/activate/i]);
  await page.waitForTimeout(3000);
  await page.screenshot({ path: `${values.artifacts}/screenshots/PB-006-activation-attempt.png`, fullPage: true });
} catch (error) {
  await captureDiagnostics(page, error);
  throw error;
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

async function deployPromptTemplateMetadata(targetOrg) {
  try {
    const output = await sfJson([
      "project",
      "deploy",
      "start",
      "--source-dir",
      PROMPT_METADATA_SOURCE_DIR,
      "--target-org",
      targetOrg,
      "--api-version",
      PROMPT_METADATA_API_VERSION,
      "--wait",
      "30",
    ]);
    await writeJsonFile(`${values.artifacts}/prompt-builder-metadata-deploy.json`, {
      status: "success",
      source_dir: PROMPT_METADATA_SOURCE_DIR,
      output,
    });
    return { ok: true, output };
  } catch (error) {
    await writeJsonFile(`${values.artifacts}/prompt-builder-metadata-deploy.json`, {
      status: "failed",
      source_dir: PROMPT_METADATA_SOURCE_DIR,
      error: error.message,
    });
    console.warn(`Prompt template metadata deploy failed, falling back to UI automation: ${error.message}`);
    return { ok: false, error };
  }
}

async function waitForPrompt(targetOrg, options = {}) {
  const timeoutMs = options.timeoutMs || 30000;
  const started = Date.now();
  let lastResult = { records: [] };

  while (Date.now() - started < timeoutMs) {
    lastResult = await findPrompt(targetOrg);
    if (lastResult.records.length > 0 && (!options.active || isActive(lastResult.records[0]))) {
      return lastResult;
    }

    await new Promise((resolve) => setTimeout(resolve, 5000));
  }

  return lastResult;
}

async function openPromptBuilderAndClickNew(page) {
  const attempts = [];

  for (const path of PROMPT_BUILDER_HOME_PATHS) {
    const promptHomeUrl = await getOrgOpenUrl(values["target-org"], path);
    await page.goto(promptHomeUrl, { waitUntil: "domcontentloaded", timeout: 120000 });
    await page.waitForLoadState("networkidle", { timeout: 30000 }).catch(() => {});
    await page.waitForTimeout(5000);
    await page.screenshot({
      path: `${values.artifacts}/screenshots/PB-001-home-${path.includes("EinsteinPromptStudio") ? "studio" : "legacy"}.png`,
      fullPage: true,
    });

    attempts.push({
      path,
      current_url: page.url(),
      ...(await pageSummary(page)),
    });

    if (await clickIfPresent(page, [/new prompt template/i, /^new$/i, /create prompt template/i], { timeoutMs: 45000 })) {
      await writeJsonFile(`${values.artifacts}/prompt-builder-navigation.json`, { attempts });
      return;
    }
  }

  await writeJsonFile(`${values.artifacts}/prompt-builder-navigation.json`, { attempts });
  throw new Error(
    `Could not find a clickable Prompt Builder create control matching: /new prompt template/i, /^new$/i. Check PB-001 screenshots and prompt-builder-diagnostics.json for the rendered Salesforce page state.`,
  );
}

async function completeTemplateTypeStep(page) {
  await page.waitForTimeout(2000);
  const text = await bodyText(page);

  if (!/prompt template type|select.*template|template type/i.test(text)) {
    return;
  }

  await clickIfPresent(page, [/^flex$/i, /flex template/i], { timeoutMs: 15000 });
  await clickIfPresent(page, [/^next$/i, /continue/i], { timeoutMs: 15000 });
  await page.waitForTimeout(3000);
}

async function saveOrAdvancePromptTemplate(page) {
  const labels = [
    /save\s*&\s*preview/i,
    /save\s+and\s+preview/i,
    /^save$/i,
    /save.*activate/i,
    /save.*draft/i,
    /^create$/i,
    /create prompt template/i,
    /^finish$/i,
    /^done$/i,
    /^next$/i,
    /continue/i,
  ];

  for (let attempt = 1; attempt <= 4; attempt += 1) {
    await clickFirst(page, labels, { timeoutMs: 30000 });
    await page.waitForTimeout(5000);

    const prompt = await findPrompt(values["target-org"]);
    if (prompt.records.length > 0) {
      return;
    }
  }

  throw new Error("Prompt Builder save wizard did not create the expected AiPrompt record after four attempts.");
}

async function clickFirst(page, labels, options = {}) {
  const timeoutMs = options.timeoutMs || 60000;
  const started = Date.now();
  let lastError = null;

  while (Date.now() - started < timeoutMs) {
    for (const scope of pageScopes(page)) {
      for (const locator of clickableLocators(scope, labels)) {
        try {
          if (await clickVisibleEnabled(locator)) {
            return true;
          }
        } catch (error) {
          lastError = error;
        }
      }
    }

    await page.waitForTimeout(1000);
  }

  const suffix = lastError ? ` Last click error: ${lastError.message}` : "";
  throw new Error(`Could not find a clickable control matching: ${labels.join(", ")}.${suffix}`);
}

async function clickIfPresent(page, labels, options = {}) {
  try {
    return await clickFirst(page, labels, options);
  } catch {
    return false;
  }
}

async function fillFirst(page, labels, value, options = {}) {
  const timeoutMs = options.timeoutMs || 60000;
  const started = Date.now();
  let lastError = null;

  while (Date.now() - started < timeoutMs) {
    for (const scope of pageScopes(page)) {
      for (const locator of fieldLocators(scope, labels)) {
        try {
          if ((await locator.count()) === 0) {
            continue;
          }

          const field = locator.first();
          await field.fill(value, { timeout: 5000 });
          return true;
        } catch (error) {
          lastError = error;
        }
      }
    }

    await page.waitForTimeout(1000);
  }

  const suffix = lastError ? ` Last fill error: ${lastError.message}` : "";
  throw new Error(`Could not find a field matching: ${labels.join(", ")}.${suffix}`);
}

async function fillIfPresent(page, labels, value, options = {}) {
  try {
    return await fillFirst(page, labels, value, options);
  } catch {
    return false;
  }
}

function clickableLocators(scope, labels) {
  const locators = [];
  for (const label of labels) {
    locators.push(scope.getByRole("button", { name: label }));
    locators.push(scope.getByRole("link", { name: label }));
    locators.push(scope.getByTitle(label));
    locators.push(scope.locator("button, a, [role='button'], input[type='button'], input[type='submit']").filter({ hasText: label }));
  }
  return locators;
}

async function clickVisibleEnabled(locator) {
  const count = Math.min(await locator.count(), 25);

  for (let index = 0; index < count; index += 1) {
    const candidate = locator.nth(index);

    if (!(await candidate.isVisible().catch(() => false))) {
      continue;
    }

    if (await candidate.isDisabled().catch(() => false)) {
      continue;
    }

    await candidate.scrollIntoViewIfNeeded({ timeout: 3000 }).catch(() => {});
    await candidate.click({ timeout: 5000 });
    return true;
  }

  return false;
}

function fieldLocators(scope, labels) {
  const locators = [];
  for (const label of labels) {
    locators.push(scope.getByLabel(label));
    locators.push(scope.getByPlaceholder(label));
    locators.push(scope.locator("input, textarea, [contenteditable='true']").filter({ hasText: label }));
  }

  if (labelsMatch(labels, "prompt instructions system")) {
    locators.push(scope.locator("textarea").last());
    locators.push(scope.locator("[contenteditable='true']").last());
  }

  return locators;
}

function labelsMatch(labels, text) {
  return labels.some((label) => (label instanceof RegExp ? label.test(text) : text.includes(String(label))));
}

function pageScopes(page) {
  return [...new Set([page, ...page.frames()])];
}

async function bodyText(page) {
  return page.locator("body").innerText({ timeout: 10000 }).catch(() => "");
}

async function pageSummary(page) {
  const buttons = await collectVisibleText(page, "button, [role='button'], input[type='button'], input[type='submit']");
  const links = await collectVisibleText(page, "a");
  return {
    title: await page.title().catch(() => ""),
    body_sample: (await bodyText(page)).slice(0, 2500),
    buttons,
    links,
  };
}

async function collectVisibleText(page, selector) {
  return page
    .locator(selector)
    .evaluateAll((elements) =>
      elements
        .filter((element) => {
          const rect = element.getBoundingClientRect();
          return rect.width > 0 && rect.height > 0;
        })
        .map((element) => element.innerText || element.value || element.getAttribute("aria-label") || element.getAttribute("title") || "")
        .map((value) => value.trim())
        .filter(Boolean)
        .slice(0, 50),
    )
    .catch(() => []);
}

async function captureDiagnostics(page, error) {
  await page.screenshot({ path: `${values.artifacts}/screenshots/PB-error.png`, fullPage: true }).catch(() => {});
  await writeJsonFile(`${values.artifacts}/prompt-builder-diagnostics.json`, {
    error: error.message,
    current_url: page.url(),
    ...(await pageSummary(page)),
  });
}
