import { existsSync } from "node:fs";
import { readFile } from "node:fs/promises";
import { basename } from "node:path";
import { parseArgs } from "node:util";

import { githubRunUrl, readDispatchPayload, readJsonFile } from "./lib.mjs";

const { values } = parseArgs({
  options: {
    artifacts: { type: "string" },
    credentials: { type: "string" },
    status: { type: "string", default: "unknown" },
    "duration-days": { type: "string", default: "30" },
  },
});

if (!values.artifacts) {
  throw new Error("Usage: node send-mailtrap-email.mjs --artifacts <dir> --credentials <runner-temp-file> --status <status>");
}

const tokenSource = process.env.MAILTRAP_TOKEN ? "MAILTRAP_TOKEN" : "MAILTRAP_API_TOKEN";
const token = normalizeMailtrapToken(process.env.MAILTRAP_TOKEN || process.env.MAILTRAP_API_TOKEN);
if (!token) {
  console.warn("MAILTRAP_TOKEN is not configured; skipping email send");
  process.exit(0);
}

const payload = await readDispatchPayload();
const credentials = values.credentials && existsSync(values.credentials)
  ? await readJsonFile(values.credentials)
  : null;
const scenarioResults = existsSync(`${values.artifacts}/scenario-results.json`)
  ? await readJsonFile(`${values.artifacts}/scenario-results.json`)
  : null;
const scratchSelection = existsSync(`${values.artifacts}/scratch-org-selection.json`)
  ? await readJsonFile(`${values.artifacts}/scratch-org-selection.json`)
  : null;

const runUrl = githubRunUrl();
const artifactUrl = process.env.ARTIFACT_URL || runUrl;
const status = String(values.status || "unknown").toLowerCase();
const success = status === "success" && credentials;
const subject = success
  ? "AgentforcePharmaGrid demo org is ready"
  : "AgentforcePharmaGrid demo setup needs attention";

const text = buildText({
  payload,
  credentials,
  scenarioResults,
  scratchSelection,
  runUrl,
  artifactUrl,
  success,
  durationDays: values["duration-days"],
});
const html = buildHtml({
  payload,
  credentials,
  scenarioResults,
  scratchSelection,
  runUrl,
  artifactUrl,
  success,
  durationDays: values["duration-days"],
});
const attachments = await buildAttachments(values.artifacts);

const response = await fetch("https://send.api.mailtrap.io/api/send", {
  method: "POST",
  headers: {
    "api-token": token,
    "content-type": "application/json",
  },
  body: JSON.stringify({
    from: {
      email: process.env.MAILTRAP_FROM_EMAIL || "demo@agentforcepharmagrid.example",
      name: process.env.MAILTRAP_FROM_NAME || "AgentforcePharmaGrid Demo",
    },
    to: [
      {
        email: payload.email,
        name: payload.name,
      },
    ],
    subject,
    text,
    html,
    attachments,
  }),
});

if (!response.ok) {
  const body = await response.text();
  if (response.status === 401) {
    throw new Error(
      `Mailtrap rejected ${tokenSource} with HTTP 401. Use a Mailtrap Email Sending API token from Sending Domains > Integration > API, make sure it has send permission for the MAILTRAP_FROM_EMAIL domain, and store only the raw token value without "Bearer ". Token diagnostics: ${mailtrapTokenDiagnostics(token)}. Response: ${body}`,
    );
  }

  throw new Error(`Mailtrap send failed: HTTP ${response.status} ${body}`);
}

console.log(`Mailtrap email sent to ${payload.email}`);

