// Focus Reels server: friends, weekly duels and remote-buddy approvals.
// No dependencies. Run: node server.js   (env: PORT=8787, HOST=127.0.0.1, DATA=./data.json)
// For real use put it behind HTTPS (e.g. a reverse proxy) and set HOST=0.0.0.0.
'use strict';
const http = require('http');
const fs = require('fs');
const crypto = require('crypto');

const PORT = Number(process.env.PORT || 8787);
const HOST = process.env.HOST || '127.0.0.1';
const DATA = process.env.DATA || './data.json';
const DAY_RE = /^\d{4}-\d{2}-\d{2}$/;

let db = { users: {}, codes: {}, requests: {} };
try { db = JSON.parse(fs.readFileSync(DATA, 'utf8')); } catch { /* first run */ }

function save() {
  const tmp = DATA + '.tmp';
  fs.writeFileSync(tmp, JSON.stringify(db));
  fs.renameSync(tmp, DATA);
}
const rid = (n = 12) => crypto.randomBytes(n).toString('hex');
const newCode = () => {
  const a = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  for (;;) {
    let c = '';
    for (let i = 0; i < 6; i++) c += a[crypto.randomInt(a.length)];
    if (!db.codes[c]) return c;
  }
};

// Very small per-IP rate limit: 120 requests per minute.
const hits = new Map();
function limited(ip) {
  const now = Date.now();
  const h = (hits.get(ip) || []).filter((t) => now - t < 60000);
  h.push(now);
  hits.set(ip, h);
  return h.length > 120;
}

function send(res, code, body) {
  const s = JSON.stringify(body);
  res.writeHead(code, { 'Content-Type': 'application/json', 'Content-Length': Buffer.byteLength(s) });
  res.end(s);
}

function readBody(req) {
  return new Promise((resolve, reject) => {
    let n = 0;
    const chunks = [];
    req.on('data', (c) => {
      n += c.length;
      if (n > 20000) { reject(new Error('too large')); req.destroy(); return; }
      chunks.push(c);
    });
    req.on('end', () => {
      if (!chunks.length) return resolve({});
      try { resolve(JSON.parse(Buffer.concat(chunks).toString('utf8'))); } catch (e) { reject(e); }
    });
  });
}

function auth(req) {
  const h = req.headers.authorization || '';
  const t = h.startsWith('Bearer ') ? h.slice(7) : '';
  if (!t) return null;
  return Object.values(db.users).find((u) => u.token === t) || null;
}

const today = (u, nowDay) => (u.days && u.days[nowDay]) || 0;
function weekTotal(u) {
  const keys = Object.keys(u.days || {}).sort().slice(-7);
  return keys.reduce((a, k) => a + u.days[k], 0);
}
const publicUser = (u, day) => ({
  userId: u.id, name: u.name, today: today(u, day), week: weekTotal(u), days: u.days || {},
});

