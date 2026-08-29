#!/usr/bin/env node
/**
 * Seed sample patients (and their scheduled visits) on the Notenra server.
 *
 * WHY VISITS ARE CREATED BY DEFAULT
 * ---------------------------------
 * `GET /patients` INNER JOINs visits, so a patient with no visit row is
 * invisible to the clinician in BOTH the app and the web portal. A scheduled
 * visit is only an appointment slot — it holds no audio. When the clinician
 * later taps Record, ClinicalService reuses that open un-recorded visit rather
 * than creating a second one, so seeding shells does not "pre-record" anything.
 * Pass --no-visits to skip them, but expect the patients not to show up.
 *
 * USAGE
 *   node tool/seed_patients.js --email <clinician> --password <pw> --confirm
 *
 * OPTIONS
 *   --email <s>         clinician login (or env NOTENRA_EMAIL)
 *   --password <s>      password         (or env NOTENRA_PASSWORD)
 *   --token <s>         use an existing JWT instead of logging in
 *   --base <url>        API base (default https://app.notenra.com/api)
 *   --per-day <n>       patients per day        (default 40)
 *   --days <n>          number of days          (default 5)
 *   --start-offset <n>  0 = start today, 1 = tomorrow (default 0)
 *   --prefix <s>        name/MRN prefix so seeded rows are identifiable
 *                       (default "ZZTest")
 *   --delay <ms>        pause between writes, for rate limits (default 250)
 *   --no-visits         create patients only (they will be invisible)
 *   --dry-run           print what would be created, write nothing
 *   --confirm           REQUIRED to actually write to the server
 *
 * Every created id is appended to tool/seeded-patients.log so the rows can be
 * found and cleaned up later.
 */

const fs = require('fs');
const path = require('path');

// ---------------------------------------------------------------- args

function parseArgs(argv) {
  const out = {
    base: process.env.NOTENRA_API || 'https://app.notenra.com/api',
    email: process.env.NOTENRA_EMAIL || null,
    password: process.env.NOTENRA_PASSWORD || null,
    token: process.env.NOTENRA_TOKEN || null,
    perDay: 40,
    days: 5,
    startOffset: 0,
    prefix: 'ZZTest',
    delay: 250,
    visits: true,
    dryRun: false,
    confirm: false,
  };
  for (let i = 2; i < argv.length; i++) {
    const a = argv[i];
    const next = () => argv[++i];
    switch (a) {
      case '--email': out.email = next(); break;
      case '--password': out.password = next(); break;
      case '--token': out.token = next(); break;
      case '--base': out.base = next(); break;
      case '--per-day': out.perDay = parseInt(next(), 10); break;
      case '--days': out.days = parseInt(next(), 10); break;
      case '--start-offset': out.startOffset = parseInt(next(), 10); break;
      case '--prefix': out.prefix = next(); break;
      case '--delay': out.delay = parseInt(next(), 10); break;
      case '--no-visits': out.visits = false; break;
      case '--dry-run': out.dryRun = true; break;
      case '--confirm': out.confirm = true; break;
      case '--help': case '-h': out.help = true; break;
      default:
        console.error(`Unknown option: ${a}`);
        process.exit(2);
    }
  }
  return out;
}

// ---------------------------------------------------------------- data

const FIRST = [
  'Amelia', 'Noah', 'Priya', 'Marcus', 'Sofia', 'Liam', 'Zara', 'Elias',
  'Rania', 'Tobias', 'Ingrid', 'Omar', 'Freya', 'Kenji', 'Aisha', 'Viktor',
  'Nadia', 'Caleb', 'Yusuf', 'Marta', 'Dexter', 'Leila', 'Hugo', 'Simone',
  'Idris', 'Paloma', 'Anders', 'Rosa', 'Malik', 'Greta',
];
const LAST = [
  'Whitfield', 'Okonkwo', 'Lindqvist', 'Rahman', 'Delacroix', 'Yamamoto',
  'Ferreira', 'Novak', 'Abadi', 'Sinclair', 'Moreau', 'Petrov', 'Haddad',
  'Bergstrom', 'Castellanos', 'Nakamura', 'Fairbanks', 'Osei', 'Varga',
  'Kowalski',
];

const VISIT_TYPES = ['Follow-up', 'New Patient', 'Virtual Visit'];

