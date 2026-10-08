import assert from 'node:assert/strict';
import { test } from 'node:test';

import {
  activeSprintLabel,
  diffSprintLabels,
  extractTaskIds,
  run,
  sprintLabel,
  taskSprintLabels,
  todayIn,
} from '../sprint-label.mjs';

// The real list names of the "Core plateform" folder on 2026-10-08. The
// spacing before the parenthesis is not consistent in ClickUp, on purpose.
const SPRINT_LISTS = [
  { id: '1', name: 'Roadmap' },
  { id: '2', name: 'Bugs & Requests' },
  { id: '3', name: 'Sprint 21 (8/3 - 8/23)' },
  { id: '4', name: 'Sprint 22 (8/24 - 9/13)' },
  { id: '5', name: 'Sprint 23 (9/14 - 9/24)' },
  { id: '6', name: 'Sprint 24(9/28 - 10/18)' },
  { id: '7', name: 'Sprint 25 (10/19 - 11/8)' },
  { id: '8', name: 'Backlog' },
];

// --- extractTaskIds -------------------------------------------------------

test('extracts the ticket id from a conventional PR title', () => {
  assert.deepEqual(
    extractTaskIds('test(respect-saas-e2e): [CORE-7895] cover the lazy project filter'),
    ['CORE-7895']
  );
});

test('extracts several ids, deduplicated, in title order', () => {
  assert.deepEqual(extractTaskIds('fix(ui): CORE-12 and CORE-7 and CORE-12 again'), [
    'CORE-12',
    'CORE-7',
  ]);
});

test('returns nothing when the title carries no id', () => {
  assert.deepEqual(extractTaskIds('chore: add verify-frontend verification skill'), []);
  assert.deepEqual(extractTaskIds(''), []);
});

test('honours a different id prefix', () => {
  assert.deepEqual(extractTaskIds('feat(x): [DEV-3] y', 'DEV'), ['DEV-3']);
  assert.deepEqual(extractTaskIds('feat(x): [CORE-3] y', 'DEV'), []);
});

// --- sprintLabel ----------------------------------------------------------

test('maps a sprint list name to the lowercase "sprint N" label', () => {
  assert.equal(sprintLabel('Sprint 24(9/28 - 10/18)'), 'sprint 24');
  assert.equal(sprintLabel('Sprint 22 (8/24 - 9/13)'), 'sprint 22');
  assert.equal(sprintLabel('  sprint 7  '), 'sprint 7');
});

test('ignores lists that are not sprints', () => {
  assert.equal(sprintLabel('Backlog'), null);
  assert.equal(sprintLabel('Sprint planning'), null);
  assert.equal(sprintLabel('Sprints'), null);
  assert.equal(sprintLabel(undefined), null);
});

// --- taskSprintLabels -----------------------------------------------------

test('reads the sprint from the task home list', () => {
  const task = { list: { name: 'Sprint 24(9/28 - 10/18)' } };
  assert.deepEqual(taskSprintLabels(task), ['sprint 24']);
});

test('reads the sprint from a secondary location when the home list is not one', () => {
  const task = {
    list: { name: 'Backlog' },
    locations: [{ name: 'Backlog' }, { name: 'Sprint 25 (10/19 - 11/8)' }],
  };
  assert.deepEqual(taskSprintLabels(task), ['sprint 25']);
});

test('returns every distinct sprint a task sits in', () => {
  const task = {
    list: { name: 'Sprint 24(9/28 - 10/18)' },
    locations: [{ name: 'Sprint 24(9/28 - 10/18)' }, { name: 'Sprint 25 (10/19 - 11/8)' }],
  };
  assert.deepEqual(taskSprintLabels(task), ['sprint 24', 'sprint 25']);
});

test('returns nothing for a task outside any sprint', () => {
  assert.deepEqual(taskSprintLabels({ list: { name: 'Backlog' } }), []);
  assert.deepEqual(taskSprintLabels({}), []);
});

// --- todayIn / activeSprintLabel -------------------------------------------

test('todayIn gives the calendar date in the sprint timezone, not UTC', () => {
  // 23:30 UTC on the 7th is already the 8th in Zurich (CEST, UTC+2).
  const now = new Date('2026-10-07T23:30:00Z');
  assert.deepEqual(todayIn('Europe/Zurich', now), [2026, 10, 8]);
  assert.deepEqual(todayIn('UTC', now), [2026, 10, 7]);
});

