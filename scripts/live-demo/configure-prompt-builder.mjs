import { parseArgs } from "node:util";

import { ensureDir, getOrgOpenUrl, querySalesforce, writeJsonFile } from "./lib.mjs";

const PROMPT_API_NAME = "IST_Inventory_Recommendation";
const promptTemplate = {
  name: "IST Inventory Recommendation",
  apiName: PROMPT_API_NAME,
  description:
    "Analyzes inventory records and generates actionable recommendations following DEA compliance and stock level rules.",
  text: `You are a US retail pharmacy inventory analyst assistant.
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

OUTPUT ONLY THE RECOMMENDATION TEXT.`,
};

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
    configured_by: "existing_active_prompt",
    prompt: before.records[0],
  });
  console.log(`${PROMPT_API_NAME} already exists and is active`);
  process.exit(0);
}

const { chromium } = await import("playwright");
const browser = await chromium.launch({ headless: true });
const page = await browser.newPage({ viewport: { width: 1440, height: 1000 } });
const captures = [];
let uiResult;

try {
  uiResult =
    before.records.length > 0
      ? await activateExistingPromptBuilderTemplate(page, captures)
      : await createPromptBuilderTemplate(page, captures);
} catch (error) {
  await captureDiagnostics(page, error, captures);
  throw error;
} finally {
  await browser.close();
}

const after = await findPrompt(values["target-org"]);
const active = after.records.length > 0 && isActive(after.records[0]);

await writeJsonFile(`${values.artifacts}/prompt-builder.json`, {
  status: active ? "active" : "not_active",
  configured_by: "prompt_builder_ui",
  ui_result: uiResult,
  query_error: after.error,
  prompt: after.records[0] || null,
  captures,
});

if (!active) {
  throw new Error(
    `Prompt Builder template ${PROMPT_API_NAME} is not active. ${
      uiResult?.blocker || "Setup evidence screenshots were captured."
    }`,
  );
}

console.log(`${PROMPT_API_NAME} created and active through Prompt Builder UI`);

async function findPrompt(targetOrg) {
  try {
    const records = await querySalesforce(
      targetOrg,
      `SELECT Id, DeveloperName, MasterLabel, ActiveVersion FROM AiPrompt WHERE DeveloperName = '${PROMPT_API_NAME}' OR MasterLabel = '${promptTemplate.name}' ORDER BY CreatedDate DESC LIMIT 1`,
    );
    return { records };
  } catch (error) {
    return { records: [], error: error.message };
  }
}

function isActive(record) {
  return Number(record.ActiveVersion || 0) > 0;
}

