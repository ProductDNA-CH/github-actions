import assert from 'node:assert/strict';
import { test } from 'node:test';

import { run } from '../active-sprint.mjs';

// The real list names of the "Core plateform" folder on 2026-10-08.
const LISTS = [
  { id: '1', name: 'Roadmap' },
  { id: '2', name: 'Bugs & Requests' },
  { id: '3', name: 'Sprint 23 (9/14 - 9/24)' },
  { id: '4', name: 'Sprint 24(9/28 - 10/18)' },
  { id: '5', name: 'Sprint 25 (10/19 - 11/8)' },
  { id: '6', name: 'Backlog' },
];

const FOLDER = '90159037608';

function fakeApi({ lists = LISTS, status = 200 } = {}) {
  const calls = [];
  const fetch = async (url, init = {}) => {
    calls.push({ url, headers: init.headers ?? {} });
    return {
      ok: status >= 200 && status < 300,
      status,
      json: async () => ({ lists }),
      text: async () => JSON.stringify({ lists }),
    };
  };
  return { fetch, calls };
}

const env = { CLICKUP_TOKEN: 'pk_test', CLICKUP_SPRINT_FOLDER_ID: FOLDER };
const quiet = { log: () => {} };

test('resolves the sprint active today from the folder lists', async () => {
  const api = fakeApi();
  const result = await run(env, { fetch: api.fetch, now: new Date('2026-10-08T10:00:00Z'), ...quiet });
  assert.deepEqual(result, { label: 'sprint 24', number: 24 });
  assert.equal(api.calls.length, 1);
  assert.equal(api.calls[0].url, `https://api.clickup.com/api/v2/folder/${FOLDER}/list?archived=false`);
  assert.equal(api.calls[0].headers.Authorization, 'pk_test');
});

test('the next sprint becomes active on its first day, in the sprint timezone', async () => {
  const api = fakeApi();
  // 23:30 UTC on the 18th is already the 19th in Zurich.
  const result = await run(env, { fetch: api.fetch, now: new Date('2026-10-18T23:30:00Z'), ...quiet });
  assert.deepEqual(result, { label: 'sprint 25', number: 25 });
});

test('fails when no sprint covers today (the gap between two sprints)', async () => {
  const api = fakeApi();
  await assert.rejects(
    run(env, { fetch: api.fetch, now: new Date('2026-09-26T10:00:00Z'), ...quiet }),
    /no sprint is active/
  );
});

test('fails when ClickUp answers an error', async () => {
  const api = fakeApi({ status: 500 });
  await assert.rejects(run(env, { fetch: api.fetch, now: new Date(), ...quiet }), /ClickUp 500/);
});

test('fails without a ClickUp token', async () => {
  const api = fakeApi();
  await assert.rejects(run({ ...env, CLICKUP_TOKEN: '' }, { fetch: api.fetch, now: new Date(), ...quiet }), /CLICKUP_TOKEN/);
  assert.equal(api.calls.length, 0);
});

test('honours a custom folder id', async () => {
  const api = fakeApi();
  await run({ ...env, CLICKUP_SPRINT_FOLDER_ID: '42' }, { fetch: api.fetch, now: new Date('2026-10-08T10:00:00Z'), ...quiet });
  assert.ok(api.calls[0].url.includes('/folder/42/list'));
});
