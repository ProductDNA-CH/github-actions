// Keeps a pull request's `sprint N` label in step with ClickUp.
//
// The ticket ids are read from the PR title (`[CORE-7895]`), each task is
// fetched from ClickUp, and the sprint is the sprint list the task sits in:
// its home list, or one of its secondary locations (ClickUp lets a task live
// in several lists). A sprint list is any list named `Sprint <number>…`, such
// as `Sprint 24(9/28 - 10/18)`; the label is the lowercase `sprint 24`, which
// is also how the release branches (`release/sprint-24`) spell it.
//
// When no ticket resolves to a sprint (no id in the title, a Backlog ticket,
// an id ClickUp does not know) the PR gets the sprint that is active today:
// the sprint list of the configured folder whose dates cover today, read from
// the list's start_date/due_date when ClickUp has them, else from the
// `(M/D - M/D)` range in its name. "Today" is the calendar date in
// Europe/Zurich, where the sprints are planned, not on the UTC runner.
//
// Only `sprint N` labels are ever touched: the wanted ones are added, the
// stale ones removed, everything else is left alone. A ClickUp failure is a
// warning and never removes a label (the resolution is incomplete); a GitHub
// failure throws, so the job goes red and someone sees it.
//
// Environment:
//   CLICKUP_TOKEN             ClickUp API token (pk_…). Empty -> no-op (fork PRs).
//   CLICKUP_TEAM_ID           workspace id, for custom task ids.
//   CLICKUP_SPRINT_FOLDER_ID  folder whose lists are the sprints.
//   GITHUB_TOKEN              token with pull-requests/issues write.
//   GITHUB_REPOSITORY         owner/repo
//   PR_NUMBER, PR_TITLE       the pull request to label.
//   ID_PREFIX                 ticket id prefix (default CORE).
//   SPRINT_TZ                 timezone of the sprint calendar (default Europe/Zurich).
//   DRY_RUN=1                 resolve and report, write nothing.
//
// action.yaml maps the action inputs onto these variables.
//
// Tests: node --test clickup-sprint-label/tests/sprint-label.test.mjs

export const LABEL_COLOR = '1d76db';
export const LABEL_DESCRIPTION = 'ClickUp sprint of the ticket in the PR title';

const DEFAULT_TEAM_ID = '90151502952';
const DEFAULT_SPRINT_FOLDER_ID = '90159037608'; // "Core plateform"
const DEFAULT_TZ = 'Europe/Zurich';

const SPRINT_LABEL_RE = /^sprint \d+$/i;
const SPRINT_LIST_RE = /^\s*sprint\s*(\d+)/i;
const NAME_RANGE_RE = /\((\d{1,2})\/(\d{1,2})\s*-\s*(\d{1,2})\/(\d{1,2})\)/;

// --- pure helpers ----------------------------------------------------------

// Every distinct `<prefix>-<digits>` in `text`, in order of first appearance.
export function extractTaskIds(text, prefix = 'CORE') {
  const re = new RegExp(`\\b${prefix}-\\d+\\b`, 'g');
  return [...new Set(String(text ?? '').match(re) ?? [])];
}

// `Sprint 24(9/28 - 10/18)` -> `sprint 24`; anything else -> null.
export function sprintLabel(listName) {
  const m = SPRINT_LIST_RE.exec(String(listName ?? ''));
  return m ? `sprint ${Number(m[1])}` : null;
}

function sprintNumber(label) {
  return Number(label.slice('sprint '.length));
}

// The sprint labels of every list a task sits in (home list + locations).
export function taskSprintLabels(task) {
  const names = [task?.list?.name, ...(task?.locations ?? []).map((l) => l?.name)];
  return [...new Set(names.map(sprintLabel).filter(Boolean))];
}

// [year, month, day] of `now` in `tz`.
export function todayIn(tz, now = new Date()) {
  const parts = new Intl.DateTimeFormat('en-CA', {
    timeZone: tz,
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
  }).formatToParts(now);
  const get = (type) => Number(parts.find((p) => p.type === type).value);
  return [get('year'), get('month'), get('day')];
}

function compareDates(a, b) {
  for (let i = 0; i < 3; i += 1) {
    if (a[i] !== b[i]) return a[i] < b[i] ? -1 : 1;
  }
  return 0;
}

function covers(range, today) {
  return compareDates(range.start, today) <= 0 && compareDates(today, range.end) <= 0;
}

