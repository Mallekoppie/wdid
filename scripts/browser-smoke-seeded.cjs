#!/usr/bin/env node
/*
 * Seeded end-to-end smoke test for the demo dataset.
 *
 * Unlike scripts/browser-smoke.cjs (which exercises the UI-creation loop
 * against a scratch database), this script validates the deterministic data
 * seeded by `wdid seed`. It walks Today, Log, Initiatives and project detail,
 * Support, Check-ins/review and Settings for the `demo` scenario, and asserts
 * the empty states for the `empty` scenario.
 *
 * The service resolves "today" and "this week" from its own clock, so the
 * anchor must be the UTC date the service is running on. `make smoke-seeded`
 * computes that date once, seeds the temporary database with
 * `--anchor <date>`, and passes the same date here. The browser clock is then
 * frozen to that date at midday UTC so the Flutter client's local date agrees.
 * Only Date is frozen; timers and requestAnimationFrame keep running because
 * Flutter animations need them.
 *
 * Usage:
 *   npm install --no-save playwright          # or point NODE_PATH at an install
 *   WDID_BASE_URL=http://127.0.0.1:9202 \
 *   WDID_SMOKE_SCENARIO=demo \
 *   WDID_SMOKE_ANCHOR=2026-10-25 \
 *   WDID_SMOKE_EMAIL=demo@wdid.local \
 *   WDID_SMOKE_PASSWORD=demo-password-123 \
 *   node scripts/browser-smoke-seeded.cjs
 *
 * Set WDID_SMOKE_SHOTS=1 to write screenshots next to the failure/step output.
 */
'use strict';

const { chromium } = require('playwright');
const fs = require('node:fs');
const path = require('node:path');

const BASE = process.env.WDID_BASE_URL || 'http://127.0.0.1:9202';
const SCENARIO = process.env.WDID_SMOKE_SCENARIO || 'demo';
const ANCHOR = process.env.WDID_SMOKE_ANCHOR || utcToday();
const EMAIL = process.env.WDID_SMOKE_EMAIL || 'demo@wdid.local';
const PASSWORD = process.env.WDID_SMOKE_PASSWORD || 'demo-password-123';
const SHOTS = process.env.WDID_SMOKE_SHOTS === '1';
const SHOT_DIR = process.env.WDID_SMOKE_SHOT_DIR || '/tmp/wdid-smoke-seeded-shots';

const FIXTURE_DIR = path.join(__dirname, '..', 'internal', 'demo', 'fixtures');

// ---------------------------------------------------------------------------
// Fixture data: the seeded UI is asserted against the same files the seeder
// embeds, so these expectations cannot drift from the dataset.
// ---------------------------------------------------------------------------

function readFixture(name) {
  return JSON.parse(fs.readFileSync(path.join(FIXTURE_DIR, name), 'utf8'));
}

const taxonomy = readFixture('taxonomy.json');
const people = readFixture('people.json');
const settingsFixture = readFixture('settings.json');
const entriesFixture = readFixture('entries.json');
const notesFixture = readFixture('notes.json');
const milestonesFixture = readFixture('milestones.json');
const checkInsFixture = readFixture('check_ins.json');

const MONTHS = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];
const WEEKDAYS = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];

function utcToday() {
  return new Date().toISOString().slice(0, 10);
}

function parseAnchor(value) {
  const match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(value);
  if (!match) fail(`WDID_SMOKE_ANCHOR must be YYYY-MM-DD, got ${value}`);
  const date = new Date(
    Date.UTC(Number(match[1]), Number(match[2]) - 1, Number(match[3]), 12, 0, 0),
  );
  if (Number.isNaN(date.getTime())) fail(`invalid anchor date ${value}`);
  if (isoDate(date) !== value) fail(`invalid anchor date ${value}`);
  return date;
}

function isoDate(date) {
  return date.toISOString().slice(0, 10);
}

function addDays(date, days) {
  const copy = new Date(date.getTime());
  copy.setUTCDate(copy.getUTCDate() + days);
  return copy;
}

function dayNumber(date) {
  return Date.UTC(date.getUTCFullYear(), date.getUTCMonth(), date.getUTCDate());
}

function sameDay(a, b) {
  return dayNumber(a) === dayNumber(b);
}

function startOfQuarter(date) {
  const month = Math.floor(date.getUTCMonth() / 3) * 3;
  return new Date(Date.UTC(date.getUTCFullYear(), month, 1, 12));
}

function startOfWeek(date) {
  const offset = (date.getUTCDay() + 6) % 7; // Monday = 0
  return addDays(date, -offset);
}

function shortDate(date) {
  return `${date.getUTCDate()} ${MONTHS[date.getUTCMonth()]}`;
}

function fullDate(date) {
  return `${WEEKDAYS[date.getUTCDay()]} ${date.getUTCDate()} ` +
    `${MONTHS[date.getUTCMonth()]} ${date.getUTCFullYear()}`;
}

/// Mirrors web/lib/utils/time_utils.dart formatRange.
function formatRange(start, end) {
  if (start.getUTCFullYear() === end.getUTCFullYear()) {
    return `${shortDate(start)} → ${shortDate(end)} ${end.getUTCFullYear()}`;
  }
  return `${shortDate(start)} ${start.getUTCFullYear()} → ` +
    `${shortDate(end)} ${end.getUTCFullYear()}`;
}

/// Mirrors web/lib/utils/time_utils.dart formatDuration.
function formatDuration(minutes) {
  const safe = Math.max(0, minutes);
  const hours = Math.floor(safe / 60);
  const remainder = safe % 60;
  if (hours === 0) return `${remainder}m`;
  if (remainder === 0) return `${hours}h`;
  return `${hours}h ${remainder}m`;
}

function capitalize(value) {
  return value.length === 0 ? value : value[0].toUpperCase() + value.slice(1);
}

const ANCHOR_DATE = parseAnchor(ANCHOR);
const WINDOW_START = addDays(ANCHOR_DATE, -13);
const WEEK_START = startOfWeek(ANCHOR_DATE);
const QUARTER_START = startOfQuarter(ANCHOR_DATE);
// The seeded window is always 14 calendar days, anchor-13 .. anchor.
const WINDOW_SPAN_DAYS =
  Math.round((dayNumber(ANCHOR_DATE) - dayNumber(WINDOW_START)) / 86400000) + 1;

function firstWeekday(date) {
  let cursor = date;
  while (cursor.getUTCDay() === 0 || cursor.getUTCDay() === 6) {
    cursor = addDays(cursor, 1);
  }
  return cursor;
}

function latestSaturday(date) {
  let cursor = date;
  while (cursor.getUTCDay() !== 6) cursor = addDays(cursor, -1);
  return cursor;
}

const SPARSE_DAY = firstWeekday(WINDOW_START);
const ON_CALL_DAY = latestSaturday(ANCHOR_DATE);

