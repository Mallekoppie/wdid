#!/usr/bin/env node
/*
 * End-to-end smoke test against a running wdid service.
 *
 * It drives the embedded Flutter app in a real Chromium browser through the
 * startup auth gate and the full loop: capture, personal review, manager
 * check-in + finalize, export/copy prompt, and backup/restore. Flutter web
 * renders to a canvas, so the script enables the semantics tree and drives the
 * accessibility DOM.
 *
 * Usage:
 *   npm install --no-save playwright          # or point NODE_PATH at an install
 *   WDID_BASE_URL=http://127.0.0.1:19101 \
 *   WDID_SMOKE_EMAIL=smoke@example.com \
 *   WDID_SMOKE_PASSWORD=smoke-password-123 \
 *   WDID_SMOKE_BOOTSTRAP_SECRET=smoke-bootstrap-secret \
 *   node scripts/browser-smoke.cjs
 *
 * A fresh database takes the bootstrap path (first admin account); once that
 * account exists the same script signs in through the normal login form.
 *
 * Set WDID_SMOKE_SHOTS=1 to write screenshots next to the failure/step output.
 */
'use strict';

const { chromium } = require('playwright');
const fs = require('node:fs');
const path = require('node:path');

const BASE = process.env.WDID_BASE_URL || 'http://127.0.0.1:9101';
const EMAIL = process.env.WDID_SMOKE_EMAIL || 'smoke@example.com';
const PASSWORD = process.env.WDID_SMOKE_PASSWORD || 'smoke-password-123';
const BOOTSTRAP =
  process.env.WDID_SMOKE_BOOTSTRAP_SECRET || 'smoke-bootstrap-secret';
const DISPLAY_NAME = process.env.WDID_SMOKE_DISPLAY_NAME || 'Smoke Admin';
const SHOTS = process.env.WDID_SMOKE_SHOTS === '1';
const SHOT_DIR = process.env.WDID_SMOKE_SHOT_DIR || '/tmp/wdid-smoke-shots';

const grpcWeb = [];

function log(message) {
  console.log(`[smoke] ${message}`);
}

function fail(message) {
  throw new Error(message);
}