test('picks the sprint whose start_date/due_date cover today', () => {
  const day = 24 * 3600 * 1000;
  const today = Date.UTC(2026, 9, 8); // 2026-10-08
  const lists = [
    {
      name: 'Sprint 23 (9/14 - 9/24)',
      start_date: String(today - 30 * day),
      due_date: String(today - 14 * day),
    },
    {
      name: 'Sprint 24(9/28 - 10/18)',
      start_date: String(today - 10 * day),
      due_date: String(today + 10 * day),
    },
    {
      name: 'Sprint 25 (10/19 - 11/8)',
      start_date: String(today + 11 * day),
      due_date: String(today + 31 * day),
    },
    { name: 'Backlog', start_date: String(today - day), due_date: String(today + day) },
  ];
  assert.equal(activeSprintLabel(lists, [2026, 10, 8], 'UTC'), 'sprint 24');
});

test('falls back to the (M/D - M/D) range in the list name when ClickUp gives no dates', () => {
  assert.equal(activeSprintLabel(SPRINT_LISTS, [2026, 10, 8]), 'sprint 24');
  assert.equal(activeSprintLabel(SPRINT_LISTS, [2026, 10, 19]), 'sprint 25');
  assert.equal(activeSprintLabel(SPRINT_LISTS, [2026, 9, 24]), 'sprint 23');
});

test('a sprint spanning the new year is active on both sides of it', () => {
  const lists = [{ name: 'Sprint 30 (12/22 - 1/10)' }];
  assert.equal(activeSprintLabel(lists, [2026, 12, 30]), 'sprint 30');
  assert.equal(activeSprintLabel(lists, [2027, 1, 5]), 'sprint 30');
  assert.equal(activeSprintLabel(lists, [2027, 1, 11]), null);
});

test('no sprint covers today (gap between sprints) -> null', () => {
  // 9/25 - 9/27 sits between sprint 23 and sprint 24.
  assert.equal(activeSprintLabel(SPRINT_LISTS, [2026, 9, 26]), null);
});

test('when two sprints overlap today the highest-numbered one wins', () => {
  const lists = [{ name: 'Sprint 24(9/28 - 10/18)' }, { name: 'Sprint 25 (10/15 - 11/8)' }];
  assert.equal(activeSprintLabel(lists, [2026, 10, 16]), 'sprint 25');
});

test('archived lists are never the active sprint', () => {
  const lists = [{ name: 'Sprint 24(9/28 - 10/18)', archived: true }];
  assert.equal(activeSprintLabel(lists, [2026, 10, 8]), null);
});

// --- diffSprintLabels ----------------------------------------------------

test('adds the wanted sprint label and removes the stale one, leaving other labels alone', () => {
  const current = ['respect-saas', 'sprint 23', 'approved by claude'];
  assert.deepEqual(diffSprintLabels(current, ['sprint 24']), {
    add: ['sprint 24'],
    remove: ['sprint 23'],
  });
});

test('is a no-op when the labels already match', () => {
  assert.deepEqual(diffSprintLabels(['sprint 24', 'dpp'], ['sprint 24']), { add: [], remove: [] });
});

test('removes every sprint label when nothing is wanted', () => {
  assert.deepEqual(diffSprintLabels(['sprint 23', 'sprint 24'], []), {
    add: [],
    remove: ['sprint 23', 'sprint 24'],
  });
});

test('label comparison is case-insensitive, GitHub style', () => {
  assert.deepEqual(diffSprintLabels(['Sprint 24'], ['sprint 24']), { add: [], remove: [] });
});

// --- run (end to end, with a fake fetch) ----------------------------------

const TEAM = '90151502952';
const FOLDER = '90159037608';

