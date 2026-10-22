const express = require('express');
const http = require('http');
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const bcrypt = require('bcryptjs');
const jwt = require('jsonwebtoken');
const { WebSocketServer } = require('ws');

const PORT = process.env.PORT || 3000;
const DATA_FILE = process.env.DATA_FILE || path.join(__dirname, 'data.json');
const SECRET_FILE = path.join(__dirname, '.secret');

// ---- JWT secret (از env یا فایل ذخیره‌شده) ----
let SECRET = process.env.JWT_SECRET;
if (!SECRET) {
  if (fs.existsSync(SECRET_FILE)) {
    SECRET = fs.readFileSync(SECRET_FILE, 'utf8').trim();
  } else {
    SECRET = crypto.randomBytes(48).toString('hex');
    fs.writeFileSync(SECRET_FILE, SECRET, { mode: 0o600 });
  }
}

// ---- ذخیره‌سازی ساده در فایل JSON ----
let db = { users: [], messages: [], nextUserId: 1, nextMsgId: 1 };
if (fs.existsSync(DATA_FILE)) {
  try {
    db = Object.assign(db, JSON.parse(fs.readFileSync(DATA_FILE, 'utf8')));
  } catch (e) {
    console.error('خواندن data.json ناموفق بود:', e.message);
    process.exit(1);
  }
}
let saveTimer = null;
function save() {
  if (saveTimer) return;
  saveTimer = setTimeout(() => {
    saveTimer = null;
    const tmp = DATA_FILE + '.tmp';
    fs.writeFileSync(tmp, JSON.stringify(db));
    fs.renameSync(tmp, DATA_FILE);
  }, 200);
}
process.on('SIGINT', () => {
  try { fs.writeFileSync(DATA_FILE, JSON.stringify(db)); } catch (_) {}
  process.exit(0);
});

// ---- ابزارها ----
const USERNAME_RE = /^[A-Za-z0-9_]{3,32}$/;
const publicUser = (u) => ({ id: u.id, username: u.username });
const publicMsg = (m) => ({ id: m.id, from: m.from, to: m.to, text: m.text, createdAt: m.createdAt });
const sign = (u) => jwt.sign({ uid: u.id }, SECRET, { expiresIn: '90d' });

// محدودیت ساده تعداد تلاش ورود/ثبت‌نام (۲۰ بار در ۱۰ دقیقه برای هر IP)
const attempts = new Map();
function limiter(req, res, next) {
  const ip = req.ip;
  const now = Date.now();
  const list = (attempts.get(ip) || []).filter((t) => now - t < 10 * 60 * 1000);
  if (list.length >= 20) return res.status(429).json({ error: 'تعداد تلاش‌ها زیاد است، چند دقیقه بعد دوباره امتحان کنید' });
  list.push(now);
  attempts.set(ip, list);
  next();
}

function auth(req, res, next) {
  const h = req.headers.authorization || '';
  const token = h.startsWith('Bearer ') ? h.slice(7) : '';
  try {
    const p = jwt.verify(token, SECRET);
    const u = db.users.find((x) => x.id === p.uid);
    if (!u) throw new Error('no user');
    req.user = u;
    next();
  } catch (_) {
    res.status(401).json({ error: 'unauthorized' });
  }
}

// ---- WebSocket ----
const sockets = new Map(); // userId -> Set<ws>
function push(uid, payload) {
  const set = sockets.get(uid);
  if (!set) return;
  const s = JSON.stringify(payload);
  for (const ws of set) if (ws.readyState === 1) ws.send(s);
}

// ---- REST ----
const app = express();
app.set('trust proxy', true);
app.use(express.json({ limit: '20kb' }));

app.get('/', (_req, res) => res.json({ ok: true, name: 'chat-server' }));

app.post('/register', limiter, async (req, res) => {
  const { username, password } = req.body || {};
  if (typeof username !== 'string' || !USERNAME_RE.test(username))
    return res.status(400).json({ error: 'نام کاربری باید ۳ تا ۳۲ حرف انگلیسی، عدد یا _ باشد' });
  if (typeof password !== 'string' || password.length < 6 || password.length > 100)
    return res.status(400).json({ error: 'رمز عبور حداقل ۶ کاراکتر باشد' });

  const hash = await bcrypt.hash(password, 10);
  const key = username.toLowerCase();
  if (db.users.some((u) => u.key === key))
    return res.status(409).json({ error: 'این نام کاربری قبلاً گرفته شده' });

  const user = { id: db.nextUserId++, username, key, hash, createdAt: Date.now() };
  db.users.push(user);
  save();
  res.json({ token: sign(user), user: publicUser(user) });
});