async function createPromptBuilderTemplate(page, captures) {
  const result = {
    attempted: true,
    promptCreated: false,
    promptActivated: false,
    route: null,
    blocker: null,
    observations: [],
  };

  await openLightningPath(page, "/lightning/setup/SetupOneHome/home", 6000);
  await capture(page, "PB-001_SetupHome.png", "Setup home before Prompt Builder search.", captures);

  const searchedTopSetup =
    (await fillFirstUi(page, ["Search Setup"], "Prompt Builder")) ||
    (await fillFirstUi(page, ["Search Setup"], "Prompt Templates"));
  await page.keyboard.press("Enter").catch(() => {});
  await page.waitForTimeout(4000);
  await capture(page, "PB-002_SetupSearchPromptBuilder.png", "Top Setup search for Prompt Builder.", captures);

  if (searchedTopSetup) {
    await clickFirstText(page, ["Prompt Builder", "Prompt Templates"], 4000);
    await waitForLightning(page, 6000);
  }

  const searchedQuickFind =
    (await fillFirstUi(page, ["Quick Find"], "Prompt Builder")) ||
    (await fillFirstUi(page, ["Quick Find"], "Prompt Templates"));
  await page.waitForTimeout(2500);
  await capture(page, "PB-003_SetupQuickFindPromptBuilder.png", "Left Quick Find search for Prompt Builder.", captures);

  if (searchedQuickFind) {
    await clickFirstText(page, ["Prompt Builder", "Prompt Templates"], 4000);
    await waitForLightning(page, 6000);
  }

  const directRoutes = [
    "/lightning/setup/EinsteinPromptStudio/home",
    "/lightning/setup/PromptBuilder/home",
    "/lightning/setup/EinsteinGPTPromptTemplates/home",
    "/lightning/setup/PromptTemplates/home",
    "/lightning/setup/GenAiPromptTemplate/home",
  ];

  let text = await allFrameText(page);
  const isValidPromptBuilder = () =>
    /New Prompt Template|Prompt Templates|Prompt Template Workspace|Manage Prompt Templates/i.test(text) &&
    !/Page not found|page you requested was not found|This page doesn't exist|Page Not Available/i.test(text);

  for (let index = 0; index < directRoutes.length; index += 1) {
    const route = directRoutes[index];
    if (isValidPromptBuilder()) {
      break;
    }

    await openLightningPath(page, route, 5500);
    text = await allFrameText(page);
    result.observations.push({ route, text: text.slice(0, 1000) });
    await capture(
      page,
      `PB-004_${String(index + 1).padStart(2, "0")}_DirectPromptBuilderRoute.png`,
      `Prompt Builder direct route candidate: ${route}`,
      captures,
    );
  }

  result.route = page.url();
  await capture(page, "PB-005_PromptBuilderLanding.png", "Prompt Builder landing page candidate.", captures);
  text = await allFrameText(page);

  if (!isValidPromptBuilder()) {
    result.blocker =
      "Prompt Builder was not available from Setup Quick Find or the known direct setup routes in this scratch org.";
    return result;
  }

  const clickedNew = await clickFirstText(page, ["New Prompt Template", "New"], 8000);
  await waitForLightning(page, 4500);
  await capture(page, "PB-006_NewPromptTemplateAttempt.png", "New prompt template attempt.", captures);

  if (!clickedNew) {
    result.blocker = "No New Prompt Template action was available in this scratch org UI.";
    return result;
  }

  const selectedFieldGeneration = await selectPromptTemplateType(page);
  let detailsFilled = await fillPromptTemplateDetails(page);
  if (!detailsFilled) {
    await clickFirstText(page, ["Next", "Continue"], 6000);
    await waitForLightning(page, 3000);
    detailsFilled = await fillPromptTemplateDetails(page);
  }

  if (!detailsFilled) {
    result.blocker = "Prompt template name/details fields did not appear after selecting the template type.";
    return result;
  }

  if (selectedFieldGeneration) {
    await chooseComboboxValue(page, ["Object", "Related Entity", "Input Object"], "Inventory Position", 8000);
    await chooseComboboxValue(page, ["Field", "Target Field"], "Recommendation Preview", 8000);
  } else {
    await addFlexInventoryInput(page, captures);
  }

  await capture(page, "PB-009_PromptTemplateDetailsFilled.png", "Prompt template details after automated fill attempt.", captures);

  await clickFirstText(page, ["Next", "Continue"], 8000);
  await waitForLightning(page, 5000);
  await fillFirstTextArea(page, promptTemplate.text, 8000);
  await capture(page, "PB-010_PromptWorkspaceFilled.png", "Prompt workspace after system prompt fill attempt.", captures);

  await clickFirstText(page, ["Save & Preview", "Save and Preview", "Save"], 8000);
  await waitForLightning(page, 8000);
  await capture(page, "PB-011_PromptSaveResult.png", "Prompt template save result.", captures);

  text = await allFrameText(page);
  result.promptCreated =
    /IST Inventory Recommendation|IST_Inventory_Recommendation|created successfully|saved|Version 1/i.test(text) &&
    !/Template Errors|Complete this field|not recognized|Select an object|deprecated|not active/i.test(text);

  if (!result.promptCreated) {
    const prompt = await findPrompt(values["target-org"]);
    result.promptCreated = prompt.records.length > 0;
  }

  if (result.promptCreated) {
    const activation = await activateOpenPromptTemplate(page, captures, "PB-012_PromptActivateResult.png", "PB-013_PromptActivateFinalState.png");
    result.promptActivated = activation.promptActivated;
    result.blocker = activation.blocker;
  }

  if (!result.promptCreated) {
    result.blocker = (await allFrameText(page)).slice(0, 1500);
  }

  return result;
}

async function fillPromptTemplateDetails(page) {
  const nameFilled = await fillFirstUi(page, ["Prompt Template Name", "Template Name", "Name"], promptTemplate.name, 8000);
  await fillFirstUi(page, ["API Name", "Prompt Template API Name", "Developer Name"], promptTemplate.apiName, 5000);
  await fillFirstUi(page, ["Template Description", "Description"], promptTemplate.description, 8000);
  return nameFilled;
}

async function selectPromptTemplateType(page) {
  return (
    (await chooseComboboxValue(page, ["Prompt Template Type", "Template Type"], "Field Generation", 6000)) ||
    (await clickFirstText(page, ["Field Generation"], 6000))
  );
}

async function addFlexInventoryInput(page, captures) {
  const clickedAdd = await clickFirstText(page, ["Add"], 4000);
  await page.waitForTimeout(1200);
  await capture(page, "PB-007_FlexInputAddAttempt.png", "Flex template Inventory Position input add attempt.", captures);

  if (!clickedAdd) {
    return false;
  }

  await fillFirstUi(page, ["Input Name", "Name"], "Inventory_Position__c", 5000);
  await chooseComboboxValue(page, ["Source Type", "Input Type"], "Object", 5000);
  await chooseComboboxValue(page, ["Object"], "Inventory Position", 5000);
  await capture(page, "PB-008_FlexInputConfigured.png", "Flex template Inventory Position input configuration attempt.", captures);
  return true;
}