function escapeRegExp(value) {
  return value.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

/// Flutter exposes semantics text in aria-label or the node's text content
/// depending on the widget. Read whichever one the framework chose.
async function accessibleName(locator) {
  const label = await locator.getAttribute('aria-label');
  if (label && label.trim()) return label.trim();
  const text = await locator.textContent();
  return (text || '').trim();
}

async function expectCount(locator, expected, label, timeout = 15000) {
  if (expected === '>0') {
    // Flutter renders asynchronously after a route change or an RPC. The
    // semantics root deliberately has opacity 0, so wait for attachment, not
    // visual visibility.
    await locator
      .first()
      .waitFor({ state: 'attached', timeout })
      .catch(() => {});
  }
  const count = await locator.count();
  if (expected === '>0' ? count === 0 : count !== expected) {
    fail(`${label}: expected ${expected}, found ${count}`);
  }
  return count;
}

/// Flutter puts some text in a semantics node's aria-label rather than in a
/// text node. Poll both so an assertion is not brittle about which one the
/// framework chose.
async function waitForTextOrLabel(page, pattern, label, timeout = 15000) {
  const source = pattern.source;
  const started = Date.now();
  while (Date.now() - started < timeout) {
    const found = await page.evaluate((expression) => {
      const regex = new RegExp(expression);
      if (regex.test(document.body.textContent || '')) return true;
      for (const node of document.querySelectorAll('[aria-label]')) {
        if (regex.test(node.getAttribute('aria-label') || '')) return true;
      }
      return false;
    }, source);
    if (found) return;
    await page.waitForTimeout(400);
  }
  fail(`${label}: no text or aria-label matched ${pattern}`);
}

async function shot(page, name) {
  if (!SHOTS) return;
  fs.mkdirSync(SHOT_DIR, { recursive: true });
  await page.screenshot({ path: path.join(SHOT_DIR, `${name}.png`) });
}

async function enableSemantics(page) {
  await page.evaluate(() => {
    document.querySelector('flt-semantics-placeholder')?.click();
  });
  await page.waitForTimeout(800);
}

/// The config fetch decides whether the gate is a bootstrap form or a normal
/// sign-in. Both render asynchronously, so wait for either instead of counting
/// once after a fixed delay.
async function waitForAuthGate(page, timeout = 15000) {
  await enableSemantics(page);
  const bootstrapInput = page.locator('input[aria-label="Bootstrap secret"]');
  const signInButton = page.getByRole('button', {
    name: 'Sign in',
    exact: true,
  });
  const deadline = Date.now() + timeout;
  while (Date.now() < deadline) {
    if ((await bootstrapInput.count()) > 0) return 'bootstrap';
    if ((await signInButton.count()) > 0) return 'signin';
    await page.waitForTimeout(250);
  }
  fail(
    'auth gate: neither the bootstrap form nor the Sign in button appeared',
  );
}

async function signIn(page) {
  await page.goto(`${BASE}/`, { waitUntil: 'load' });
  await page.waitForTimeout(2500);

  const gate = await waitForAuthGate(page);
  if (gate === 'bootstrap') {
    log('auth gate: bootstrap first admin account');
    await page.locator('input[aria-label="Display name"]').fill(DISPLAY_NAME);
    await page.locator('input[aria-label="Email"]').first().fill(EMAIL);
    await page.locator('input[aria-label="Password"]').first().fill(PASSWORD);
    await page
      .locator('input[aria-label="Bootstrap secret"]')
      .fill(BOOTSTRAP);
    await page.getByRole('button', { name: 'Create admin account' }).click();
  } else {
    log('auth gate: sign in with the existing account');
    await page.locator('input[aria-label="Email"]').first().fill(EMAIL);
    await page.locator('input[aria-label="Password"]').first().fill(PASSWORD);
    await page.getByRole('button', { name: 'Sign in', exact: true }).click();
  }

  await page
    .waitForURL(/#\/today/, { timeout: 15000 })
    .catch(() => fail(`sign-in did not reach Today: ${page.url()}`));
  await waitForTextOrLabel(page, /Start a timer/, 'Today after sign-in');
  await shot(page, '01-today');
}

async function captureEntry(page) {
  log('capture: quick-capture one work entry');

  // The quick-capture form reads the taxonomy at first build. Make the
  // category explicit so the capture cannot race the taxonomy load after a
  // sign-in reload.
  const quick = page.locator(
    'flt-semantics[role="group"][aria-label*="Enter saves"]',
  );
  await quick.first().waitFor({ state: 'attached', timeout: 15000 }).catch(() => {});
  const categoryButton = quick
    .getByRole('button')
    .filter({ hasNotText: 'No subcategory' })
    .filter({ hasNotText: 'Add' })
    .first();
  if (!(await categoryButton.count())) {
    fail('capture: no category selector was found');
  }

  // Choose whichever category the instance actually has; the smoke test must
  // not assume the seed taxonomy. Remember its name for the confirmation.
  await categoryButton.click();
  await page.waitForTimeout(500);
  const categoryOptions = page.getByRole('menuitem');
  await categoryOptions
    .first()
    .waitFor({ state: 'attached', timeout: 5000 })
    .catch(() => {});
  if (!(await categoryOptions.count())) {
    fail('capture: no category could be selected from the menu');
  }
  const categoryOption = categoryOptions.first();
  const categoryName = await accessibleName(categoryOption);
  if (!categoryName) {
    fail('capture: could not read the selected category name');
  }
  await categoryOption.click();
  // Wait for the menu to close before touching the form; a click landing on
  // the dismissing overlay would silently drop the capture.
  await categoryOptions
    .first()
    .waitFor({ state: 'detached', timeout: 3000 })
    .catch(() => {});
  await page.waitForTimeout(400);

  await page
    .locator('input[aria-label="What did you do?"]')
    .fill('Smoke capture entry');
  await page.getByRole('button', { name: 'Add', exact: true }).click();
  await page.waitForTimeout(1500);
  await waitForTextOrLabel(
    page,
    new RegExp(`Logged .*to ${escapeRegExp(categoryName)}`),
    'capture confirmation',
  );

  await page.goto(`${BASE}/#/log`, { waitUntil: 'load' });
  await page.waitForTimeout(2000);
  await waitForTextOrLabel(
    page,
    /Smoke capture entry/,
    'captured entry in the log',
  );
  log('capture: entry visible in Log');
  await shot(page, '02-log');
}

async function personalReview(page) {
  log('personal review: open the live review and save it');
  await page.goto(`${BASE}/#/checkins`, { waitUntil: 'load' });
  await page.waitForTimeout(2000);
  await page.getByRole('button', { name: 'New review' }).click();
  await page.waitForTimeout(1000);
  await page.getByRole('button', { name: 'Open review' }).click();
  await page.waitForTimeout(2500);
  if (!page.url().includes('/checkins/review')) {
    fail(`review route did not open: ${page.url()}`);
  }
  const notes = page.locator(
    'textarea[aria-label="Focus notes (optional)"], input[aria-label="Focus notes (optional)"]',
  );
  await notes.first().fill('Live smoke reflection');
  await page.getByRole('button', { name: 'Save review' }).click();
  await page.waitForTimeout(2500);
  if (!page.url().match(/#\/checkins\/[^/?]+$/)) {
    fail(`saving the review did not open its detail: ${page.url()}`);
  }
  await waitForTextOrLabel(
    page,
    /Personal review — editable/,
    'personal review detail',
  );
  log('personal review: saved');
  await shot(page, '03-personal-review');
}

async function managerCheckIn(page) {
  log('manager check-in: create, finalize');
  await page.goto(`${BASE}/#/checkins`, { waitUntil: 'load' });
  await page.waitForTimeout(2000);
  await page.getByRole('button', { name: 'Create check-in' }).first().click();
  await page.waitForTimeout(1200);
  await page
    .locator('textarea[aria-label="Focus notes (optional)"]')
    .first()
    .fill('Manager smoke focus');
  await page.getByRole('button', { name: 'Create check-in' }).last().click();
  await page.waitForTimeout(2500);
  await expectCount(
    page.getByRole('button', { name: 'Mark final' }),
    '>0',
    'draft manager check-in',
  );
  await page.getByRole('button', { name: 'Mark final' }).first().click();
  await page.waitForTimeout(1000);
  await waitForTextOrLabel(
    page,
    /Mark check-in as final\?/,
    'finalize confirmation',
  );
  await page.getByRole('button', { name: 'Mark final' }).last().click();
  await page.waitForTimeout(2500);
  await waitForTextOrLabel(
    page,
    /Final check-in — read-only/,
    'final manager check-in',
  );
  log('manager check-in: finalized');
  await shot(page, '04-manager-final');
}

async function exportAndCopyPrompt(page) {
  log('export: build the export bundle and copy the prompt');
  await page.getByRole('button', { name: 'Export', exact: true }).click();
  await page.waitForTimeout(2000);
  await expectCount(
    page.getByRole('button', { name: 'Copy prompt' }),
    '>0',
    'export dialog prompt action',
  );
  await expectCount(
    page.getByRole('button', { name: 'Copy file' }),
    '>0',
    'export dialog file action',
  );
  await page.getByRole('button', { name: 'Copy prompt' }).first().click();
  await page.waitForTimeout(500);
  const clipboard = await page.evaluate(() => navigator.clipboard.readText());
  if (!clipboard.includes('Use only the data supplied')) {
    fail(`clipboard prompt missing the service-owned instruction (${clipboard.length} chars)`);
  }
  log(`export: copied ${clipboard.length} prompt characters`);
  await shot(page, '05-export');
  await page.getByRole('button', { name: 'Close', exact: true }).last().click();
  await page.waitForTimeout(600);
}

async function backupAndRestore(page) {
  log('backup: take a snapshot and restore it');
  await page.goto(`${BASE}/#/settings`, { waitUntil: 'load' });
  await page.waitForTimeout(3000);
  await expectCount(
    page.getByRole('button', { name: 'Backup now' }),
    '>0',
    'Backup now action',
  );
  await page.getByRole('button', { name: 'Backup now' }).click();
  await page.waitForTimeout(2500);
  // The snapshot list is the durable evidence: a manual snapshot appears only
  // after SettingsService.BackupNow succeeds. The transient toast is not used
  // as the assertion.
  await waitForTextOrLabel(
    page,
    /-manual\.db/,
    'manual snapshot in the backup list',
  );
  log('backup: manual snapshot listed');

  await expectCount(
    page.getByRole('button', { name: 'Restore selected' }),
    '>0',
    'restore action',
  );
  await page.getByRole('button', { name: 'Restore selected' }).click();
  await page.waitForTimeout(1000);
  await waitForTextOrLabel(
    page,
    /Restore wdid-.*\?/,
    'restore confirmation',
  );
  await page.getByRole('button', { name: 'Restore', exact: true }).last().click();
  await page.waitForTimeout(3000);
  await waitForTextOrLabel(page, /Restored wdid-/, 'restore confirmation toast');
  log('backup: restored');
  await shot(page, '06-restored');
}

function recordGrpcWeb(page) {
  page.on('response', async (response) => {
    const url = response.url();
    if (!url.includes('/wdid.v1.')) return;
    try {
      grpcWeb.push({
        procedure: url.split('/wdid.v1.')[1],
        status: response.status(),
        contentType: response.headers()['content-type'] || '',
      });
    } catch {
      // A navigation can invalidate a response; the smoke assertions do not
      // depend on every entry.
    }
  });
}

function reportGrpcWeb() {
  const services = new Set(
    grpcWeb.map((entry) => entry.procedure.split('/')[0]).filter(Boolean),
  );
  const successful = grpcWeb.filter(
    (entry) =>
      entry.status === 200 && entry.contentType.includes('application/grpc-web'),
  );
  if (successful.length === 0) {
    fail('no successful browser gRPC-Web response was observed');
  }
  log(
    `gRPC-Web: ${grpcWeb.length} responses, ${successful.length} successful across ${services.size} services`,
  );
  log(`services: ${[...services].sort().join(', ')}`);
}

(async () => {
  const browser = await chromium.launch({ headless: true });
  try {
    const context = await browser.newContext({
      viewport: { width: 1440, height: 1200 },
      permissions: ['clipboard-read', 'clipboard-write'],
    });
    const page = await context.newPage();
    recordGrpcWeb(page);

    await signIn(page);
    await captureEntry(page);
    await personalReview(page);
    await managerCheckIn(page);
    await exportAndCopyPrompt(page);
    await backupAndRestore(page);
    reportGrpcWeb();
    log('PASS');
  } finally {
    await browser.close();
  }
})().catch((error) => {
  console.error(`[smoke] FAIL: ${error.message}`);
  process.exit(1);
});