function fakeApi({ tasks = {}, lists = SPRINT_LISTS, prLabels = [], clickupDown = false } = {}) {
  const calls = [];
  const fetch = async (url, init = {}) => {
    const method = init.method ?? 'GET';
    calls.push(`${method} ${url}`);
    const json = (status, body) => ({
      ok: status >= 200 && status < 300,
      status,
      json: async () => body,
      text: async () => JSON.stringify(body),
    });
    if (url.startsWith('https://api.clickup.com/')) {
      if (clickupDown) return json(500, { err: 'boom' });
      const task = url.match(/\/task\/([^?]+)/);
      if (task) {
        const body = tasks[decodeURIComponent(task[1])];
        return body ? json(200, body) : json(404, { err: 'Task not found' });
      }
      if (url.includes(`/folder/${FOLDER}/list`)) return json(200, { lists });
      return json(404, {});
    }
    if (url.startsWith('https://api.github.com/')) {
      if (method === 'GET' && url.endsWith('/issues/4206/labels?per_page=100')) {
        return json(
          200,
          prLabels.map((name) => ({ name }))
        );
      }
      if (method === 'POST' && url.endsWith('/repos/ProductDNA-CH/frontend/labels')) {
        const { name } = JSON.parse(init.body);
        return name === 'sprint 24'
          ? json(422, { errors: [{ code: 'already_exists' }] })
          : json(201, {});
      }
      if (method === 'POST' && url.endsWith('/issues/4206/labels')) return json(200, []);
      if (method === 'DELETE') return json(200, []);
    }
    return json(500, {});
  };
  return { fetch, calls };
}

const baseEnv = {
  CLICKUP_TOKEN: 'pk_test',
  CLICKUP_TEAM_ID: TEAM,
  CLICKUP_SPRINT_FOLDER_ID: FOLDER,
  GITHUB_TOKEN: 'ghs_test',
  GITHUB_REPOSITORY: 'ProductDNA-CH/frontend',
  PR_NUMBER: '4206',
};

const quiet = { log: () => {}, warn: () => {} };

test('run: a titled ticket labels the PR with its sprint and drops the stale one', async () => {
  const api = fakeApi({
    tasks: { 'CORE-7895': { list: { name: 'Sprint 24(9/28 - 10/18)' } } },
    prLabels: ['respect-saas', 'sprint 23'],
  });
  const result = await run(
    { ...baseEnv, PR_TITLE: 'test(respect-saas-e2e): [CORE-7895] cover the lazy project filter' },
    { fetch: api.fetch, now: new Date('2026-10-08T10:00:00Z'), ...quiet }
  );
  assert.deepEqual(result, { wanted: ['sprint 24'], add: ['sprint 24'], remove: ['sprint 23'] });
  assert.ok(
    api.calls.includes(
      `GET https://api.clickup.com/api/v2/task/CORE-7895?custom_task_ids=true&team_id=${TEAM}`
    ),
    'reads the task by custom id'
  );
  assert.ok(api.calls.includes('POST https://api.github.com/repos/ProductDNA-CH/frontend/labels'));
  assert.ok(
    api.calls.includes(
      'POST https://api.github.com/repos/ProductDNA-CH/frontend/issues/4206/labels'
    )
  );
  assert.ok(
    api.calls.includes(
      'DELETE https://api.github.com/repos/ProductDNA-CH/frontend/issues/4206/labels/sprint%2023'
    )
  );
  assert.ok(
    !api.calls.some((c) => c.includes('/folder/')),
    'no folder lookup when a ticket resolves'
  );
});

test('run: a title without a ticket defaults to the active sprint', async () => {
  const api = fakeApi({ prLabels: [] });
  const result = await run(
    { ...baseEnv, PR_TITLE: 'chore: add verify-frontend verification skill' },
    { fetch: api.fetch, now: new Date('2026-10-08T10:00:00Z'), ...quiet }
  );
  assert.deepEqual(result, { wanted: ['sprint 24'], add: ['sprint 24'], remove: [] });
  assert.ok(
    api.calls.some((c) => c.includes(`/folder/${FOLDER}/list`)),
    'looks up the folder lists'
  );
});

test('run: a ticket outside any sprint (Backlog) also defaults to the active sprint', async () => {
  const api = fakeApi({ tasks: { 'CORE-1': { list: { name: 'Backlog' } } } });
  const result = await run(
    { ...baseEnv, PR_TITLE: 'fix(ui): [CORE-1] x' },
    { fetch: api.fetch, now: new Date('2026-10-08T10:00:00Z'), ...quiet }
  );
  assert.deepEqual(result.wanted, ['sprint 24']);
});