async function activateExistingPromptBuilderTemplate(page, captures) {
  const result = {
    attempted: true,
    promptCreated: true,
    promptActivated: false,
    route: null,
    blocker: null,
    observations: [],
  };

  await openLightningPath(page, "/lightning/setup/EinsteinPromptStudio/home", 7000);
  await capture(page, "PB-ACT-001_PromptBuilderHome.png", "Prompt Builder home before activation search.", captures);

  const searched =
    (await fillFirstUi(page, ["Search templates", "Search templates..."], promptTemplate.name, 5000)) ||
    (await fillFirstUi(page, ["Search"], promptTemplate.name, 5000));
  await page.keyboard.press("Enter").catch(() => {});
  await page.waitForTimeout(3500);
  await capture(page, "PB-ACT-002_TemplateSearch.png", "Prompt Builder template search for existing IST template.", captures);

  if (!searched) {
    result.blocker = "Could not find the Prompt Builder template search box.";
    return result;
  }

  const opened = await clickFirstText(page, [promptTemplate.name, PROMPT_API_NAME], 7000);
  await waitForLightning(page, 7000);
  await capture(page, "PB-ACT-003_TemplateOpened.png", "Existing IST prompt template opened.", captures);

  if (!opened) {
    result.blocker = "Could not open the saved IST Inventory Recommendation template from the Prompt Builder list.";
    return result;
  }

  const activation = await activateOpenPromptTemplate(
    page,
    captures,
    "PB-ACT-004_ActivateClicked.png",
    "PB-ACT-005_ActivationFinalState.png",
  );
  result.route = page.url();
  result.promptActivated = activation.promptActivated;
  result.blocker = activation.blocker;
  return result;
}

async function activateOpenPromptTemplate(page, captures, clickedFile, finalFile) {
  await page.keyboard.press("Escape").catch(() => {});
  await page.waitForTimeout(500);
  const clickedActivate = await clickExactButton(page, "Activate", 8000);
  await waitForLightning(page, 5000);
  await capture(page, clickedFile, "Prompt template Activate click result.", captures);

  if (clickedActivate) {
    await clickExactButton(page, "Activate", 6000) ||
      (await clickExactButton(page, "Confirm", 6000)) ||
      (await clickExactButton(page, "Save", 6000));
    await waitForLightning(page, 7000);
  }

  await capture(page, finalFile, "Prompt template final activation state.", captures);
  const text = await allFrameText(page);
  const activateButtonCount = await page.locator('button:has-text("Activate")').count().catch(() => 0);
  const promptActivated =
    /Deactivate|Version Activated|Activated successfully|Version 1 \(Active\)|Active/i.test(text) ||
    (clickedActivate && activateButtonCount === 0);

  return {
    promptActivated,
    blocker: promptActivated ? null : text.slice(0, 1500),
  };
}

async function openLightningPath(page, path, waitMs) {
  const url = await getOrgOpenUrl(values["target-org"], path);
  await page.goto(url, { waitUntil: "load", timeout: 120000 });
  await waitForLightning(page, waitMs);
}

async function waitForLightning(page, waitMs = 7000) {
  await page.waitForLoadState("load", { timeout: 90000 }).catch(() => {});
  await page.waitForLoadState("networkidle", { timeout: 30000 }).catch(() => {});
  await page.waitForTimeout(waitMs);
}

async function capture(page, fileName, note, captures) {
  const outputPath = `${values.artifacts}/screenshots/${fileName}`;
  await page.screenshot({ path: outputPath, fullPage: true });
  captures.push({ file: outputPath, note, url: page.url() });
  console.log(`Captured ${fileName}: ${note}`);
  return outputPath;
}

async function allFrameText(page) {
  const parts = [];
  for (const frame of page.frames()) {
    try {
      const text = await frame.evaluate(() => document.body?.innerText || "");
      if (text.trim()) {
        parts.push(text);
      }
    } catch {
      // Cross-origin or detached frames can be ignored for text evidence.
    }
  }
  return parts.join("\n").replace(/\s+/g, " ").trim();
}

async function clickFirstText(page, labels, timeoutMs = 2500) {
  for (const frame of page.frames()) {
    for (const label of labels) {
      const candidates = [
        frame.getByRole("button", { name: label, exact: false }),
        frame.getByRole("link", { name: label, exact: false }),
        frame.getByText(label, { exact: false }),
      ];

      for (const locator of candidates) {
        try {
          if (await clickVisibleLocator(locator, timeoutMs)) {
            return true;
          }
        } catch {
          // Try the next label/locator.
        }
      }
    }
  }
  return false;
}