function entryDayRoles(day) {
  const roles = new Set();
  const weekday = day.getUTCDay() !== 0 && day.getUTCDay() !== 6;
  if (weekday && !sameDay(day, SPARSE_DAY)) roles.add('normal-weekday');
  if (sameDay(day, SPARSE_DAY)) roles.add('sparse');
  if (sameDay(day, ON_CALL_DAY)) roles.add('on-call');
  if (sameDay(day, ANCHOR_DATE)) roles.add('anchor');
  return roles;
}

/// Expands entries.json exactly like internal/demo/seedEntries.
function expandEntries() {
  const expanded = [];
  for (let index = 0; index < 14; index += 1) {
    const day = addDays(WINDOW_START, index);
    const roles = entryDayRoles(day);
    for (const template of entriesFixture.entries) {
      if (!template.days.some((selector) => roles.has(selector))) continue;
      const [hours, minutes] = template.start.split(':').map(Number);
      const started = new Date(Date.UTC(
        day.getUTCFullYear(),
        day.getUTCMonth(),
        day.getUTCDate(),
        hours,
        minutes,
      ));
      expanded.push({
        day,
        date: isoDate(day),
        started,
        startMinutes: hours * 60 + minutes,
        minutes: template.minutes,
        category: template.category,
        subcategory: template.subcategory || '',
        person: template.person || '',
        description: template.description,
        outcome: template.outcome || '',
        source: template.source,
      });
    }
  }
  return expanded;
}

const ALL_ENTRIES = expandEntries();

const CATEGORY_ROLE = new Map();
const PROJECT_CATEGORY = new Map();
const SUBCATEGORY_STATUS = new Map();
const INITIATIVE_PROJECTS = [];
for (const category of taxonomy.categories) {
  CATEGORY_ROLE.set(category.name, category.role);
  for (const subcategory of category.subcategories || []) {
    PROJECT_CATEGORY.set(subcategory.name, category.name);
    SUBCATEGORY_STATUS.set(subcategory.name, subcategory.status);
    if (category.role === 'initiative') {
      INITIATIVE_PROJECTS.push({ ...subcategory, category: category.name });
    }
  }
}
const SUPPORT_MODES = taxonomy.categories
  .find((category) => category.role === 'support')
  .subcategories.map((subcategory) => subcategory.name);

function entriesBetween(from, to) {
  const start = isoDate(from);
  const end = isoDate(to);
  return ALL_ENTRIES.filter(
    (entry) => entry.date >= start && entry.date <= end,
  );
}

function sumMinutes(entries) {
  return entries.reduce((total, entry) => total + entry.minutes, 0);
}

function distinctDays(entries) {
  return new Set(entries.map((entry) => entry.date)).size;
}

function attribution(entry) {
  return [entry.category, entry.subcategory, entry.person]
    .filter((part) => part)
    .join(' · ');
}

/// SupportEntryRow renders `Support · <person> · <mode>` (no mode when the
/// entry is a mode-less interrupt), unlike the Log's category-first order.
function supportAttribution(entry) {
  return ['Support', entry.person, entry.subcategory]
    .filter((part) => part)
    .join(' · ');
}

function categoryTotals(entries) {
  const totals = new Map();
  for (const entry of entries) {
    totals.set(entry.category, (totals.get(entry.category) || 0) + entry.minutes);
  }
  return totals;
}

function projectTotals(entries) {
  const totals = new Map();
  for (const entry of entries) {
    if (CATEGORY_ROLE.get(entry.category) !== 'initiative') continue;
    const key = entry.subcategory;
    const current = totals.get(key) || { minutes: 0, entries: 0 };
    current.minutes += entry.minutes;
    current.entries += 1;
    totals.set(key, current);
  }
  return totals;
}

function supportTotals(entries) {
  const support = entries.filter(
    (entry) => CATEGORY_ROLE.get(entry.category) === 'support',
  );
  const byPerson = new Map();
  const byMode = new Map();
  for (const entry of support) {
    const person = byPerson.get(entry.person) || { minutes: 0, interactions: 0 };
    person.minutes += entry.minutes;
    person.interactions += 1;
    byPerson.set(entry.person, person);
    if (entry.subcategory) {
      const mode = byMode.get(entry.subcategory) ||
        { minutes: 0, interactions: 0 };
      mode.minutes += entry.minutes;
      mode.interactions += 1;
      byMode.set(entry.subcategory, mode);
    }
  }
  return {
    minutes: sumMinutes(support),
    interactions: support.length,
    people: byPerson.size,
    byPerson,
    byMode,
  };
}

const ANCHOR_ENTRIES = ALL_ENTRIES.filter(
  (entry) => entry.date === isoDate(ANCHOR_DATE),
);
const WINDOW_ENTRIES = entriesBetween(WINDOW_START, ANCHOR_DATE);
const WEEK_ENTRIES = entriesBetween(WEEK_START, ANCHOR_DATE);
const QUARTER_ENTRIES = entriesBetween(QUARTER_START, ANCHOR_DATE);
const WINDOW_MINUTES = sumMinutes(WINDOW_ENTRIES);
const WINDOW_DAYS_WITH_ENTRIES = distinctDays(WINDOW_ENTRIES);
const WEEK_MINUTES = sumMinutes(WEEK_ENTRIES);
const TODAY_MINUTES = sumMinutes(ANCHOR_ENTRIES);
const WEEK_CATEGORIES = [...new Set(WEEK_ENTRIES.map((entry) => entry.category))];
const QUARTER_PROJECT_TOTALS = projectTotals(QUARTER_ENTRIES);
const QUARTER_CATEGORY_TOTALS = categoryTotals(QUARTER_ENTRIES);
const QUARTER_INITIATIVE_MINUTES = [...CATEGORY_ROLE.entries()]
  .filter(([, role]) => role === 'initiative')
  .reduce(
    (total, [name]) => total + (QUARTER_CATEGORY_TOTALS.get(name) || 0),
    0,
  );

const ANCHOR_NOTE = notesFixture.dayNotes.find(
  (note) => note.daysBeforeAnchor === 0,
).text;

const ACME_NOTE = notesFixture.projectNotes.find(
  (note) => note.subcategory === 'Acme migration',
).text;
const LONG_NOTE = notesFixture.projectNotes.find(
  (note) => note.subcategory === 'Search relevance',
).text;

const PROJECT_MILESTONES = new Map();
for (const milestone of milestonesFixture.milestones) {
  const due = addDays(ANCHOR_DATE, milestone.dueOffsetDays);
  const list = PROJECT_MILESTONES.get(milestone.subcategory) || [];
  list.push({ ...milestone, due });
  PROJECT_MILESTONES.set(milestone.subcategory, list);
}

for (const checkIn of checkInsFixture.checkIns) {
  checkIn.periodStart = addDays(ANCHOR_DATE, -checkIn.periodStartOffset);
  checkIn.periodEnd = addDays(ANCHOR_DATE, -checkIn.periodEndOffset);
  checkIn.createdAt = addDays(ANCHOR_DATE, -checkIn.createdDaysBeforeAnchor);
  checkIn.daysCovered =
    Math.round(
      (dayNumber(checkIn.periodEnd) - dayNumber(checkIn.periodStart)) /
        86400000,
    ) + 1;
  checkIn.entries = entriesBetween(checkIn.periodStart, checkIn.periodEnd);
  checkIn.minutes = sumMinutes(checkIn.entries);
  checkIn.support = supportTotals(checkIn.entries);
}