const routes = {
  'POST /register': async (req, res, body) => {
    const name = String(body.name || '').trim().slice(0, 30);
    if (!name) return send(res, 400, { error: 'name required' });
    const id = rid(6);
    const u = { id, name, token: rid(24), code: newCode(), friends: [], buddyId: null, days: {} };
    db.users[id] = u;
    db.codes[u.code] = id;
    save();
    send(res, 200, { userId: id, token: u.token, code: u.code, name });
  },

  'GET /me': async (req, res, body, u) => send(res, 200, {
    userId: u.id, name: u.name, code: u.code, buddyId: u.buddyId,
    // People who chose me as their buddy, so the app knows to poll for approvals.
    buddyFor: Object.values(db.users).filter((x) => x.buddyId === u.id).map((x) => x.id),
  }),

  'POST /sync': async (req, res, body, u) => {
    const days = body.days && typeof body.days === 'object' ? body.days : {};
    for (const [k, v] of Object.entries(days)) {
      if (DAY_RE.test(k) && Number.isInteger(v) && v >= 0 && v < 100000) u.days[k] = v;
    }
    const keep = Object.keys(u.days).sort().slice(-14);
    for (const k of Object.keys(u.days)) if (!keep.includes(k)) delete u.days[k];
    save();
    send(res, 200, { ok: true });
  },

  'GET /friends': async (req, res, body, u, q) => {
    const day = DAY_RE.test(q.get('day') || '') ? q.get('day') : '';
    send(res, 200, {
      me: publicUser(u, day),
      friends: u.friends.map((id) => db.users[id]).filter(Boolean).map((f) => publicUser(f, day)),
    });
  },

  'POST /invite/accept': async (req, res, body, u) => {
    const code = String(body.code || '').trim().toUpperCase();
    const otherId = db.codes[code];
    const o = otherId && db.users[otherId];
    if (!o) return send(res, 404, { error: 'unknown code' });
    if (o.id === u.id) return send(res, 400, { error: 'that is your own code' });
    if (!u.friends.includes(o.id)) u.friends.push(o.id);
    if (!o.friends.includes(u.id)) o.friends.push(u.id);
    save();
    send(res, 200, { friend: { userId: o.id, name: o.name } });
  },

  'POST /friends/remove': async (req, res, body, u) => {
    const id = String(body.friendId || '');
    u.friends = u.friends.filter((x) => x !== id);
    const o = db.users[id];
    if (o) o.friends = o.friends.filter((x) => x !== u.id);
    if (u.buddyId === id) u.buddyId = null;
    if (o && o.buddyId === u.id) o.buddyId = null;
    save();
    send(res, 200, { ok: true });
  },

  'POST /buddy': async (req, res, body, u) => {
    const id = body.friendId ? String(body.friendId) : null;
    if (id && !u.friends.includes(id)) return send(res, 400, { error: 'not your friend' });
    if (id === null && u.buddyId && hasPending(u.id)) {
      return send(res, 409, { error: 'finish pending requests first' });
    }
    u.buddyId = id;
    save();
    send(res, 200, { buddyId: u.buddyId });
  },

  'POST /requests': async (req, res, body, u) => {
    if (!u.buddyId) return send(res, 400, { error: 'no buddy set' });
    const id = rid(8);
    db.requests[id] = {
      id, from: u.id, to: u.buddyId, kind: String(body.kind || 'pause').slice(0, 20),
      note: String(body.note || '').slice(0, 120), status: 'pending', at: Date.now(),
    };
    // Keep the store small: drop requests older than a day.
    for (const [k, r] of Object.entries(db.requests)) if (Date.now() - r.at > 86400000) delete db.requests[k];
    save();
    send(res, 200, { id });
  },

  'GET /requests/mine': async (req, res, body, u) => send(res, 200, {
    requests: Object.values(db.requests).filter((r) => r.from === u.id).sort((a, b) => b.at - a.at).slice(0, 10),
  }),

  'GET /requests/incoming': async (req, res, body, u) => send(res, 200, {
    requests: Object.values(db.requests).filter((r) => r.to === u.id && r.status === 'pending')
      .map((r) => ({ ...r, fromName: (db.users[r.from] || {}).name || '?' })),
  }),
};

function hasPending(userId) {
  return Object.values(db.requests).some((r) => r.from === userId && r.status === 'pending');
}

const server = http.createServer(async (req, res) => {
  try {
    if (limited(req.socket.remoteAddress)) return send(res, 429, { error: 'slow down' });
    const url = new URL(req.url, 'http://x');
    const key = `${req.method} ${url.pathname}`;
    const body = req.method === 'POST' ? await readBody(req) : {};

    // POST /requests/:id/decision
    const m = url.pathname.match(/^\/requests\/([0-9a-f]+)\/decision$/);
    if (req.method === 'POST' && m) {
      const u = auth(req);
      if (!u) return send(res, 401, { error: 'unauthorized' });
      const r = db.requests[m[1]];
      if (!r || r.to !== u.id) return send(res, 404, { error: 'not found' });
      if (r.status !== 'pending') return send(res, 409, { error: 'already decided' });
      r.status = body.approve === true ? 'approved' : 'denied';
      r.decidedAt = Date.now();
      save();
      return send(res, 200, { status: r.status });
    }

    const handler = routes[key];
    if (!handler) return send(res, 404, { error: 'not found' });
    let u = null;
    if (key !== 'POST /register') {
      u = auth(req);
      if (!u) return send(res, 401, { error: 'unauthorized' });
    }
    await handler(req, res, body, u, url.searchParams);
  } catch (e) {
    send(res, 400, { error: String(e.message || e) });
  }
});

server.listen(PORT, HOST, () => console.log(`focus-reels server on http://${HOST}:${PORT}`));