async function clickExactButton(page, label, timeoutMs = 5000) {
  for (const frame of page.frames()) {
    const candidates = [
      frame.getByRole("button", { name: label, exact: true }),
      frame.locator(`button:has-text("${label}")`),
      frame.locator(`lightning-button:has-text("${label}") button`),
    ];

    for (const locator of candidates) {
      try {
        const count = Math.min(await locator.count(), 10);
        for (let index = 0; index < count; index += 1) {
          const candidate = locator.nth(index);
          if (!(await candidate.isVisible().catch(() => false))) {
            continue;
          }
          await candidate.click({ force: true, timeout: timeoutMs });
          await page.waitForTimeout(1000);
          return true;
        }
      } catch {
        // Try the next button candidate.
      }
    }
  }
  return false;
}

async function clickVisibleLocator(locator, timeoutMs) {
  const count = Math.min(await locator.count(), 20);
  for (let index = 0; index < count; index += 1) {
    const candidate = locator.nth(index);
    if (!(await candidate.isVisible().catch(() => false))) {
      continue;
    }
    if (await candidate.isDisabled().catch(() => false)) {
      continue;
    }
    await candidate.scrollIntoViewIfNeeded({ timeout: 2000 }).catch(() => {});
    await candidate.click({ timeout: timeoutMs });
    await new Promise((resolve) => setTimeout(resolve, 800));
    return true;
  }
  return false;
}

async function fillFirstUi(page, labels, value, timeoutMs = 2500) {
  for (const frame of page.frames()) {
    for (const label of labels) {
      const candidates = [
        frame.getByLabel(label, { exact: false }),
        frame.getByPlaceholder(label, { exact: false }),
      ];

      for (const locator of candidates) {
        try {
          const count = await locator.count();
          if (count > 0) {
            await locator.first().fill(value, { timeout: timeoutMs });
            return true;
          }
        } catch {
          // Try the next field.
        }
      }
    }
  }
  return false;
}

async function fillFirstTextArea(page, value, timeoutMs = 2500) {
  for (const frame of page.frames()) {
    const candidates = [
      frame.locator("textarea"),
      frame.locator("[contenteditable='true']"),
      frame.locator(".ql-editor"),
      frame.locator("lightning-textarea textarea"),
    ];

    for (const locator of candidates) {
      try {
        const count = await locator.count();
        if (count > 0) {
          await locator.first().fill(value, { timeout: timeoutMs });
          return true;
        }
      } catch {
        // Try the next editor.
      }
    }
  }
  return false;
}

async function chooseComboboxValue(page, labels, value, timeoutMs = 2500) {
  async function clickVisibleOption() {
    for (const frame of page.frames()) {
      const optionLocators = [
        frame.locator(`lightning-base-combobox-item:has-text("${value}")`),
        frame.locator(`[role="option"]:has-text("${value}")`),
        frame.getByRole("option", { name: value, exact: false }),
        frame.getByText(value, { exact: true }),
      ];

      for (const option of optionLocators) {
        try {
          if (await clickVisibleLocator(option, timeoutMs)) {
            await page.waitForTimeout(800);
            return true;
          }
        } catch {
          // Try the next visible option candidate.
        }
      }
    }
    return false;
  }

  for (const frame of page.frames()) {
    for (const label of labels) {
      const candidates = [
        frame.getByRole("combobox", { name: label, exact: false }),
        frame.getByLabel(label, { exact: false }),
        frame.locator(`lightning-combobox:has-text("${label}")`),
        frame.locator(`select[aria-label*="${label}"]`),
      ];

      for (const locator of candidates) {
        try {
          const count = await locator.count();
          if (count > 0) {
            await locator.first().click({ timeout: timeoutMs });
            await page.waitForTimeout(800);
            try {
              await locator.first().fill(value, { timeout: 1000 });
              await page.waitForTimeout(1000);
            } catch {
              try {
                await page.keyboard.type(value, { delay: 20 });
                await page.waitForTimeout(1000);
              } catch {
                // Some combobox buttons cannot accept text; rely on visible options.
              }
            }
            if ((await clickVisibleOption()) || (await clickFirstText(page, [value], timeoutMs))) {
              return true;
            }
          }
        } catch {
          // Try the next combobox candidate.
        }
      }
    }
  }

  return false;
}

async function captureDiagnostics(page, error, captures) {
  await capture(page, "PB-error.png", `Prompt Builder automation failed: ${error.message}`, captures).catch(() => {});
  await writeJsonFile(`${values.artifacts}/prompt-builder-diagnostics.json`, {
    error: error.message,
    current_url: page.url(),
    body_sample: (await allFrameText(page)).slice(0, 2500),
    captures,
  });
}