function buildText({
  payload,
  credentials,
  scenarioResults,
  scratchSelection,
  runUrl,
  artifactUrl,
  success,
  durationDays,
}) {
  const lines = [
    `Hi ${payload.name},`,
    "",
    success
      ? `Your AgentforcePharmaGrid 30-day scratch org is ready. It expires on ${credentials.expires_at}.`
      : "The live demo run did not complete successfully. Setup evidence was uploaded so the failure can be inspected honestly.",
    "",
  ];

  if (credentials) {
    lines.push(
      "Scratch org credentials:",
      `Login URL: ${credentials.login_url}`,
      `Username: ${credentials.username}`,
      `Password: ${credentials.password}`,
      `Expiration: ${credentials.expires_at}`,
      "",
    );
  }

  if (scenarioResults) {
    lines.push(
      `Scenario summary: ${scenarioResults.passed || 0} passed, ${scenarioResults.failed || 0} failed.`,
      "",
    );
  }

  if (scratchSelection) {
    lines.push(
      `Scratch org mode: requested ${scratchSelection.requested_mode}, ${scratchSelection.effective_mode}.`,
      scratchSelection.fallback_reason ? `Fallback reason: ${scratchSelection.fallback_reason}` : "",
      "",
    );
  }

  lines.push(
    `Artifacts: ${artifactUrl}`,
    `Run log: ${runUrl}`,
    "Repository: https://github.com/jayavardhan-raju/AgentforcePharmaGrid",
    "Documentation: https://jayavardhan-raju.github.io/AgentforcePharmaGrid/",
    "",
    `Scratch org duration is fixed at ${durationDays} days. Your Salesforce Dev Hub auth URL is not included in this email, logs, or artifacts.`,
  );

  return lines.join("\n");
}

function buildHtml({
  payload,
  credentials,
  scenarioResults,
  scratchSelection,
  runUrl,
  artifactUrl,
  success,
  durationDays,
}) {
  const credentialRows = credentials
    ? `
      <h2>Scratch Org Credentials</h2>
      <table>
        <tr><th align="left">Login URL</th><td><a href="${escapeHtml(credentials.login_url)}">${escapeHtml(credentials.login_url)}</a></td></tr>
        <tr><th align="left">Username</th><td>${escapeHtml(credentials.username)}</td></tr>
        <tr><th align="left">Password</th><td><code>${escapeHtml(credentials.password)}</code></td></tr>
        <tr><th align="left">Expiration</th><td>${escapeHtml(credentials.expires_at)}</td></tr>
      </table>`
    : "";

  const scenarios = scenarioResults
    ? `<p><strong>Scenario summary:</strong> ${scenarioResults.passed || 0} passed, ${scenarioResults.failed || 0} failed.</p>`
    : "";
  const scratchMode = scratchSelection
    ? `<p><strong>Scratch org mode:</strong> requested ${escapeHtml(scratchSelection.requested_mode)}, ${escapeHtml(scratchSelection.effective_mode)}.${
        scratchSelection.fallback_reason ? ` ${escapeHtml(scratchSelection.fallback_reason)}` : ""
      }</p>`
    : "";

  return `
    <p>Hi ${escapeHtml(payload.name)},</p>
    <p>${
      success
        ? `Your AgentforcePharmaGrid 30-day scratch org is ready. It expires on ${escapeHtml(credentials.expires_at)}.`
        : "The live demo run did not complete successfully. Setup evidence was uploaded so the failure can be inspected honestly."
    }</p>
    ${credentialRows}
    ${scenarios}
    ${scratchMode}
    <p><a href="${escapeHtml(artifactUrl)}">Open the uploaded artifacts</a></p>
    <p><a href="${escapeHtml(runUrl)}">Open the GitHub Actions run log</a></p>
    <p>
      <a href="https://github.com/jayavardhan-raju/AgentforcePharmaGrid">Repository</a> |
      <a href="https://jayavardhan-raju.github.io/AgentforcePharmaGrid/">Documentation</a>
    </p>
    <p>Scratch org duration is fixed at ${escapeHtml(durationDays)} days. The Salesforce Dev Hub auth URL is not included in this email, logs, or artifacts.</p>
  `;
}

async function buildAttachments(artifactDir) {
  const gifPath = `${artifactDir}/agentforce-pharmagrid-demo.gif`;
  if (!existsSync(gifPath)) {
    return [];
  }

  return [
    {
      filename: basename(gifPath),
      content: (await readFile(gifPath)).toString("base64"),
      type: "image/gif",
      disposition: "attachment",
    },
  ];
}

function escapeHtml(value) {
  return String(value || "")
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#39;");
}

function normalizeMailtrapToken(value) {
  return String(value || "")
    .trim()
    .replace(/^Bearer\s+/i, "")
    .trim();
}

function mailtrapTokenDiagnostics(value) {
  const token = String(value || "");
  return `length=${token.length}, prefix=${token.slice(0, 4) || "empty"}, suffix=${token.slice(-4) || "empty"}`;
}