// The date range of a sprint list as [y, m, d] tuples, or null when unknown.
// Prefers the list's own dates; falls back to the `(M/D - M/D)` of its name,
// whose year is inferred from `today` (a range that wraps the year end runs
// into the next year, and is tried a year earlier too so that a sprint that
// started in December is still active in January).
function listDateRange(list, today, tz) {
  if (list.start_date && list.due_date) {
    return {
      start: todayIn(tz, new Date(Number(list.start_date))),
      end: todayIn(tz, new Date(Number(list.due_date))),
    };
  }
  const m = NAME_RANGE_RE.exec(String(list.name ?? ''));
  if (!m) return null;
  const [sm, sd, em, ed] = m.slice(1).map(Number);
  const wraps = em < sm || (em === sm && ed < sd);
  for (const year of [today[0], today[0] - 1]) {
    const range = { start: [year, sm, sd], end: [wraps ? year + 1 : year, em, ed] };
    if (covers(range, today)) return range;
  }
  return null;
}

// The `sprint N` label of the sprint active on `today`, or null. When several
// sprints cover the day (an overlap, or year-less names that repeat) the
// highest-numbered one is the current one.
export function activeSprintLabel(lists, today, tz = DEFAULT_TZ) {
  const active = (lists ?? [])
    .filter((l) => !l.archived)
    .map((l) => ({ label: sprintLabel(l.name), range: listDateRange(l, today, tz) }))
    .filter((l) => l.label && l.range && covers(l.range, today))
    .map((l) => l.label)
    .sort((a, b) => sprintNumber(b) - sprintNumber(a));
  return active[0] ?? null;
}

// What to add and remove so that the PR's sprint labels are exactly `wanted`.
// Non-sprint labels are never part of the answer.
export function diffSprintLabels(current, wanted) {
  const lower = (s) => s.toLowerCase();
  const currentSprints = current.filter((l) => SPRINT_LABEL_RE.test(l));
  const have = new Set(currentSprints.map(lower));
  const want = new Set(wanted.map(lower));
  return {
    add: wanted.filter((l) => !have.has(lower(l))),
    remove: currentSprints.filter((l) => !want.has(lower(l))),
  };
}

// --- API clients -----------------------------------------------------------

function clickupClient({ token, teamId, fetch }) {
  const get = async (path) => {
    const res = await fetch(`https://api.clickup.com/api/v2${path}`, {
      headers: { Authorization: token, Accept: 'application/json' },
    });
    if (!res.ok) {
      const error = new Error(
        `ClickUp ${res.status} on ${path}: ${(await res.text()).slice(0, 200)}`
      );
      error.status = res.status;
      throw error;
    }
    return res.json();
  };
  return {
    task: (id) => get(`/task/${encodeURIComponent(id)}?custom_task_ids=true&team_id=${teamId}`),
    folderLists: (folderId) =>
      get(`/folder/${folderId}/list?archived=false`).then((b) => b.lists ?? []),
  };
}

function githubClient({ token, repo, fetch }) {
  const call = async (method, path, body) => {
    const res = await fetch(`https://api.github.com/repos/${repo}${path}`, {
      method,
      headers: {
        Authorization: `Bearer ${token}`,
        Accept: 'application/vnd.github+json',
        'X-GitHub-Api-Version': '2022-11-28',
        ...(body ? { 'Content-Type': 'application/json' } : {}),
      },
      body: body ? JSON.stringify(body) : undefined,
    });
    return res;
  };
  const must = async (res, what) => {
    if (!res.ok)
      throw new Error(`GitHub ${res.status} while ${what}: ${(await res.text()).slice(0, 200)}`);
    return res;
  };
  return {
    prLabels: async (pr) => {
      const res = await must(
        await call('GET', `/issues/${pr}/labels?per_page=100`),
        'reading the PR labels'
      );
      return (await res.json()).map((l) => l.name);
    },
    // Creating through the issues endpoint would give the label GitHub's
    // default grey; create it explicitly, and accept "already exists".
    ensureLabel: async (name) => {
      const res = await call('POST', '/labels', {
        name,
        color: LABEL_COLOR,
        description: LABEL_DESCRIPTION,
      });
      if (res.status === 422) return;
      await must(res, `creating the label "${name}"`);
    },
    addLabels: async (pr, labels) =>
      must(await call('POST', `/issues/${pr}/labels`, { labels }), 'adding labels'),
    removeLabel: async (pr, name) => {
      const res = await call('DELETE', `/issues/${pr}/labels/${encodeURIComponent(name)}`);
      if (res.status === 404) return; // already gone
      await must(res, `removing the label "${name}"`);
    },
  };
}