test('run: labels every sprint when the title names tickets from two sprints', async () => {
  const api = fakeApi({
    tasks: {
      'CORE-1': { list: { name: 'Sprint 24(9/28 - 10/18)' } },
      'CORE-2': { list: { name: 'Sprint 25 (10/19 - 11/8)' } },
    },
  });
  const result = await run(
    { ...baseEnv, PR_TITLE: 'fix(ui): [CORE-1] [CORE-2] x' },
    { fetch: api.fetch, now: new Date('2026-10-08T10:00:00Z'), ...quiet }
  );
  assert.deepEqual(result.wanted, ['sprint 24', 'sprint 25']);
});

test('run: is a no-op on GitHub when the label is already right', async () => {
  const api = fakeApi({
    tasks: { 'CORE-7895': { list: { name: 'Sprint 24(9/28 - 10/18)' } } },
    prLabels: ['sprint 24'],
  });
  const result = await run(
    { ...baseEnv, PR_TITLE: 'fix(ui): [CORE-7895] x' },
    { fetch: api.fetch, now: new Date('2026-10-08T10:00:00Z'), ...quiet }
  );
  assert.deepEqual(result, { wanted: ['sprint 24'], add: [], remove: [] });
  assert.ok(!api.calls.some((c) => c.startsWith('POST') || c.startsWith('DELETE')));
});

test('run: when ClickUp is down, nothing is removed and nothing fails', async () => {
  const api = fakeApi({ clickupDown: true, prLabels: ['sprint 23'] });
  const warnings = [];
  const result = await run(
    { ...baseEnv, PR_TITLE: 'fix(ui): [CORE-7895] x' },
    {
      fetch: api.fetch,
      now: new Date('2026-10-08T10:00:00Z'),
      log: () => {},
      warn: (m) => warnings.push(m),
    }
  );
  assert.deepEqual(result, { wanted: [], add: [], remove: [] });
  assert.ok(warnings.length > 0, 'warns about the ClickUp failure');
  assert.ok(!api.calls.some((c) => c.startsWith('DELETE')), 'keeps the existing sprint label');
});

test('run: an unknown ticket id is skipped, and the active sprint is used instead', async () => {
  const api = fakeApi({ tasks: {} });
  const warnings = [];
  const result = await run(
    { ...baseEnv, PR_TITLE: 'fix(ui): [CORE-999999] x' },
    {
      fetch: api.fetch,
      now: new Date('2026-10-08T10:00:00Z'),
      log: () => {},
      warn: (m) => warnings.push(m),
    }
  );
  assert.deepEqual(result.wanted, ['sprint 24']);
  assert.ok(warnings.some((m) => m.includes('CORE-999999')));
});

test('run: without a ClickUp token (fork PR) it does nothing', async () => {
  const api = fakeApi();
  const result = await run(
    { ...baseEnv, CLICKUP_TOKEN: '', PR_TITLE: 'fix(ui): [CORE-7895] x' },
    { fetch: api.fetch, now: new Date('2026-10-08T10:00:00Z'), ...quiet }
  );
  assert.deepEqual(result, { wanted: [], add: [], remove: [] });
  assert.deepEqual(api.calls, []);
});

test('run: DRY_RUN resolves and reports but never writes to GitHub', async () => {
  const api = fakeApi({
    tasks: { 'CORE-7895': { list: { name: 'Sprint 24(9/28 - 10/18)' } } },
    prLabels: ['sprint 23'],
  });
  const result = await run(
    { ...baseEnv, DRY_RUN: '1', PR_TITLE: 'fix(ui): [CORE-7895] x' },
    { fetch: api.fetch, now: new Date('2026-10-08T10:00:00Z'), ...quiet }
  );
  assert.deepEqual(result, { wanted: ['sprint 24'], add: ['sprint 24'], remove: ['sprint 23'] });
  assert.ok(!api.calls.some((c) => c.startsWith('POST') || c.startsWith('DELETE')));
});

test('run: a GitHub write failure throws (the job must go red)', async () => {
  const api = fakeApi({ tasks: { 'CORE-7895': { list: { name: 'Sprint 24(9/28 - 10/18)' } } } });
  const failing = async (url, init) => {
    if (String(url).includes('/issues/4206/labels') && init?.method === 'POST') {
      return { ok: false, status: 403, json: async () => ({}), text: async () => 'forbidden' };
    }
    return api.fetch(url, init);
  };
  await assert.rejects(
    run(
      { ...baseEnv, PR_TITLE: 'fix(ui): [CORE-7895] x' },
      { fetch: failing, now: new Date(), ...quiet }
    ),
    /403/
  );
});