app.post('/login', limiter, async (req, res) => {
  const { username, password } = req.body || {};
  if (typeof username !== 'string' || typeof password !== 'string')
    return res.status(400).json({ error: 'نام کاربری و رمز عبور را وارد کنید' });
  const user = db.users.find((u) => u.key === username.trim().toLowerCase());
  const ok = user && (await bcrypt.compare(password, user.hash));
  if (!ok) return res.status(401).json({ error: 'نام کاربری یا رمز عبور اشتباه است' });
  res.json({ token: sign(user), user: publicUser(user) });
});

app.get('/users', auth, (req, res) => {
  const q = String(req.query.q || '').trim().toLowerCase();
  const list = db.users
    .filter((u) => u.id !== req.user.id && (!q || u.key.includes(q)))
    .slice(0, 30)
    .map(publicUser);
  res.json(list);
});

app.get('/chats', auth, (req, res) => {
  const me = req.user.id;
  const map = new Map();
  for (const m of db.messages) {
    if (m.from !== me && m.to !== me) continue;
    const peerId = m.from === me ? m.to : m.from;
    let c = map.get(peerId);
    if (!c) {
      const peer = db.users.find((u) => u.id === peerId);
      if (!peer) continue;
      c = { peer: publicUser(peer), last: null, unread: 0 };
      map.set(peerId, c);
    }
    c.last = publicMsg(m);
    if (m.to === me && !m.read) c.unread++;
  }
  const list = [...map.values()].sort((a, b) => b.last.createdAt - a.last.createdAt);
  res.json(list);
});

app.get('/messages/:peer', auth, (req, res) => {
  const me = req.user.id;
  const peer = parseInt(req.params.peer, 10);
  const list = db.messages
    .filter((m) => (m.from === me && m.to === peer) || (m.from === peer && m.to === me))
    .slice(-500)
    .map(publicMsg);
  let changed = false;
  for (const m of db.messages) {
    if (m.from === peer && m.to === me && !m.read) { m.read = true; changed = true; }
  }
  if (changed) save();
  res.json(list);
});

app.post('/messages/:peer', auth, (req, res) => {
  const me = req.user.id;
  const peer = parseInt(req.params.peer, 10);
  if (!db.users.some((u) => u.id === peer)) return res.status(404).json({ error: 'کاربر پیدا نشد' });
  const text = typeof req.body?.text === 'string' ? req.body.text.trim() : '';
  if (!text || text.length > 4000) return res.status(400).json({ error: 'متن پیام معتبر نیست' });

  const m = { id: db.nextMsgId++, from: me, to: peer, text, createdAt: Date.now(), read: false };
  db.messages.push(m);
  save();
  const out = publicMsg(m);
  push(peer, { type: 'message', message: out });
  if (peer !== me) push(me, { type: 'message', message: out }); // سایر دستگاه‌های خود فرستنده
  res.json(out);
});

app.post('/read/:peer', auth, (req, res) => {
  const me = req.user.id;
  const peer = parseInt(req.params.peer, 10);
  let changed = false;
  for (const m of db.messages) {
    if (m.from === peer && m.to === me && !m.read) { m.read = true; changed = true; }
  }
  if (changed) save();
  res.json({ ok: true });
});

// ---- راه‌اندازی ----
const server = http.createServer(app);
const wss = new WebSocketServer({ server, path: '/ws' });

wss.on('connection', (ws, req) => {
  let uid;
  try {
    const token = new URL(req.url, 'http://x').searchParams.get('token');
    uid = jwt.verify(token, SECRET).uid;
  } catch (_) {
    ws.close(4001, 'unauthorized');
    return;
  }
  ws.isAlive = true;
  ws.on('pong', () => { ws.isAlive = true; });
  if (!sockets.has(uid)) sockets.set(uid, new Set());
  sockets.get(uid).add(ws);
  ws.on('close', () => {
    const set = sockets.get(uid);
    if (set) { set.delete(ws); if (!set.size) sockets.delete(uid); }
  });
  ws.on('error', () => {});
});

setInterval(() => {
  for (const ws of wss.clients) {
    if (!ws.isAlive) { ws.terminate(); continue; }
    ws.isAlive = false;
    ws.ping();
  }
}, 30000);

server.listen(PORT, '0.0.0.0', () => console.log(`Chat server on port ${PORT}`));