// ---------------------------------------------------------------------------
// Playwright helpers (same idioms as scripts/browser-smoke.cjs)
// ---------------------------------------------------------------------------

const grpcWeb = [];

function log(message) {
  console.log(`[smoke-seeded:${SCENARIO}] ${message}`);
}

function fail(message) {
  throw new Error(message);
}

function escapeRegExp(value) {
  return value.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

async function accessibleName(locator) {
  const label = await locator.getAttribute('aria-label');
  if (label && label.trim()) return label.trim();
  const text = await locator.textContent();
  return (text || '').trim();
}

async function expectCount(locator, expected, label, timeout = 15000) {
  if (expected === '>0') {
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

async function hasTextOrLabel(page, pattern) {
  const source = pattern.source;
  return page.evaluate((expression) => {
    const regex = new RegExp(expression);
    // Flutter's semantics DOM interleaves text nodes with newlines and
    // indentation. Collapse whitespace so multi-word assertions are not
    // sensitive to where the framework inserted a line break.
    const normalize = (value) => (value || '').replace(/\s+/g, ' ');
    if (regex.test(normalize(document.body.textContent))) return true;
    for (const node of document.querySelectorAll('[aria-label]')) {
      if (regex.test(normalize(node.getAttribute('aria-label')))) return true;
    }
    return false;
  }, source);
}

async function waitForTextOrLabel(page, pattern, label, timeout = 15000) {
  const started = Date.now();
  while (Date.now() - started < timeout) {
    if (await hasTextOrLabel(page, pattern)) return;
    await page.waitForTimeout(300);
  }
  fail(`${label}: no text or aria-label matched ${pattern}`);
}

async function waitForNoTextOrLabel(page, pattern, label, timeout = 5000) {
  const started = Date.now();
  while (Date.now() - started < timeout) {
    if (!(await hasTextOrLabel(page, pattern))) return;
    await page.waitForTimeout(250);
  }
  fail(`${label}: unexpectedly found ${pattern}`);
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

async function fillField(page, label, value) {
  // Flutter recreates the semantics input while the form settles, so retry
  // until the framework actually keeps the typed value.
  for (let attempt = 0; attempt < 25; attempt += 1) {
    const input = page.locator(`input[aria-label="${label}"]`).first();
    if (await input.count()) {
      await input.click({ timeout: 2000 }).catch(() => {});
      await page.waitForTimeout(120);
      await input.pressSequentially(value, { delay: 8 }).catch(() => {});
      await page.waitForTimeout(250);
      const values = await page.evaluate((wanted) => [
        ...document.querySelectorAll('input'),
      ]
        .filter((node) => node.getAttribute('aria-label') === wanted)
        .map((node) => node.value), label);
      if (values.includes(value)) return;
    }
    await page.waitForTimeout(250);
  }
  fail(`could not fill the ${label} field`);
}

/// Flutter's Material date fields assume the US mm/dd/yyyy compact format.
function compactDate(date) {
  const month = String(date.getUTCMonth() + 1).padStart(2, '0');
  const day = String(date.getUTCDate()).padStart(2, '0');
  return `${month}/${day}/${date.getUTCFullYear()}`;
}

/// Types a date into the range picker's input mode. The field keeps its
/// previous value, so clear it first; a few retries cover Flutter recreating
/// the semantics input while the picker settles.
async function fillDateField(page, label, value) {
  for (let attempt = 0; attempt < 25; attempt += 1) {
    const input = page.locator(`input[aria-label="${label}"]`).first();
    if (await input.count()) {
      await input.click({ timeout: 2000 }).catch(() => {});
      await page.waitForTimeout(120);
      await input.selectText().catch(() => {});
      await page.keyboard.press('Backspace').catch(() => {});
      await input.pressSequentially(value, { delay: 10 }).catch(() => {});
      await page.waitForTimeout(300);
      if ((await input.inputValue().catch(() => '')) === value) return;
    }
    await page.waitForTimeout(250);
  }
  fail(`could not fill the ${label} field`);
}

/// Selects the Log's Custom range preset and enters [start]..[end] through the
/// date-range picker's input mode. Using an explicit range keeps the assertions
/// on the full seeded window regardless of the anchor's position in the month.
async function selectLogWindow(page, start, end) {
  await selectAppDropdown(page, 'This week', 'Custom range', 'Log period');

  const switchToInput = page.getByRole('button', {
    name: 'Switch to input',
    exact: true,
  });
  await switchToInput
    .first()
    .waitFor({ state: 'attached', timeout: 10000 })
    .catch(() => {});
  if (await switchToInput.count()) {
    await switchToInput.first().click();
    await page.waitForTimeout(500);
  }

  await fillDateField(page, 'Start Date', compactDate(start));
  await fillDateField(page, 'End Date', compactDate(end));
  const ok = page.getByRole('button', { name: 'OK', exact: true });
  await ok.first().waitFor({ state: 'attached', timeout: 10000 });
  await ok.first().click();
  await page.waitForTimeout(1500);
  log(
    `Log period: custom ${isoDate(start)}..${isoDate(end)} ` +
    `(${WINDOW_SPAN_DAYS} calendar days)`,
  );
}

async function signIn(page) {
  log('sign in as the seeded account');
  await page.goto(`${BASE}/`, { waitUntil: 'load' });
  await page.waitForTimeout(2500);
  await enableSemantics(page);

  const signInButton = page.getByRole('button', { name: 'Sign in', exact: true });
  for (let attempt = 0; attempt < 40; attempt += 1) {
    if (await signInButton.count()) break;
    await page.waitForTimeout(250);
  }
  if (!(await signInButton.count())) {
    fail('auth gate: the Sign in button did not appear');
  }

  await fillField(page, 'Email', EMAIL);
  await fillField(page, 'Password', PASSWORD);
  await page.waitForTimeout(400);
  await signInButton.click();
  await page
    .waitForURL(/#\/today/, { timeout: 15000 })
    .catch(() => fail(`sign-in did not reach Today: ${page.url()}`));
  await waitForTextOrLabel(page, /Start a timer/, 'Today after sign-in');
  await shot(page, `${SCENARIO}-01-today`);
}

async function gotoRoute(page, route, gate, label) {
  await page.goto(`${BASE}/#${route}`, { waitUntil: 'load' });
  await page.waitForTimeout(1200);
  if (gate) await waitForTextOrLabel(page, gate, label || route);
}

async function openMenu(page, trigger, label) {
  await trigger.first().waitFor({ state: 'attached', timeout: 10000 });
  await trigger.first().click();
  await page.waitForTimeout(500);
  const items = page.getByRole('menuitem');
  await items.first().waitFor({ state: 'attached', timeout: 5000 }).catch(() => {});
  if ((await items.count()) === 0) fail(`${label}: the menu did not open`);
}

async function menuNames(page) {
  return page.getByRole('menuitem').evaluateAll((nodes) =>
    nodes.map((node) =>
      (node.getAttribute('aria-label') || node.textContent || '').trim(),
    ),
  );
}

async function waitForMenuItems(page, expected, label, timeout = 10000) {
  const started = Date.now();
  let names = [];
  while (Date.now() - started < timeout) {
    names = await menuNames(page);
    if (expected.every((name) => names.includes(name))) return names;
    await page.waitForTimeout(300);
  }
  const missing = expected.filter((name) => !names.includes(name));
  fail(
    `${label}: missing ${missing.join(', ')} ` +
    `(found ${names.filter(Boolean).join(', ')})`,
  );
}

async function chooseMenuItem(page, name, label) {
  const item = page.getByRole('menuitem', { name, exact: true });
  await item.first().waitFor({ state: 'attached', timeout: 5000 });
  await item.first().click();
  await page
    .getByRole('menuitem')
    .first()
    .waitFor({ state: 'detached', timeout: 5000 })
    .catch(() => {});
  await page.waitForTimeout(500);
  log(`${label}: selected ${name}`);
}

async function selectAppDropdown(page, currentValue, option, label) {
  const trigger = page.getByRole('button', {
    name: currentValue,
    exact: true,
  });
  await openMenu(page, trigger, label);
  await chooseMenuItem(page, option, label);
}

async function readFocusedInputValue(page, label) {
  const input = page.locator(`input[aria-label="${label}"]`).first();
  await input.waitFor({ state: 'attached', timeout: 10000 });
  for (let attempt = 0; attempt < 20; attempt += 1) {
    await input.click({ force: true }).catch(() => {});
    await page.waitForTimeout(300);
    const value = await input.inputValue().catch(() => '');
    if (value !== '') return value;
  }
  return '';
}

async function readFocusedTextareaValue(page, locator) {
  await locator.first().waitFor({ state: 'attached', timeout: 10000 });
  await locator.first().click({ force: true }).catch(() => {});
  await page.waitForTimeout(400);
  return locator.first().inputValue().catch(() => '');
}

async function waitForTextareaValue(page, locator, expected, label) {
  for (let attempt = 0; attempt < 20; attempt += 1) {
    const value = await readFocusedTextareaValue(page, locator);
    if (value === expected) return;
    await page.waitForTimeout(400);
  }
  fail(`${label}: textarea value did not match the seeded note`);
}

async function scrollUntil(page, pattern, label, attempts = 14) {
  for (let attempt = 0; attempt < attempts; attempt += 1) {
    if (await hasTextOrLabel(page, pattern)) return;
    await page.mouse.move(720, 900);
    await page.mouse.wheel(0, 1100);
    await page.waitForTimeout(450);
  }
  await waitForTextOrLabel(page, pattern, label);
}

async function clickProjectCard(page, projectName) {
  const card = page.getByRole('progressbar', {
    name: new RegExp(`^${escapeRegExp(projectName)}(\\s|$)`),
  });
  await card.first().waitFor({ state: 'attached', timeout: 15000 });
  await card.first().scrollIntoViewIfNeeded().catch(() => {});
  await page.waitForTimeout(300);
  const box = await card.first().boundingBox();
  if (!box) fail(`project card ${projectName}: no bounding box`);
  await page.mouse.click(box.x + box.width / 2, box.y + box.height / 2);
  await page.waitForTimeout(2000);
}

async function openTab(page, name, label) {
  const tab = page.getByRole('tab', { name, exact: true });
  await tab.first().waitFor({ state: 'attached', timeout: 10000 });
  await tab.first().click();
  await page.waitForTimeout(1500);
  log(`${label}: opened ${name}`);
}

// ---------------------------------------------------------------------------
// Scenario assertions
// ---------------------------------------------------------------------------

async function assertTodayDemo(page) {
  log('Today: idle timer, anchor-day rows, week report and day note');
  await waitForTextOrLabel(page, /Start a timer/, 'Today: idle timer');
  await waitForNoTextOrLabel(page, /\bRunning\b/, 'Today: no running timer');
  await waitForNoTextOrLabel(page, /Timer paused/, 'Today: no paused timer');

  await waitForTextOrLabel(
    page,
    new RegExp(escapeRegExp(fullDate(ANCHOR_DATE))),
    'Today: anchor date',
  );
  await waitForTextOrLabel(
    page,
    new RegExp(escapeRegExp(`${formatDuration(WEEK_MINUTES)} this week`)),
    'Today: week label',
  );
  await waitForTextOrLabel(
    page,
    new RegExp(escapeRegExp(`${formatDuration(TODAY_MINUTES)}`)),
    'Today: total',
  );
  await waitForTextOrLabel(
    page,
    new RegExp(
      escapeRegExp(`${formatDuration(WEEK_MINUTES)} logged this week`),
    ),
    'Today: week report total',
  );
  await waitForTextOrLabel(page, /Week by category/, 'Today: week panel');

  for (const category of WEEK_CATEGORIES) {
    await waitForTextOrLabel(
      page,
      new RegExp(escapeRegExp(category)),
      `Today: week category ${category}`,
    );
  }

  for (const entry of ANCHOR_ENTRIES) {
    await waitForTextOrLabel(
      page,
      new RegExp(escapeRegExp(entry.description)),
      `Today: entry ${entry.description}`,
    );
    await waitForTextOrLabel(
      page,
      new RegExp(escapeRegExp(attribution(entry))),
      `Today: attribution ${attribution(entry)}`,
    );
  }

  const interrupt = ANCHOR_ENTRIES.find((entry) => !entry.subcategory);
  if (!interrupt) fail('Today: the fixture has no mode-less interrupt row');
  await waitForTextOrLabel(page, /No mode/, 'Today: no-mode label');
  await waitForTextOrLabel(page, /Set mode/, 'Today: set-mode action');

  await waitForTextareaValue(
    page,
    page.locator('textarea'),
    ANCHOR_NOTE,
    'Today: anchor day note',
  );
  await shot(page, `${SCENARIO}-02-today-populated`);
}

async function assertTodayEmpty(page) {
  log('Today: empty states');
  await waitForTextOrLabel(page, /Start a timer/, 'Today: idle timer');
  await waitForNoTextOrLabel(page, /\bRunning\b/, 'Today: no running timer');
  await waitForNoTextOrLabel(page, /Timer paused/, 'Today: no paused timer');
  await waitForTextOrLabel(page, /Nothing logged yet/, 'Today: empty list');
  await waitForTextOrLabel(
    page,
    /Capture your first entry above\./,
    'Today: empty list hint',
  );
  await waitForTextOrLabel(page, /0m this week/, 'Today: empty week label');
  await waitForTextOrLabel(
    page,
    /No time logged in this period\./,
    'Today: empty week report',
  );
  await waitForTextareaValue(
    page,
    page.locator('textarea'),
    '',
    'Today: empty day note',
  );
  await shot(page, `${SCENARIO}-02-today-empty`);
}

async function assertLogDemo(page) {
  log('Log: full-window totals, filters and seeded descriptions');
  await gotoRoute(page, '/log', /Add entry/, 'Log');

  // Query the whole seeded window explicitly. The preset ranges would clip it
  // when the anchor is early in the month or week.
  if (WINDOW_SPAN_DAYS !== 14) {
    fail(`Log: seeded window spans ${WINDOW_SPAN_DAYS} days, expected 14`);
  }
  await selectLogWindow(page, WINDOW_START, ANCHOR_DATE);
  await waitForTextOrLabel(
    page,
    new RegExp(escapeRegExp(formatRange(WINDOW_START, ANCHOR_DATE))),
    'Log: window range',
  );
  await waitForTextOrLabel(
    page,
    new RegExp(
      escapeRegExp(
        `${formatDuration(WINDOW_MINUTES)} · ` +
        `${WINDOW_DAYS_WITH_ENTRIES} days shown`,
      ),
    ),
    'Log: window total and day count',
  );

  await openMenu(
    page,
    page.getByRole('button', { name: 'All categories', exact: true }),
    'Log category',
  );
  await waitForMenuItems(
    page,
    ['Client Delivery', 'Platform', 'Growth'],
    'Log category menu',
  );
  await chooseMenuItem(page, 'Client Delivery', 'Log category');
  await page.waitForTimeout(1200);

  await openMenu(
    page,
    page.getByRole('button', { name: 'All subcategories', exact: true }),
    'Log subcategory',
  );
  await waitForMenuItems(
    page,
    ['Acme migration', 'Globex onboarding', 'Initech audit'],
    'Log subcategory menu',
  );
  await chooseMenuItem(page, 'Acme migration', 'Log subcategory');
  await page.waitForTimeout(1200);

  const acmeEntries = WINDOW_ENTRIES.filter(
    (entry) => entry.subcategory === 'Acme migration',
  );
  await waitForTextOrLabel(
    page,
    new RegExp(
      escapeRegExp(
        `${formatDuration(sumMinutes(acmeEntries))} · ` +
        `${distinctDays(acmeEntries)} days shown`,
      ),
    ),
    'Log: filtered Acme total and day count',
  );
  for (const entry of acmeEntries) {
    await waitForTextOrLabel(
      page,
      new RegExp(escapeRegExp(entry.description)),
      `Log: filtered entry ${entry.description}`,
    );
  }
  await shot(page, `${SCENARIO}-03-log-filtered`);
}

async function assertLogEmpty(page) {
  log('Log: empty states');
  await gotoRoute(page, '/log', /Add entry/, 'Log');
  await waitForTextOrLabel(
    page,
    /Nothing logged in this period/,
    'Log: empty title',
  );
  await waitForTextOrLabel(
    page,
    /Capture work on Today or widen the date range\./,
    'Log: empty hint',
  );
  await waitForTextOrLabel(page, /Add entry/, 'Log: add entry action');
  await shot(page, `${SCENARIO}-03-log-empty`);
}

async function assertInitiativesDemo(page) {
  log('Initiatives: portfolio cards and project detail');
  await gotoRoute(
    page,
    '/initiatives',
    new RegExp(escapeRegExp('8 projects')),
    'Initiatives',
  );
  await waitForTextOrLabel(
    page,
    new RegExp(
      escapeRegExp(
        `8 projects · ${formatDuration(QUARTER_INITIATIVE_MINUTES)} ` +
        'logged this quarter',
      ),
    ),
    'Initiatives: header',
  );

  for (const project of INITIATIVE_PROJECTS) {
    const totals = QUARTER_PROJECT_TOTALS.get(project.name) ||
      { minutes: 0, entries: 0 };
    const card = page.getByRole('progressbar', {
      name: new RegExp(`^${escapeRegExp(project.name)}(\\s|$)`),
    });
    await card.first().waitFor({ state: 'attached', timeout: 15000 });
    const name = await accessibleName(card.first());
    const expectedParts = [
      project.name,
      project.category,
      capitalize(project.status),
      project.targetOutcome,
      formatDuration(totals.minutes),
      `${project.progress}%`,
    ];
    for (const part of expectedParts) {
      if (!name.includes(part)) {
        fail(
          `Initiatives: card ${project.name} is missing ${JSON.stringify(part)}; ` +
          `accessible name was ${JSON.stringify(name.slice(0, 300))}`,
        );
      }
    }
  }
  await shot(page, `${SCENARIO}-04-initiatives`);

  // Acme migration: notes, milestones and report.
  await clickProjectCard(page, 'Acme migration');
  if (!page.url().includes('/initiatives/')) {
    fail(`Acme migration: card click did not open the detail (${page.url()})`);
  }
  await waitForTextOrLabel(
    page,
    new RegExp(escapeRegExp('Acme migration')),
    'Acme detail: title',
  );
  await waitForTextOrLabel(
    page,
    new RegExp(
      escapeRegExp("Acme's production workloads run entirely on the new platform."),
    ),
    'Acme detail: target outcome',
  );
  await waitForTextOrLabel(page, /60%/, 'Acme detail: progress');

  await openTab(page, 'Notes', 'Acme detail');
  await waitForTextOrLabel(
    page,
    new RegExp(escapeRegExp(ACME_NOTE)),
    'Acme detail: project note',
  );

  await openTab(page, 'Milestones', 'Acme detail');
  const acmeMilestones = PROJECT_MILESTONES.get('Acme migration');
  await waitForTextOrLabel(
    page,
    new RegExp(
      escapeRegExp(
        `${acmeMilestones.length} milestones`,
      ),
    ),
    'Acme detail: milestone count',
  );
  const checkboxes = page.getByRole('checkbox');
  await expectCount(
    checkboxes,
    acmeMilestones.length,
    'Acme detail: milestone checkboxes',
  );
  for (const [index, milestone] of acmeMilestones.entries()) {
    await waitForTextOrLabel(
      page,
      new RegExp(escapeRegExp(milestone.title)),
      `Acme detail: milestone ${milestone.title}`,
    );
    await waitForTextOrLabel(
      page,
      new RegExp(escapeRegExp(`Due ${shortDate(milestone.due)}`)),
      `Acme detail: milestone due ${milestone.title}`,
    );
    const checked = await checkboxes.nth(index).isChecked();
    if (checked !== milestone.done) {
      fail(
        `Acme detail: milestone ${milestone.title} checked=${checked}, ` +
        `expected ${milestone.done}`,
      );
    }
  }
  await shot(page, `${SCENARIO}-05-acme-milestones`);

  await openTab(page, 'Report', 'Acme detail');
  await waitForTextOrLabel(page, /Project report/, 'Acme report: title');
  await waitForTextOrLabel(page, /This quarter/, 'Acme report: quarter stat');
  const acmeQuarter = QUARTER_PROJECT_TOTALS.get('Acme migration') ||
    { minutes: 0, entries: 0 };
  const acmeProgress = {
    total: acmeMilestones.length,
    done: acmeMilestones.filter((milestone) => milestone.done).length,
  };
  await waitForTextOrLabel(
    page,
    new RegExp(
      escapeRegExp(`${formatDuration(acmeQuarter.minutes)} `) + '[\\s\\S]*' +
      escapeRegExp(`${acmeQuarter.entries} `) + '[\\s\\S]*' +
      escapeRegExp(`${acmeProgress.done} of ${acmeProgress.total} complete`),
    ),
    'Acme report: stats',
  );

  // Search relevance carries the long, unwrapped note.
  await gotoRoute(
    page,
    '/initiatives',
    /8 projects/,
    'Initiatives again',
  );
  await clickProjectCard(page, 'Search relevance');
  await openTab(page, 'Notes', 'Search relevance');
  const longNoteStart = LONG_NOTE.slice(0, 60);
  const longNoteEnd = LONG_NOTE.slice(-40);
  await waitForTextOrLabel(
    page,
    new RegExp(escapeRegExp(longNoteStart)),
    'Search relevance: long note start',
  );
  await waitForTextOrLabel(
    page,
    new RegExp(escapeRegExp(longNoteEnd)),
    'Search relevance: long note end',
  );
  const overflow = await page.evaluate(() => ({
    scrollWidth: document.documentElement.scrollWidth,
    clientWidth: document.documentElement.clientWidth,
  }));
  if (overflow.scrollWidth > overflow.clientWidth + 1) {
    fail(
      'Search relevance: the long note overflows horizontally ' +
      `(${overflow.scrollWidth} > ${overflow.clientWidth})`,
    );
  }
  await shot(page, `${SCENARIO}-06-long-note`);
}

async function assertInitiativesEmpty(page) {
  log('Initiatives: empty states');
  await gotoRoute(page, '/initiatives', /New project/, 'Initiatives');
  await waitForTextOrLabel(
    page,
    /0 projects · 0m logged this quarter/,
    'Initiatives: empty header',
  );
  await waitForTextOrLabel(page, /No projects yet/, 'Initiatives: empty title');
  await waitForTextOrLabel(page, /New project/, 'Initiatives: new project action');
  await shot(page, `${SCENARIO}-04-initiatives-empty`);
}

async function assertSupportDemo(page) {
  log('Support: roster, rollups and feed');
  await gotoRoute(page, '/support', /Support log/, 'Support');
  const totals = supportTotals(QUARTER_ENTRIES);
  await waitForTextOrLabel(
    page,
    new RegExp(
      escapeRegExp(
        `${formatDuration(totals.minutes)} · ${totals.people} ` +
        `${totals.people === 1 ? 'person' : 'people'} · ` +
        `${totals.interactions} interactions`,
      ),
    ),
    'Support: header totals',
  );

  for (const person of people.roster) {
    await waitForTextOrLabel(
      page,
      new RegExp(escapeRegExp(person)),
      `Support: roster ${person}`,
    );
  }

  for (const [mode, data] of totals.byMode) {
    await waitForTextOrLabel(
      page,
      new RegExp(escapeRegExp(mode)),
      `Support: by-mode ${mode}`,
    );
    await waitForTextOrLabel(
      page,
      new RegExp(escapeRegExp(formatDuration(data.minutes))),
      `Support: by-mode minutes ${mode}`,
    );
  }
  await waitForTextOrLabel(
    page,
    new RegExp(
      escapeRegExp(
        `${totals.people} ${totals.people === 1 ? 'person' : 'people'} supported`,
      ),
    ),
    'Support: by-person subtitle',
  );
  for (const [person, data] of totals.byPerson) {
    await waitForTextOrLabel(
      page,
      new RegExp(escapeRegExp(person)),
      `Support: by-person ${person}`,
    );
    await waitForTextOrLabel(
      page,
      new RegExp(escapeRegExp(formatDuration(data.minutes))),
      `Support: by-person minutes ${person}`,
    );
  }

  for (const entry of QUARTER_ENTRIES.filter(
    (item) => CATEGORY_ROLE.get(item.category) === 'support',
  )) {
    await waitForTextOrLabel(
      page,
      new RegExp(escapeRegExp(supportAttribution(entry))),
      `Support: feed attribution ${supportAttribution(entry)}`,
    );
    await waitForTextOrLabel(
      page,
      new RegExp(escapeRegExp(entry.description)),
      `Support: feed entry ${entry.description}`,
    );
  }
  const noMode = QUARTER_ENTRIES.find(
    (entry) => CATEGORY_ROLE.get(entry.category) === 'support' &&
      !entry.subcategory,
  );
  if (!noMode) fail('Support: the fixture has no mode-less entry');
  await waitForTextOrLabel(
    page,
    new RegExp(escapeRegExp(`${supportAttribution(noMode)} · No mode`)),
    'Support: no-mode feed row',
  );

  // The Log support dialog's Mode selector must offer all five seeded modes.
  const expectedModes = [
    'Mentoring',
    'Pairing',
    'Incident support',
    'Code review',
    '1:1',
  ];
  const logSupport = page.getByRole('button', {
    name: 'Log support',
    exact: true,
  });
  await expectCount(logSupport, '>0', 'Support: log support action');
  await logSupport.first().click();
  const dialog = page.getByRole('dialog');
  const saveSupport = dialog.getByRole('button', {
    name: 'Save support',
    exact: true,
  });
  await saveSupport
    .first()
    .waitFor({ state: 'attached', timeout: 10000 })
    .catch(() => fail('Support: the Log support dialog did not open'));
  await openMenu(
    page,
    dialog.getByRole('button', { name: expectedModes[0], exact: true }),
    'Support mode',
  );
  await waitForMenuItems(page, expectedModes, 'Support mode menu');
  await expectCount(
    page.getByRole('menuitem'),
    expectedModes.length,
    'Support mode menu count',
  );
  await page.keyboard.press('Escape');
  await page.waitForTimeout(500);
  const cancel = dialog.getByRole('button', { name: 'Cancel', exact: true });
  await expectCount(cancel, '>0', 'Support: dialog cancel action');
  await cancel.first().click();
  await dialog
    .waitFor({ state: 'detached', timeout: 5000 })
    .catch(() => fail('Support: the Log support dialog did not close'));
  await shot(page, `${SCENARIO}-07-support`);
}

async function assertSupportEmpty(page) {
  log('Support: empty states');
  await gotoRoute(page, '/support', /Log support/, 'Support');
  await waitForTextOrLabel(
    page,
    /0m · 0 people · 0 interactions/,
    'Support: empty header',
  );
  await waitForTextOrLabel(
    page,
    /No people yet\. Add a name here or while logging support\./,
    'Support: empty roster',
  );
  await waitForTextOrLabel(
    page,
    /No support logged in this period/,
    'Support: empty feed',
  );
  await waitForTextOrLabel(page, /Log support/, 'Support: log support action');
  await shot(page, `${SCENARIO}-07-support-empty`);
}

async function assertCheckInsDemo(page) {
  log('Check-ins: cards, read-only manager detail, editable personal review');
  await gotoRoute(page, '/checkins', /Create check-in/, 'Check-ins');
  await waitForTextOrLabel(page, /2 shown/, 'Check-ins: card count');

  const manager = checkInsFixture.checkIns.find(
    (checkIn) => checkIn.kind === 'manager',
  );
  const personal = checkInsFixture.checkIns.find(
    (checkIn) => checkIn.kind === 'personal',
  );
  for (const checkIn of [manager, personal]) {
    await waitForTextOrLabel(
      page,
      new RegExp(escapeRegExp(formatRange(checkIn.periodStart, checkIn.periodEnd))),
      `Check-ins: ${checkIn.kind} period`,
    );
    await waitForTextOrLabel(
      page,
      new RegExp(
        escapeRegExp(
          `${formatDuration(checkIn.minutes)} logged ` +
          `${checkIn.daysCovered} days`,
        ),
      ),
      `Check-ins: ${checkIn.kind} metrics`,
    );
  }
  await waitForTextOrLabel(page, /Manager/, 'Check-ins: manager badge');
  await waitForTextOrLabel(page, /1:1/, 'Check-ins: audience badge');
  await waitForTextOrLabel(page, /Final/, 'Check-ins: final badge');
  await waitForTextOrLabel(page, /Personal/, 'Check-ins: personal badge');
  await waitForTextOrLabel(page, /Draft/, 'Check-ins: draft badge');
  await shot(page, `${SCENARIO}-08-checkins`);

  // Final manager check-in: read-only, aggregates.
  const managerCard = page
    .getByRole('button')
    .filter({ hasText: 'Manager' })
    .filter({ hasText: 'Final' });
  await expectCount(managerCard, 1, 'Check-ins: manager card');
  await managerCard.first().click();
  await page.waitForTimeout(2500);
  await waitForTextOrLabel(
    page,
    /Final check-in — read-only boundary for the next period\./,
    'Manager detail: read-only banner',
  );
  await waitForTextOrLabel(
    page,
    new RegExp(
      escapeRegExp(
        `${formatDuration(manager.minutes)} logged ` +
        `${manager.daysCovered} days ${manager.entries.length} entries ` +
        `${formatDuration(manager.support.minutes)} support ` +
        `${manager.support.interactions} interactions`,
      ),
    ),
    'Manager detail: stats',
  );
  await scrollUntil(page, /Time by category/, 'Manager detail: aggregates');
  await waitForTextOrLabel(page, /Time by project/, 'Manager detail: by project');
  await waitForTextOrLabel(page, /Support by person/, 'Manager detail: by person');
  await waitForTextOrLabel(page, /Weekly rhythm/, 'Manager detail: weekly rhythm');
  for (const [category, minutes] of categoryTotals(manager.entries)) {
    await waitForTextOrLabel(
      page,
      new RegExp(escapeRegExp(category)),
      `Manager detail: category ${category}`,
    );
    await waitForTextOrLabel(
      page,
      new RegExp(escapeRegExp(formatDuration(minutes))),
      `Manager detail: category minutes ${category}`,
    );
  }
  await shot(page, `${SCENARIO}-09-manager-final`);

  // Personal review: editable summary and focus notes.
  await gotoRoute(page, '/checkins', /Create check-in/, 'Check-ins again');
  const personalCard = page
    .getByRole('button')
    .filter({ hasText: 'Personal' })
    .filter({ hasText: 'Draft' });
  await expectCount(personalCard, 1, 'Check-ins: personal card');
  await personalCard.first().click();
  await page.waitForTimeout(2500);
  await waitForTextOrLabel(
    page,
    /Personal review — editable, and never moves the manager boundary\./,
    'Personal detail: editable banner',
  );
  await waitForTextOrLabel(
    page,
    new RegExp(
      escapeRegExp(
        `${formatDuration(personal.minutes)} logged ` +
        `${personal.daysCovered} days ${personal.entries.length} entries ` +
        `${formatDuration(personal.support.minutes)} support ` +
        `${personal.support.interactions} interactions`,
      ),
    ),
    'Personal detail: stats',
  );
  await waitForTextOrLabel(
    page,
    new RegExp(escapeRegExp(personal.focusNotes)),
    'Personal detail: focus notes',
  );
  await waitForTextOrLabel(
    page,
    /Draft review/,
    'Personal detail: summary',
  );
  await waitForTextOrLabel(
    page,
    /Steady progress on the self-serve trial and search relevance\./,
    'Personal detail: summary body',
  );
  await waitForTextOrLabel(page, /Edit review/, 'Personal detail: edit action');
  await waitForTextOrLabel(page, /Delete review/, 'Personal detail: delete action');
  await waitForTextOrLabel(page, /Export/, 'Personal detail: export action');
  await scrollUntil(page, /Time by category/, 'Personal detail: aggregates');
  await waitForTextOrLabel(page, /Time by category/, 'Personal detail: categories');
  await waitForTextOrLabel(page, /Time by project/, 'Personal detail: projects');
  await waitForTextOrLabel(page, /Support by person/, 'Personal detail: support');
  await shot(page, `${SCENARIO}-10-personal-review`);

  // Edit dialog opens and is dismissed without saving.
  await gotoRoute(page, '/checkins', /Create check-in/, 'Check-ins again');
  const editCard = page
    .getByRole('button')
    .filter({ hasText: 'Personal' })
    .filter({ hasText: 'Draft' });
  await editCard.first().click();
  await page.waitForTimeout(2000);
  await page.getByRole('button', { name: 'Edit review' }).first().click();
  await page.waitForTimeout(1200);
  await waitForTextOrLabel(page, /Save review/, 'Personal detail: edit dialog');
  await waitForTextOrLabel(
    page,
    /7 days covered/,
    'Personal detail: edit period',
  );
  await waitForTextOrLabel(page, /Cancel/, 'Personal detail: cancel action');
  const cancel = page.getByRole('button', { name: 'Cancel', exact: true });
  if (await cancel.count()) {
    await cancel.first().click();
  } else {
    await page.keyboard.press('Escape');
  }
  await page.waitForTimeout(800);

  // Live review over the full 14-day window. Do not save.
  await gotoRoute(
    page,
    `/checkins/review?start=${isoDate(WINDOW_START)}&end=${isoDate(ANCHOR_DATE)}`,
    /Save review/,
    'Live review',
  );
  const windowEntries = entriesBetween(WINDOW_START, ANCHOR_DATE);
  const windowSupport = supportTotals(windowEntries);
  const windowDays =
    Math.round((dayNumber(ANCHOR_DATE) - dayNumber(WINDOW_START)) / 86400000) +
    1;
  await waitForTextOrLabel(
    page,
    new RegExp(
      escapeRegExp(
        `${formatDuration(sumMinutes(windowEntries))} logged ${windowDays} days ` +
        `${windowEntries.length} entries ` +
        `${formatDuration(windowSupport.minutes)} support`,
      ),
    ),
    'Live review: stats',
  );
  await scrollUntil(page, /Time by category/, 'Live review: aggregates');
  await waitForTextOrLabel(page, /Time by project/, 'Live review: by project');
  await waitForTextOrLabel(page, /Support by person/, 'Live review: by person');
  await waitForTextOrLabel(page, /Weekly rhythm/, 'Live review: weekly rhythm');
  await shot(page, `${SCENARIO}-11-live-review`);
}

async function assertCheckInsEmpty(page) {
  log('Check-ins: empty list and empty live review');
  await gotoRoute(page, '/checkins', /Create check-in/, 'Check-ins');
  await waitForTextOrLabel(page, /No check-ins yet/, 'Check-ins: empty title');
  await waitForTextOrLabel(
    page,
    /A manager check-in snapshots the period since the previous one\./,
    'Check-ins: empty hint',
  );
  await waitForTextOrLabel(page, /Create check-in/, 'Check-ins: create action');
  await shot(page, `${SCENARIO}-08-checkins-empty`);

  await gotoRoute(page, '/checkins/review', /Save review/, 'Live review');
  await waitForTextOrLabel(
    page,
    /Nothing logged in this period/,
    'Live review: empty title',
  );
  await waitForTextOrLabel(
    page,
    /Save empty review/,
    'Live review: save empty review',
  );
  await shot(page, `${SCENARIO}-09-review-empty`);
}

async function assertSettingsDemo(page) {
  log('Settings: timezone, daily target, cadence and demo taxonomy');
  await gotoRoute(page, '/settings', /Save time settings/, 'Settings');

  const timezone = await readFocusedInputValue(page, 'Timezone');
  if (timezone !== settingsFixture.timezone) {
    fail(`Settings: timezone ${timezone}, expected ${settingsFixture.timezone}`);
  }
  const dailyTarget = await readFocusedInputValue(page, 'Daily target');
  const expectedTarget = String(settingsFixture.dailyTargetMinutes / 60);
  if (dailyTarget !== expectedTarget) {
    fail(`Settings: daily target ${dailyTarget}, expected ${expectedTarget}`);
  }
  const cadence = capitalize(settingsFixture.reviewCadence);
  await waitForTextOrLabel(
    page,
    new RegExp(escapeRegExp(cadence)),
    `Settings: review cadence ${cadence}`,
  );
  const cadenceButton = page.getByRole('button', {
    name: cadence,
    exact: true,
  });
  await expectCount(cadenceButton, 1, `Settings: ${cadence} dropdown`);
  await expectCount(
    page.getByRole('button', { name: 'Monday', exact: true }),
    1,
    'Settings: week starts Monday',
  );

  for (const category of taxonomy.categories) {
    await waitForTextOrLabel(
      page,
      new RegExp(escapeRegExp(category.name)),
      `Settings: category ${category.name}`,
    );
    for (const subcategory of category.subcategories || []) {
      await waitForTextOrLabel(
        page,
        new RegExp(escapeRegExp(subcategory.name)),
        `Settings: subcategory ${subcategory.name}`,
      );
    }
  }
  await shot(page, `${SCENARIO}-12-settings`);
}

async function assertSettingsEmpty(page) {
  log('Settings: default timezone, target, cadence and taxonomy');
  await gotoRoute(page, '/settings', /Save time settings/, 'Settings');

  const timezone = await readFocusedInputValue(page, 'Timezone');
  if (timezone !== 'UTC') fail(`Settings: timezone ${timezone}, expected UTC`);
  const dailyTarget = await readFocusedInputValue(page, 'Daily target');
  if (dailyTarget !== '7.5') {
    fail(`Settings: daily target ${dailyTarget}, expected 7.5`);
  }
  await expectCount(
    page.getByRole('button', { name: 'Off', exact: true }),
    1,
    'Settings: personal review Off',
  );
  await expectCount(
    page.getByRole('button', { name: 'Monday', exact: true }),
    1,
    'Settings: week starts Monday',
  );

  for (const expected of [
    'Initiatives',
    'No subcategories.',
    'Support',
    'Review',
    'Pair',
    'Unblock',
    'Mentor',
    'Incident',
    'Other',
    'Meetings',
    'Admin',
    'Learning',
    'Unplanned',
  ]) {
    await waitForTextOrLabel(
      page,
      new RegExp(escapeRegExp(expected)),
      `Settings: default taxonomy ${expected}`,
    );
  }
  await shot(page, `${SCENARIO}-12-settings-empty`);
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
    `gRPC-Web: ${grpcWeb.length} responses, ${successful.length} successful ` +
    `across ${services.size} services`,
  );
  log(`services: ${[...services].sort().join(', ')}`);
}

// ---------------------------------------------------------------------------
// Entry point
// ---------------------------------------------------------------------------

(async () => {
  if (SCENARIO !== 'demo' && SCENARIO !== 'empty') {
    fail(`WDID_SMOKE_SCENARIO must be demo or empty, got ${SCENARIO}`);
  }
  if (isoDate(ANCHOR_DATE) !== ANCHOR) {
    fail(`invalid anchor ${ANCHOR}`);
  }
  log(
    `scenario=${SCENARIO} base=${BASE} anchor=${ANCHOR} ` +
    `weekStart=${isoDate(WEEK_START)} window=${isoDate(WINDOW_START)}..${ANCHOR}`,
  );

  const browser = await chromium.launch({ headless: true });
  try {
    const context = await browser.newContext({
      viewport: { width: 1440, height: 1200 },
      timezoneId: 'UTC',
    });
    const page = await context.newPage();
    recordGrpcWeb(page);

    // Freeze only Date, before the app loads. Timers and rAF stay real so
    // Flutter animations still run. The service's own clock is the anchor;
    // both agree because make smoke-seeded seeds with this same UTC date.
    await page.clock.setFixedTime(
      new Date(`${ANCHOR}T12:00:00Z`),
    );
    const browserDate = await page.evaluate(() =>
      new Date().toISOString().slice(0, 10),
    );
    if (browserDate !== ANCHOR) {
      fail(`browser clock says ${browserDate}, expected ${ANCHOR}`);
    }

    await signIn(page);

    if (SCENARIO === 'demo') {
      await assertTodayDemo(page);
      await assertLogDemo(page);
      await assertInitiativesDemo(page);
      await assertSupportDemo(page);
      await assertCheckInsDemo(page);
      await assertSettingsDemo(page);
    } else {
      await assertTodayEmpty(page);
      await assertLogEmpty(page);
      await assertInitiativesEmpty(page);
      await assertSupportEmpty(page);
      await assertCheckInsEmpty(page);
      await assertSettingsEmpty(page);
    }

    reportGrpcWeb();
    log('PASS');
  } finally {
    await browser.close();
  }
})().catch((error) => {
  console.error(`[smoke-seeded] FAIL: ${error.message}`);
  process.exit(1);
});
