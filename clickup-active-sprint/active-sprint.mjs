// Resolves the ClickUp sprint active today and prints it as the `sprint N`
// label clickup-sprint-label puts on pull requests.
//
// The rules are clickup-sprint-label's: among the lists of the sprint folder,
// the sprint whose dates (start_date/due_date, else the `(M/D - M/D)` of its
// name) cover today in the sprint timezone; the highest-numbered one when two
// overlap. They are imported from that action's module rather than copied.
//
// Unlike the label action this one fails, with exit 1, when ClickUp cannot be
// read or no sprint is active: a consumer gating a release on the answer must
// not get an empty one silently.
//
// Environment:
//   CLICKUP_TOKEN             ClickUp API token (pk_…).
//   CLICKUP_SPRINT_FOLDER_ID  folder whose lists are the sprints.
//   SPRINT_TZ                 timezone of the sprint calendar (default Europe/Zurich).
//
// Outputs (GITHUB_OUTPUT): label (`sprint 24`), number (`24`).
// Tests: node --test clickup-active-sprint/tests/active-sprint.test.mjs

import { appendFileSync } from 'node:fs';

import { activeSprintLabel, todayIn } from '../clickup-sprint-label/sprint-label.mjs';

const DEFAULT_SPRINT_FOLDER_ID = '90159037608'; // "Core plateform"
const DEFAULT_TZ = 'Europe/Zurich';

export async function run(env, deps = {}) {
  const fetchImpl = deps.fetch ?? globalThis.fetch;
  const log = deps.log ?? ((m) => console.log(m));
  const now = deps.now ?? new Date();
  const tz = env.SPRINT_TZ || DEFAULT_TZ;
  const folderId = env.CLICKUP_SPRINT_FOLDER_ID || DEFAULT_SPRINT_FOLDER_ID;

  if (!env.CLICKUP_TOKEN) throw new Error('CLICKUP_TOKEN is required');

  const path = `/folder/${folderId}/list?archived=false`;
  const res = await fetchImpl(`https://api.clickup.com/api/v2${path}`, {
    headers: { Authorization: env.CLICKUP_TOKEN, Accept: 'application/json' },
  });
  if (!res.ok) throw new Error(`ClickUp ${res.status} on ${path}: ${(await res.text()).slice(0, 200)}`);
  const lists = (await res.json()).lists ?? [];

  const today = todayIn(tz, now);
  const label = activeSprintLabel(lists, today, tz);
  if (!label) {
    throw new Error(`no sprint is active on ${today.join('-')} (${tz}) among ${lists.length} lists of folder ${folderId}`);
  }
  log(`active sprint on ${today.join('-')} (${tz}): ${label}`);
  return { label, number: Number(label.slice('sprint '.length)) };
}

if (import.meta.url === `file://${process.argv[1]}`) {
  run(process.env)
    .then(({ label, number }) => {
      if (process.env.GITHUB_OUTPUT) appendFileSync(process.env.GITHUB_OUTPUT, `label=${label}\nnumber=${number}\n`);
    })
    .catch((error) => {
      console.log(`::error::${error.message}`);
      process.exitCode = 1;
    });
}