const pad = (n, w = 2) => String(n).padStart(w, '0');
const ymd = (d) => `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;

/** Slots spread across a working day: 09:00 onward, evenly divided. */
function slotTime(index, perDay) {
  const startMin = 9 * 60;
  const endMin = 17 * 60;
  const step = Math.max(5, Math.floor((endMin - startMin) / Math.max(1, perDay)));
  const t = startMin + index * step;
  return `${pad(Math.floor(t / 60))}:${pad(t % 60)}`;
}

function makePatient(seq, prefix) {
  // Both indices vary with seq AND with the block number, so the pair doesn't
  // repeat every lcm(30,20)=60 patients — 200 rows come out with no duplicate
  // full names.
  const first = FIRST[(seq * 7) % FIRST.length];
  const last = LAST[(seq * 3 + Math.floor(seq / FIRST.length)) % LAST.length];
  // Deterministic pseudo-DOB so re-runs are comparable.
  const year = 1945 + ((seq * 7) % 60);
  const month = 1 + ((seq * 3) % 12);
  const day = 1 + ((seq * 5) % 28);
  return {
    name: `${first} ${last} (${prefix})`,
    mrn: `${prefix}-${pad(seq, 5)}`,
    dob: `${year}-${pad(month)}-${pad(day)}`,
  };
}

// ---------------------------------------------------------------- http

class Api {
  constructor(base, delayMs) {
    this.base = base.replace(/\/+$/, '');
    this.delayMs = delayMs;
    this.token = null;
    this.csrf = null;
    this.csrfCookie = '__Host-csrf_token';
    this.sessionCookie = null;
  }

  sleep(ms) { return new Promise((r) => setTimeout(r, ms)); }

  /** Fetch with CSRF double-submit, bearer auth, and 429 backoff. */
  async request(method, pathname, body, attempt = 0) {
    const headers = { Accept: 'application/json' };
    const cookies = [];
    if (body !== undefined) headers['Content-Type'] = 'application/json';
    if (this.token) headers['Authorization'] = `Bearer ${this.token}`;
    if (method !== 'GET') {
      if (!this.csrf) await this.loadCsrf();
      if (this.csrf) {
        headers['x-csrf-token'] = this.csrf;
        cookies.push(`${this.csrfCookie}=${this.csrf}`);
      }
    }
    if (this.sessionCookie) cookies.push(this.sessionCookie);
    if (cookies.length) headers['Cookie'] = cookies.join('; ');

    const res = await fetch(`${this.base}${pathname}`, {
      method,
      headers,
      body: body === undefined ? undefined : JSON.stringify(body),
      redirect: 'manual',
    });

    // Capture a rotated session cookie if the server issues one.
    const setCookie = res.headers.getSetCookie ? res.headers.getSetCookie() : [];
    for (const c of setCookie) {
      // Any conventionally-named session cookie, with or without a prefix.
      const m = /(?:__Host-|__Secure-)?[A-Za-z0-9_.-]*session=([^;]+)/i.exec(c);
      if (m) {
        this.sessionCookie = c.split(';')[0];
        if (!this.token) this.token = m[1];
      }
    }

    const text = await res.text();
    let data = null;
    try { data = text ? JSON.parse(text) : null; } catch { data = text; }

    // A 200 carrying HTML is a gateway page, not a real success.
    if (typeof data === 'string' && /^\s*<(!doctype|html)/i.test(data)) {
      throw new Error(`Gateway returned HTML (status ${res.status}) — backend unreachable`);
    }

    // Rate limited / transient: back off and retry.
    if ((res.status === 429 || res.status >= 500) && attempt < 5) {
      const wait = Math.min(30000, 1000 * Math.pow(2, attempt));
      console.warn(`  ! ${res.status} on ${method} ${pathname} — retrying in ${wait}ms`);
      await this.sleep(wait);
      return this.request(method, pathname, body, attempt + 1);
    }

    // A stale CSRF token: refresh once and replay.
    if (res.status === 403 && attempt < 2 &&
        JSON.stringify(data || '').toLowerCase().includes('csrf')) {
      await this.loadCsrf();
      return this.request(method, pathname, body, attempt + 1);
    }

    if (!res.ok) {
      const msg = (data && (data.error || data.message)) || `HTTP ${res.status}`;
      const err = new Error(msg);
      err.status = res.status;
      err.data = data;
      throw err;
    }
    return data;
  }

  async loadCsrf() {
    const d = await this.request('GET', '/csrf-token');
    if (d && d.csrfToken) {
      this.csrf = d.csrfToken;
      if (d.cookieName) this.csrfCookie = d.cookieName;
    }
  }

  async login(email, password) {
    const d = await this.request('POST', '/auth/login', { email, password });
    if (d && (d.temporaryToken || d.tempToken)) {
      throw new Error(
        'This account must clear a first-login gate (password change, PHI ' +
        'training, or MFA) before the API will accept it. Sign in once in the ' +
        'app to clear it, or use --token with a session JWT.');
    }
    const tok = d && (d.token || d.jwt || d.accessToken);
    if (tok) this.token = tok;
    if (!this.token) {
      throw new Error('Login returned no session token.');
    }
    return d && d.user;
  }

  createPatient(p) {
    return this.request('POST', '/patients', {
      name: p.name, mrn: p.mrn, date_of_birth: p.dob,
    });
  }

  createVisit(patientId, date, time, type) {
    return this.request('POST', '/visits', {
      patient_id: patientId, visit_date: date, visit_time: time, visit_type: type,
    });
  }
}

// ---------------------------------------------------------------- main

async function main() {
  const opt = parseArgs(process.argv);
  if (opt.help) {
    console.log(fs.readFileSync(__filename, 'utf8').split('*/')[0]);
    return;
  }

  const total = opt.perDay * opt.days;
  const plan = [];
  for (let d = 0; d < opt.days; d++) {
    const date = new Date();
    date.setHours(12, 0, 0, 0);
    date.setDate(date.getDate() + opt.startOffset + d);
    for (let i = 0; i < opt.perDay; i++) {
      const seq = d * opt.perDay + i + 1;
      plan.push({
        ...makePatient(seq, opt.prefix),
        date: ymd(date),
        time: slotTime(i, opt.perDay),
        type: VISIT_TYPES[seq % VISIT_TYPES.length],
      });
    }
  }

  console.log(`Target      : ${opt.base}`);
  console.log(`Plan        : ${opt.perDay}/day x ${opt.days} days = ${total} patients`);
  console.log(`Visits      : ${opt.visits ? 'yes (scheduled shells, no audio)' : 'NO — patients will be invisible in the app'}`);
  console.log(`Date range  : ${plan[0].date} .. ${plan[plan.length - 1].date}`);
  console.log(`Name/MRN    : "${plan[0].name}" / ${plan[0].mrn}`);
  console.log(`Writes      : ${opt.visits ? total * 2 : total} requests @ ${opt.delay}ms apart`);
  console.log('');

  if (opt.dryRun) {
    console.log('--dry-run: nothing was written. First 5 planned rows:');
    for (const p of plan.slice(0, 5)) {
      console.log(`  ${p.date} ${p.time}  ${p.mrn}  ${p.name}  [${p.type}]`);
    }
    return;
  }
  if (!opt.confirm) {
    console.error('Refusing to write without --confirm. Re-run with --confirm ' +
      '(or --dry-run to preview).');
    process.exit(1);
  }

  const api = new Api(opt.base, opt.delay);
  if (opt.token) {
    api.token = opt.token;
    console.log('Using the supplied token.');
  } else {
    if (!opt.email || !opt.password) {
      console.error('Need --email and --password (or --token).');
      process.exit(2);
    }
    const user = await api.login(opt.email, opt.password);
    console.log(`Signed in as ${(user && (user.email || user.name)) || opt.email}`);
  }

  const logPath = path.join(__dirname, 'seeded-patients.log');
  const log = (line) => fs.appendFileSync(logPath, line + '\n', 'utf8');
  log(`--- run ${new Date().toISOString()} base=${opt.base} ---`);

  let madePatients = 0, madeVisits = 0, failed = 0;
  for (const p of plan) {
    try {
      const created = await api.createPatient(p);
      const obj = (created && (created.patient || created.data)) || created;
      const pid = obj && (obj.id ?? obj.patient_id);
      if (!pid) throw new Error('No patient id in response');
      madePatients++;
      log(`patient ${pid} ${p.mrn} ${p.name}`);

      if (opt.visits) {
        await api.sleep(opt.delay);
        const v = await api.createVisit(pid, p.date, p.time, p.type);
        const vobj = (v && (v.visit || v.data)) || v;
        const vid = vobj && (vobj.id ?? vobj.visit_id);
        madeVisits++;
        log(`visit   ${vid} patient=${pid} ${p.date} ${p.time} ${p.type}`);
      }
      if ((madePatients % 10) === 0) {
        console.log(`  ${madePatients}/${total} patients, ${madeVisits} visits`);
      }
    } catch (e) {
      failed++;
      console.error(`  x ${p.mrn}: ${e.message}`);
      log(`FAILED  ${p.mrn} ${e.message}`);
      if (e.status === 401) {
        console.error('Session rejected — stopping.');
        break;
      }
    }
    await api.sleep(opt.delay);
  }

  console.log('');
  console.log(`Done. patients=${madePatients} visits=${madeVisits} failed=${failed}`);
  console.log(`Log: ${logPath}`);
}

main().catch((e) => {
  console.error(`\nFATAL: ${e.message}`);
  process.exit(1);
});