// --- orchestration ---------------------------------------------------------

export async function run(env, deps = {}) {
  const fetchImpl = deps.fetch ?? globalThis.fetch;
  const log = deps.log ?? ((m) => console.log(m));
  const warn = deps.warn ?? ((m) => console.log(`::warning::${m}`));
  const now = deps.now ?? new Date();
  const nothing = { wanted: [], add: [], remove: [] };

  const pr = env.PR_NUMBER;
  const title = env.PR_TITLE ?? '';
  const dryRun = env.DRY_RUN === '1';
  const tz = env.SPRINT_TZ || DEFAULT_TZ;

  if (!env.CLICKUP_TOKEN) {
    warn('CLICKUP_TOKEN is empty (a PR from a fork has no secrets): leaving the labels alone');
    return nothing;
  }
  if (!pr || !env.GITHUB_TOKEN || !env.GITHUB_REPOSITORY) {
    throw new Error('PR_NUMBER, GITHUB_TOKEN and GITHUB_REPOSITORY are required');
  }

  const clickup = clickupClient({
    token: env.CLICKUP_TOKEN,
    teamId: env.CLICKUP_TEAM_ID || DEFAULT_TEAM_ID,
    fetch: fetchImpl,
  });
  const github = githubClient({
    token: env.GITHUB_TOKEN,
    repo: env.GITHUB_REPOSITORY,
    fetch: fetchImpl,
  });

  // 1. The sprints of the tickets named in the title.
  const ids = extractTaskIds(title, env.ID_PREFIX || 'CORE');
  let clickupFailed = false;
  const wanted = new Set();
  for (const id of ids) {
    try {
      const sprints = taskSprintLabels(await clickup.task(id));
      log(`${id}: ${sprints.length ? sprints.join(', ') : 'in no sprint list'}`);
      sprints.forEach((s) => wanted.add(s));
    } catch (error) {
      // 404 is an answer (no such task: a typo in the title), not an outage.
      if (error.status !== 404) clickupFailed = true;
      warn(`${id}: ${error.message}`);
    }
  }

  // 2. Nothing resolved: the sprint active today.
  if (wanted.size === 0) {
    if (clickupFailed) {
      warn('ClickUp could not be read for the ticket(s): leaving the labels alone');
      return nothing;
    }
    try {
      const lists = await clickup.folderLists(
        env.CLICKUP_SPRINT_FOLDER_ID || DEFAULT_SPRINT_FOLDER_ID
      );
      const active = activeSprintLabel(lists, todayIn(tz, now), tz);
      const dated = lists.some((l) => l.start_date && l.due_date);
      log(
        `${lists.length} lists in the sprint folder, dates ${dated ? 'from ClickUp' : 'from the list names'}`
      );
      const why = ids.length ? 'no ticket in a sprint' : 'no ticket in the title';
      if (active) {
        log(`${why}: defaulting to the active sprint, ${active}`);
        wanted.add(active);
      } else {
        log(`${why}, and no sprint is active today`);
      }
    } catch (error) {
      warn(`${error.message}: leaving the labels alone`);
      return nothing;
    }
  }

  // 3. Make the PR's sprint labels match.
  const want = [...wanted].sort((a, b) => sprintNumber(a) - sprintNumber(b));
  const current = await github.prLabels(pr);
  const { add, remove } = diffSprintLabels(current, want);
  // A sprint label still present after a ClickUp failure may be right; a
  // failed lookup is no evidence that it is wrong.
  const removals = clickupFailed ? [] : remove;
  const result = { wanted: want, add, remove: removals };

  if (add.length === 0 && removals.length === 0) {
    log(`#${pr}: already labelled ${want.join(', ') || 'with no sprint'}`);
    return result;
  }
  if (dryRun) {
    log(`#${pr}: WOULD add [${add.join(', ')}] and remove [${removals.join(', ')}]`);
    return result;
  }
  for (const name of add) await github.ensureLabel(name);
  if (add.length) await github.addLabels(pr, add);
  for (const name of removals) await github.removeLabel(pr, name);
  log(`#${pr}: added [${add.join(', ')}], removed [${removals.join(', ')}]`);
  return result;
}

if (import.meta.url === `file://${process.argv[1]}`) {
  run(process.env).catch((error) => {
    console.log(`::error::${error.message}`);
    process.exitCode = 1;
  });
}
