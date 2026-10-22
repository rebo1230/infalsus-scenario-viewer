// Notes, annotations and terms for the In Falsus scenario viewer.
// Optional add-on: remove the <script src="memo.js"> / memo.css tags to drop it entirely.
// Everything is stored in this browser (localStorage) and can be exported / imported as JSON.
(() => {
  const V = window.IFV;
  if (!V) return;
  const { D, eps, byChrono, esc } = V;
  const $ = id => document.getElementById(id);
  const app = $('app');
  const KEY = 'ifv.memo', UI_KEY = 'ifv.memoUi';
  const LANGS = V.LANG_ORDER, TAG = V.LANG_TAG;
  const COLORS = [['yellow', '#ffd866'], ['red', '#ff6b81'], ['blue', '#5cc8ff'], ['green', '#5fe0a8'], ['purple', '#c39bff']];
  const colorOf = c => (COLORS.find(x => x[0] === c) || COLORS[0])[1];
  const KIND = { ep: '회차', line: '대사', span: '단어' };
  const uid = () => Date.now().toString(36) + Math.random().toString(36).slice(2, 7);
  const fmtTime = t => (t ? new Date(t).toLocaleString('ko-KR', { month: 'numeric', day: 'numeric', hour: '2-digit', minute: '2-digit' }) : '');

  // every line by ID, and the text the reader shows for it (ruby base + reading, no tags or breaks)
  const lineMap = new Map();
  for (const e of eps) e.lines.forEach((l, i) => lineMap.set(l[0], { e, l, i }));
  const rawText = (l, lang) => l[V.TEXT_IDX[lang]] || '';
  const domText = raw => String(raw || '').replace(/<[^>]+>/g, '').replace(/\n/g, '');

  /* ================= storage + undo ================= */
  const blank = () => ({ v: 1, notes: [], anns: [], terms: [] });
  const uiDefault = () => ({ open: false, tab: 'notes', note: null, sort: 'updated', mode: 'edit', find: '' });
  let M = (() => { try { const v = JSON.parse(localStorage.getItem(KEY) || 'null'); if (v && v.v === 1) return Object.assign(blank(), v); } catch {} return blank(); })();
  let ui = (() => { try { return Object.assign(uiDefault(), JSON.parse(localStorage.getItem(UI_KEY) || '{}')); } catch { return uiDefault(); } })();
  let saveTimer = 0;
  const persist = () => { clearTimeout(saveTimer); try { localStorage.setItem(KEY, JSON.stringify(M)); } catch {} };
  const save = soon => { clearTimeout(saveTimer); if (soon) saveTimer = setTimeout(persist, 400); else persist(); };
  const saveUi = () => { try { localStorage.setItem(UI_KEY, JSON.stringify(ui)); } catch {} };
  window.addEventListener('beforeunload', persist);

  // term forms: a list per language (older data stored a single string)
  const formsOf = (t, k) => { const v = t.forms?.[k]; return Array.isArray(v) ? v.filter(Boolean) : v ? [v] : []; };
  const allForms = t => LANGS.flatMap(k => formsOf(t, k));
  // t.exact[lang]: forms matched exactly (same case, whole word); t.excl: text that never counts as the term
  const isExact = (t, k, f) => (t.exact?.[k] || []).includes(f);
  const normalizeTerms = () => { for (const t of M.terms) {
    t.forms = t.forms || {}; t.exact = t.exact || {}; t.excl = (t.excl || []).filter(Boolean);
    if (!LANGS.includes(t.base)) t.base = '';
    for (const k of LANGS) { t.forms[k] = formsOf(t, k); t.exact[k] = (t.exact[k] || []).filter(f => t.forms[k].includes(f)); }
  } };
  normalizeTerms();
  const formsHtml = t => LANGS.filter(k => formsOf(t, k).length).map(k => `<span><i${k === t.base ? ' class="t-base" title="기준 언어"' : ''}>${TAG[k]}</i>${formsOf(t, k).map(f => isExact(t, k, f) ? `<b class="t-exact" title="완전일치">${esc(f)}</b>` : esc(f)).join(' · ')}</span>`).join('') +
    ((t.excl || []).length ? `<span class="t-excl"><i>제외</i>${t.excl.map(esc).join(' · ')}</span>` : '');
  const ICON_EXACT = '<svg viewBox="0 0 16 16" width="14" height="14" aria-hidden="true"><path d="M2 5v6h12V5" fill="none" stroke="currentColor" stroke-width="1.6"/><path d="M5.5 7.2h5M5.5 9.2h5" stroke="currentColor" stroke-width="1.3"/></svg>';
  const ICON_PIN = '<svg viewBox="0 0 16 16" width="11" height="11" aria-hidden="true"><path d="M8 1.5a4.2 4.2 0 0 1 4.2 4.2C12.2 9 8 14.5 8 14.5S3.8 9 3.8 5.7A4.2 4.2 0 0 1 8 1.5z" fill="currentColor"/><circle cx="8" cy="5.7" r="1.5" fill="#0a131c"/></svg>';
  const ICON_EPANN = '<svg viewBox="0 0 16 16" width="14" height="14" aria-hidden="true"><path d="M2.5 2.5h11v8h-6l-3 3v-3h-2z" fill="none" stroke="currentColor" stroke-width="1.4" stroke-linejoin="round"/><path d="M5 5.5h6M5 7.8h4" stroke="currentColor" stroke-width="1.3"/></svg>';
  const ICON_QUOTE = '<svg viewBox="0 0 16 16" width="14" height="14" aria-hidden="true"><path d="M3 9.5c0-3 1.2-4.6 3.4-5.3l.4 1C5.6 5.8 5 6.7 5 8h1.8v4H3zm6 0c0-3 1.2-4.6 3.4-5.3l.4 1c-1.2.6-1.8 1.5-1.8 2.8h1.8v4H9z" fill="currentColor"/></svg>';
  // where the term occurs in a text of one language: [[start, length], ...]
  const LAT = c => /[A-Za-z0-9_À-ɏ]/.test(c || '');
  function termHits(t, k, text) {
    const low = text.toLowerCase(), hits = [], skip = [];
    for (const x of t.excl || []) { const f = x.toLowerCase(); for (let i = low.indexOf(f); i >= 0; i = low.indexOf(f, i + 1)) skip.push([i, i + f.length]); }
    for (const form of formsOf(t, k)) {
      const exact = isExact(t, k, form), hay = exact ? text : low, f = exact ? form : form.toLowerCase();
      for (let i = hay.indexOf(f); i >= 0; i = hay.indexOf(f, i + f.length)) {
        const e = i + f.length;
        // whole word only for letters at the edges (CJK text has no spaces, so nothing to check there)
        if (exact && ((LAT(f[0]) && LAT(text[i - 1])) || (LAT(f[f.length - 1]) && LAT(text[e])))) continue;
        if (skip.some(([s, z]) => i < z && s < e)) continue;
        if (!hits.some(([s, n]) => i < s + n && s < e)) hits.push([i, f.length]);
      }
    }
    return hits;
  }
  // base language: the term only counts in a line when the base language's form is found in that line too
  const hasBase = t => t.base && formsOf(t, t.base).length > 0;
  const baseOk = (t, k, l) => !l || !hasBase(t) || k === t.base || termHits(t, t.base, domText(rawText(l, t.base))).length > 0;

  const undoStack = [];
  function checkpoint(label) { undoStack.push({ label, data: JSON.stringify(M) }); if (undoStack.length > 30) undoStack.shift(); }
  function undo() {
    const s = undoStack.pop();
    if (!s) { toast('되돌릴 작업이 없습니다'); return; }
    M = JSON.parse(s.data); save(); refresh(); toast(`되돌림: ${s.label}`);
  }

  let toastEl = null;
  function toast(msg, withUndo) {
    toastEl?.remove();
    const el = toastEl = document.createElement('div');
    el.className = 'm-toast'; el.setAttribute('role', 'status');
    el.innerHTML = `<span>${esc(msg)}</span>${withUndo ? '<button type="button">되돌리기</button>' : ''}`;
    el.querySelector('button')?.addEventListener('click', () => { el.remove(); undo(); });
    app.appendChild(el);
    setTimeout(() => el.remove(), 6000);
  }

  /* ================= derived indexes ================= */
  let annLines = new Set(), mentions = new Map();
  function reindex() {
    annLines = new Set(M.anns.filter(a => a.line).map(a => a.line));
    mentions = new Map();
    for (const n of M.notes) for (const m of (n.body || '').matchAll(/\[\[(\d{3}-\d+)\]\]/g)) {
      if (!mentions.has(m[1])) mentions.set(m[1], new Set());
      mentions.get(m[1]).add(n.id);
    }
  }
  reindex();
  const termCache = new Map();
  function termLines(t) {
    const key = JSON.stringify([t.forms, t.exact, t.excl, t.base]);
    if (termCache.has(key)) return termCache.get(key);
    const langs = hasBase(t) ? [t.base] : LANGS.filter(k => formsOf(t, k).length);
    const out = [];
    if (langs.length) for (const [, { e, l }] of lineMap) {
      if (langs.some(k => termHits(t, k, domText(rawText(l, k))).length)) out.push({ e, l });
    }
    termCache.set(key, out);
    return out;
  }

  /* ================= text anchors (word annotations, links, term marks) ================= */
  function startOf(block, range) {
    const pre = document.createRange();
    pre.selectNodeContents(block); pre.setEnd(range.startContainer, range.startOffset);
    return pre.toString().length;
  }
  const anchorAt = (text, s, e) => ({ quote: text.slice(s, e), pre: text.slice(Math.max(0, s - 12), s), post: text.slice(e, e + 12) });
  function anchorOf(block, range) {
    const s = startOf(block, range);
    return anchorAt(block.textContent, s, s + range.toString().length);
  }
  // where existing word annotations sit in this block: { a, link (null = main anchor), s, e }
  function spanRangesIn(block, lineId, lang, exceptId) {
    const text = block.textContent, out = [];
    for (const a of M.anns) {
      if (a.kind !== 'span' || a.line !== lineId || a.id === exceptId) continue;
      const anchors = a.lang === lang ? [[a, null]] : (a.links || []).filter(k => k.lang === lang).map(k => [k, k]);
      for (const [an, link] of anchors) {
        const s = locate(text, an);
        if (s >= 0) out.push({ a, link, s, e: s + an.quote.length });
      }
    }
    return out;
  }
  const overlapping = (ranges, s, e) => ranges.filter(r => r.s < e && s < r.e);
  // find the anchored text again, even if the surrounding text changed a little
  function locate(text, a) {
    if (!a.quote) return -1;
    const full = text.indexOf(a.pre + a.quote + a.post);
    if (full >= 0) return full + a.pre.length;
    const before = a.pre ? text.indexOf(a.pre + a.quote) : -1;
    if (before >= 0) return before + a.pre.length;
    const after = a.post ? text.indexOf(a.quote + a.post) : -1;
    if (after >= 0) return after;
    return text.indexOf(a.quote);
  }
  function wrapRange(block, start, len, make) {
    if (start < 0 || !len) return false;
    const walker = document.createTreeWalker(block, NodeFilter.SHOW_TEXT);
    const parts = []; let pos = 0;
    while (walker.nextNode()) {
      const n = walker.currentNode, L = n.nodeValue.length;
      if (pos + L > start && pos < start + len) parts.push([n, Math.max(0, start - pos), Math.min(L, start + len - pos)]);
      pos += L;
      if (pos >= start + len) break;
    }
    for (const [n, s, t] of parts) {
      let node = n;
      if (t < node.nodeValue.length) node.splitText(t);
      if (s > 0) node = node.splitText(s);
      const w = make();
      node.parentNode.insertBefore(w, node);
      w.appendChild(node);
    }
    return parts.length > 0;
  }
  function markTerms(block, lang, l) {
    for (const t of M.terms) {
      if (!baseOk(t, lang, l)) continue;
      for (const [i, n] of termHits(t, lang, block.textContent)) {
        wrapRange(block, i, n, () => {
          const s = document.createElement('span');
          s.className = 'term-mark'; s.dataset.term = t.id; s.style.setProperty('--ac', colorOf(t.color));
          s.title = `용어: ${t.name}${t.note ? ' — ' + t.note : ''}`;
          return s;
        });
      }
    }
  }
  function markSpans(block, lang, lineId) {
    for (const a of M.anns) {
      if (a.kind !== 'span' || a.line !== lineId) continue;
      const anchors = a.lang === lang ? [a] : (a.links || []).filter(k => k.lang === lang);
      for (const an of anchors) {
        wrapRange(block, locate(block.textContent, an), an.quote.length, () => {
          const s = document.createElement('span');
          s.className = 'ann-mark'; s.dataset.ann = a.id; s.style.setProperty('--ac', colorOf(a.color));
          s.title = a.text || '(내용 없음)';
          return s;
        });
      }
    }
  }
  const spanLost = a => {
    const r = lineMap.get(a.line);
    return !r || locate(domText(rawText(r.l, a.lang)), a) < 0;
  };

  /* ================= side panel ================= */
  const panel = document.createElement('aside');
  panel.className = 'memo'; panel.id = 'memo'; panel.setAttribute('aria-label', '노트'); panel.hidden = true;
  panel.innerHTML = `
    <div class="m-head">
      <div class="m-tabs" role="tablist"><button role="tab" data-mt="notes">노트</button><button role="tab" data-mt="ep">주석</button><button role="tab" data-mt="terms">용어집</button></div>
      <div class="m-acts">
        <button class="m-btn" id="mExport" title="노트·주석·용어를 JSON 파일로 저장">내보내기</button>
        <button class="m-btn" id="mImport" title="JSON 파일을 불러와 지금 내용과 합치기">불러오기</button>
        <input type="file" id="mFile" accept=".json,application/json" hidden>
        <button class="m-x" id="mClose" aria-label="노트 닫기">×</button>
      </div>
    </div>
    <div class="m-body" id="mBody"></div>`;
  app.appendChild(panel);

  function setOpen(open) {
    ui.open = open; saveUi();
    panel.hidden = !open;
    app.classList.toggle('memo-open', open);
    $('memoBtn')?.setAttribute('aria-pressed', String(open));
    if (open) renderPanel();
  }
  function setTab(t) { ui.tab = t; saveUi(); renderPanel(); }

  function renderPanel() {
    if (panel.hidden) return;
    panel.querySelectorAll('[data-mt]').forEach(b => b.setAttribute('aria-selected', String(b.dataset.mt === ui.tab)));
    const body = $('mBody');
    body.innerHTML = ui.tab === 'ep' ? epTabHtml() : ui.tab === 'terms' ? termsTabHtml() : notesTabHtml();
    if (ui.tab === 'notes') wireNotes();
    if (ui.tab === 'ep') wireEpFilter();
  }

  /* ---------- notes (A) ---------- */
  const curNote = () => M.notes.find(n => n.id === ui.note) || null;
  function sortedNotes() {
    const f = (ui.find || '').toLowerCase();
    return M.notes.filter(n => !f || (n.title || '').toLowerCase().includes(f) || (n.body || '').toLowerCase().includes(f))
      .sort(ui.sort === 'title' ? (a, b) => (a.title || '').localeCompare(b.title || '') : (a, b) => b.updated - a.updated);
  }
  function notesTabHtml() {
    const cur = curNote();
    const list = sortedNotes().map(n => `<li><button data-note="${n.id}" aria-current="${n.id === ui.note}"><span>${esc(n.title || '제목 없음')}</span><time>${fmtTime(n.updated)}</time></button></li>`).join('');
    return `
      <div class="n-bar"><input id="nFind" type="search" placeholder="노트 찾기" value="${esc(ui.find || '')}" aria-label="노트 찾기">
        <select id="nSort" aria-label="노트 정렬"><option value="updated" ${ui.sort === 'updated' ? 'selected' : ''}>최근 수정순</option><option value="title" ${ui.sort === 'title' ? 'selected' : ''}>이름순</option></select>
        <button class="m-btn" id="nNew">＋ 새 노트</button></div>
      <ul class="n-list" id="nList">${list || '<li class="m-empty">노트가 없습니다</li>'}</ul>
      ${cur ? `<div class="n-edit">
        <input id="nTitle" value="${esc(cur.title || '')}" placeholder="제목" aria-label="노트 제목">
        <div class="n-tools">
          <span class="seg2"><button data-nm="edit" aria-pressed="${ui.mode === 'edit'}">편집</button><button data-nm="view" aria-pressed="${ui.mode === 'view'}">보기</button></span>
          <span class="n-time" id="nTime">수정 ${fmtTime(cur.updated)}</span>
          <button class="m-btn" id="nMd" title="이 노트를 .md 파일로 저장">.md</button>
          <button class="m-btn danger" id="nDel">삭제</button>
        </div>
        ${ui.mode === 'edit'
          ? `<textarea id="nText" spellcheck="false" placeholder="# 제목&#10;- 목록&#10;**굵게**&#10;[[075-043]] 대사 링크 · [[#156]] 회차 링크">${esc(cur.body || '')}</textarea>`
          : `<div class="n-view">${mdHtml(cur.body || '') || '<p class="m-empty">비어 있음</p>'}</div>`}
        <div class="n-hint">[[대사 ID]], [[#회차 번호]]로 링크 · 대사 옆 ❝ 또는 글자를 선택해 '노트에 인용'</div>
      </div>` : '<div class="m-empty">노트를 고르거나 새로 만드세요.</div>'}`;
  }
  function inlineMd(s) {
    return esc(s).replace(/\*\*(.+?)\*\*/g, '<b>$1</b>')
      .replace(/\[\[(#?)([\w-]+)\]\]/g, (m, h, id) => h ? `<button class="m-link" data-c="${id}">#${id}</button>` : `<button class="m-link" data-l="${id}">${id}</button>`);
  }
  function mdHtml(src) {
    const out = []; let list = false;
    for (const raw of src.split('\n')) {
      const line = raw.trimEnd();
      const li = /^\s*[-*]\s+(.*)$/.exec(line);
      if (li) { if (!list) { out.push('<ul>'); list = true; } out.push(`<li>${inlineMd(li[1])}</li>`); continue; }
      if (list) { out.push('</ul>'); list = false; }
      const h = /^(#{1,3})\s+(.*)$/.exec(line);
      if (h) { out.push(`<h${h[1].length + 3}>${inlineMd(h[2])}</h${h[1].length + 3}>`); continue; }
      const q = /^>\s?(.*)$/.exec(line);
      if (q) { out.push(`<blockquote>${inlineMd(q[1])}</blockquote>`); continue; }
      out.push(line ? `<p>${inlineMd(line)}</p>` : '<p class="sp"></p>');
    }
    if (list) out.push('</ul>');
    return out.join('');
  }
  function newNote(title) {
    const n = { id: uid(), title: title || `노트 ${M.notes.length + 1}`, body: '', updated: Date.now() };
    M.notes.push(n); ui.note = n.id; ui.mode = 'edit'; save(); saveUi();
    return n;
  }
  let cursor = { note: null, pos: null };
  function wireNotes() {
    $('nFind').oninput = () => { ui.find = $('nFind').value; saveUi(); const v = ui.find; renderPanel(); const f = $('nFind'); f.focus(); f.setSelectionRange(v.length, v.length); };
    $('nSort').onchange = () => { ui.sort = $('nSort').value; saveUi(); renderPanel(); };
    $('nNew').onclick = () => { newNote(); renderPanel(); $('nTitle')?.select(); };
    // clicking the open note again folds it away
    $('nList').onclick = ev => { const b = ev.target.closest('[data-note]'); if (b) { ui.note = ui.note === b.dataset.note ? null : b.dataset.note; saveUi(); renderPanel(); } };
    const cur = curNote(); if (!cur) return;
    const touch = () => { cur.updated = Date.now(); save(true); const t = $('nTime'); if (t) t.textContent = `수정 ${fmtTime(cur.updated)}`; };
    $('nTitle').oninput = () => {
      cur.title = $('nTitle').value; touch();
      const span = panel.querySelector(`[data-note="${cur.id}"] span`); if (span) span.textContent = cur.title || '제목 없음';
    };
    panel.querySelectorAll('[data-nm]').forEach(b => b.onclick = () => { ui.mode = b.dataset.nm; saveUi(); renderPanel(); });
    $('nMd').onclick = () => download(`${(cur.title || 'note').replace(/[\\/:*?"<>|]/g, '_')}.md`, `# ${cur.title || ''}\n\n${cur.body || ''}\n`, 'text/markdown');
    $('nDel').onclick = () => {
      checkpoint('노트 삭제');
      M.notes = M.notes.filter(n => n !== cur); ui.note = M.notes[0]?.id || null; save(); saveUi(); refresh();
      toast('노트를 지웠습니다', true);
    };
    const ta = $('nText');
    if (ta) {
      const remember = () => { cursor = { note: cur.id, pos: ta.selectionStart }; };
      ta.oninput = () => { cur.body = ta.value; touch(); remember(); };
      ta.onkeyup = ta.onclick = ta.onselect = remember;
      ta.onchange = () => { reindex(); keepScroll(V.renderReader); };   // note mentions (on blur)
      if (cursor.note === cur.id && cursor.pos != null) { ta.focus(); ta.setSelectionRange(cursor.pos, cursor.pos); }
    }
  }
  // insert text into the active note (at the last cursor position) and show it
  function insertIntoNote(text) {
    let n = curNote() || M.notes[0] || newNote();
    ui.note = n.id; ui.tab = 'notes'; ui.mode = 'edit'; saveUi();
    const body = n.body || '';
    const pos = cursor.note === n.id && cursor.pos != null ? cursor.pos : body.length;
    const before = body.slice(0, pos), after = body.slice(pos);
    const glue = before && !before.endsWith('\n') ? '\n' : '';
    n.body = before + glue + text + (after.startsWith('\n') ? '' : '\n') + after;
    n.updated = Date.now();
    cursor = { note: n.id, pos: (before + glue + text).length + 1 };
    save(); reindex();
    if (panel.hidden) setOpen(true); else renderPanel();
    keepScroll(V.renderReader);
    toast(`'${n.title}'에 넣었습니다`);
  }

  /* ---------- this episode (B9) ---------- */
  function annsOf(e) {
    const order = a => a.kind === 'ep' ? -1 : (lineMap.get(a.line)?.i ?? 1e9);
    return M.anns.filter(a => a.c === e.c).sort((a, b) => order(a) - order(b) || (a.kind === 'line' ? -1 : 1));
  }
  function annItemHtml(a, withEp) {
    const r = a.line ? lineMap.get(a.line) : null, e = byChrono.get(a.c);
    const lost = a.kind === 'span' && spanLost(a);
    return `<div class="m-item" style="--ac:${colorOf(a.color)}">
      <button class="m-go" data-ann-go="${a.id}">
        <span class="m-kind">${KIND[a.kind]}</span>${withEp && e ? ` ${esc(V.epLabel(e))}` : ''}${a.line ? ` <span class="mono">${a.line}</span>` : ''}
        ${a.kind === 'span' ? ` <q>${esc(a.quote)}</q><i class="m-lang">${TAG[a.lang]}</i>${(a.links || []).map(k => `<i class="m-lang">${TAG[k.lang]}</i>`).join('')}` : ''}
        ${a.kind === 'line' && r ? ` <span class="m-quote">${esc(V.plain(rawText(r.l, V.primary()) || r.l[3]).slice(0, 40))}</span>` : ''}
        ${lost ? ' <span class="m-lost" title="번역이 바뀌어 원래 글자를 찾지 못했습니다">위치 잃음</span>' : ''}
      </button>
      ${a.text ? `<div class="m-text">${esc(a.text)}</div>` : ''}
      ${a.tags?.length ? `<div class="m-tags">${a.tags.map(t => `<span>#${esc(t)}</span>`).join('')}</div>` : ''}
      <div class="m-item-acts"><time>${fmtTime(a.updated)}</time><button data-ann-edit="${a.id}">편집</button></div>
    </div>`;
  }
  // annotation filters, shared by the panel's 주석 tab and the data view's 주석 tab
  const COLOR_KO = { yellow: '노랑', red: '빨강', blue: '파랑', green: '초록', purple: '보라' };
  const allTags = () => [...new Set(M.anns.flatMap(a => a.tags || []))].sort();
  const byPlace = (a, b) => a.c - b.c || (lineMap.get(a.line)?.i ?? -1) - (lineMap.get(b.line)?.i ?? -1);
  function filterAnns(list, f) {
    const q = (f.find || '').trim().toLowerCase();
    return list.filter(a => (!f.kind || a.kind === f.kind) && (!f.color || (a.color || 'yellow') === f.color) && (!f.tag || (a.tags || []).includes(f.tag))
      && (!q || `${a.text || ''} ${a.quote || ''}`.toLowerCase().includes(q)));
  }
  const kindOpts = first => `<option value="">${first}</option>${Object.entries(KIND).map(([k, v]) => `<option value="${k}">${v}</option>`).join('')}`;
  const colorOpts = first => `<option value="">${first}</option>${COLORS.map(([k]) => `<option value="${k}">${COLOR_KO[k] || k}</option>`).join('')}`;
  const tagOpts = (first, keep) => `<option value="">${first}</option>${allTags().map(t => `<option value="${esc(t)}"${t === keep ? ' selected' : ''}>#${esc(t)}</option>`).join('')}`;

  function epTabHtml() {
    const f = ui.af || (ui.af = {});
    if (f.tag && !allTags().includes(f.tag)) f.tag = '';   // that tag was removed meanwhile
    return `<div class="n-bar a-filter">
        <select id="pfKind" aria-label="종류">${kindOpts('종류 전체')}</select>
        <select id="pfColor" aria-label="색">${colorOpts('색 전체')}</select>
        <select id="pfTag" aria-label="태그">${tagOpts('태그 전체', f.tag)}</select>
        <input id="pfFind" type="search" placeholder="내용·인용 찾기" value="${esc(f.find || '')}" aria-label="주석 찾기">
      </div><div id="pfList">${epListHtml()}</div>`;
  }
  function epListHtml() {
    const f = ui.af || {}, filtered = !!(f.kind || f.color || f.tag || (f.find || '').trim());
    const e = V.state.open ? byChrono.get(V.state.open) : null;
    // no episode open: every annotation, in episode order
    if (!e) {
      const list = filterAnns([...M.anns].sort(byPlace), f);
      return `<div class="m-sub">전체 주석 ${filtered ? `${list.length} / ${M.anns.length}` : list.length}개</div>
        ${list.length ? list.map(a => annItemHtml(a, true)).join('') : `<div class="m-empty">${filtered ? '조건에 맞는 주석이 없습니다.' : '주석이 없습니다. 회차를 열고 대사에 마우스를 올려 ＋를 누르거나, 글자를 선택해 주석을 답니다.'}</div>`}`;
    }
    const mine = annsOf(e), list = filterAnns(mine, f);
    const noteIds = new Set(); for (const l of e.lines) for (const id of mentions.get(l[0]) || []) noteIds.add(id);
    const notes = [...noteIds].map(id => M.notes.find(n => n.id === id)).filter(Boolean);
    return `<div class="m-sub">${esc(V.epLabel(e))} · 주석 ${filtered ? `${list.length} / ${mine.length}` : list.length}개</div>
      ${list.length ? list.map(a => annItemHtml(a)).join('') : `<div class="m-empty">${filtered ? '조건에 맞는 주석이 없습니다.' : '주석이 없습니다. 대사에 마우스를 올려 ＋를 누르거나, 글자를 선택해 주석을 답니다.'}</div>`}
      ${notes.length ? `<div class="m-sub">이 회차를 언급한 노트</div>${notes.map(n => `<button class="m-notelink" data-open-note="${n.id}">📄 ${esc(n.title || '제목 없음')}</button>`).join('')}` : ''}`;
  }
  function wireEpFilter() {
    const f = ui.af || (ui.af = {});
    $('pfKind').value = f.kind || ''; $('pfColor').value = f.color || '';
    const upd = () => {
      Object.assign(f, { kind: $('pfKind').value, color: $('pfColor').value, tag: $('pfTag').value, find: $('pfFind').value });
      saveUi(); $('pfList').innerHTML = epListHtml();
    };
    ['pfKind', 'pfColor', 'pfTag'].forEach(id => $(id).onchange = upd);
    $('pfFind').oninput = upd;
  }

  /* ---------- terms (C) ---------- */
  function termsTabHtml() {
    return `<div class="n-bar"><button class="m-btn" id="tNew">＋ 새 용어</button><span class="m-sub">${M.terms.length}개</span></div>` +
      (M.terms.length ? M.terms.map(t => `<div class="m-item term" style="--ac:${colorOf(t.color)}">
        <div class="t-name">${esc(t.name)}</div>
        <div class="t-forms">${formsHtml(t)}</div>
        ${t.note ? `<div class="m-text">${esc(t.note)}</div>` : ''}
        <div class="m-item-acts"><span>${termLines(t).length}줄</span><button data-term-view="${t.id}">모아 보기</button><button data-term-edit="${t.id}">편집</button></div>
      </div>`).join('') : '<div class="m-empty">대본에서 글자를 선택해 \'용어로 등록\'을 누르거나 ＋ 새 용어로 만듭니다.</div>');
  }

  /* ================= popovers: annotation / term editors, selection bar ================= */
  let pop = null, selBar = null, modal = null;
  const unplace = el => { el?._ro?.disconnect(); el?.remove(); };
  const closePop = () => { unplace(pop); pop = null; };
  const closeSelBar = () => { unplace(selBar); selBar = null; };
  const closeModal = () => { modal?.remove(); modal = null; };
  // below the anchor if it fits, else above, else pinned inside the window; re-run whenever the box grows
  function position(el) {
    const rect = el._rect, w = el.offsetWidth, h = el.offsetHeight;
    const left = Math.min(Math.max(8, rect.left), innerWidth - w - 8);
    let top = rect.bottom + 6;
    if (top + h > innerHeight - 8) top = rect.top - h - 6 >= 8 ? rect.top - h - 6 : Math.max(8, innerHeight - h - 8);
    el.style.left = left + 'px'; el.style.top = top + 'px';
  }
  function place(el, rect) {
    el.style.visibility = 'hidden'; app.appendChild(el);
    el._rect = rect; position(el); el.style.visibility = '';
    el._ro = new ResizeObserver(() => position(el)); el._ro.observe(el);
  }
  const colorsHtml = cur => `<span class="p-colors">${COLORS.map(([k, v]) => `<button type="button" class="p-color" data-color="${k}" style="--c:${v}" aria-pressed="${(cur || 'yellow') === k}" aria-label="색 ${k}"></button>`).join('')}</span>`;
  const pickedColor = root => root.querySelector('.p-color[aria-pressed="true"]')?.dataset.color || 'yellow';
  function wireColors(root) {
    root.querySelectorAll('.p-color').forEach(b => b.onclick = () => root.querySelectorAll('.p-color').forEach(x => x.setAttribute('aria-pressed', String(x === b))));
  }
  // other-language texts of a line, for picking linked words / term forms (C2, C3)
  function pickHtml(lineId, exceptLang) {
    const r = lineMap.get(lineId); if (!r) return '';
    return LANGS.filter(k => k !== exceptLang && rawText(r.l, k)).map(k =>
      `<div class="p-pickrow"><i>${TAG[k]}</i><span class="p-picktext" data-lang="${k}">${V.rich(rawText(r.l, k))}</span></div>`).join('') +
      '<div class="n-hint">연결할 부분을 드래그하세요</div>';
  }
  // button that opens / closes a pick area, showing which state it is in
  function wireToggle(btn, pick, lineId, exceptLang) {
    btn.classList.add('p-toggle'); btn.setAttribute('aria-expanded', 'false');
    btn.onclick = () => {
      pick.hidden = !pick.hidden;
      btn.setAttribute('aria-expanded', String(!pick.hidden));
      if (!pick.hidden && !pick.innerHTML) pick.innerHTML = pickHtml(lineId, exceptLang);
    };
  }
  function onPick(root, cb) {
    root.addEventListener('mouseup', () => {
      const sel = getSelection(); if (!sel.rangeCount || sel.isCollapsed) return;
      const range = sel.getRangeAt(0);
      const block = range.startContainer.parentElement?.closest('.p-picktext');
      if (!block || !block.contains(range.endContainer) || !range.toString().trim()) return;
      const s = startOf(block, range);
      cb(block.dataset.lang, anchorOf(block, range), block, s, s + range.toString().length);
      sel.removeAllRanges();
    });
  }

  function openAnnEditor(a, rect) {
    closePop(); closeSelBar();
    const isNew = !M.anns.includes(a);
    const draft = { links: [...(a.links || [])] };
    const el = pop = document.createElement('div');
    el.className = 'm-pop'; el.setAttribute('role', 'dialog'); el.setAttribute('aria-label', `${KIND[a.kind]} 주석`);
    const linksHtml = () => draft.links.map(k => `<span class="p-link"><i>${TAG[k.lang]}</i>${esc(k.quote)}<button type="button" data-unlink="${k.lang}" aria-label="연결 끊기">×</button></span>`).join('');
    el.innerHTML = `
      <div class="p-head"><b>${KIND[a.kind]} 주석</b>${a.line ? ` <span class="mono">${a.line}</span>` : ''}${a.kind === 'span' ? ` <q>${esc(a.quote)}</q><i class="m-lang">${TAG[a.lang]}</i>` : ''}
        <button type="button" class="m-x p-x" aria-label="닫기">×</button></div>
      <textarea class="p-text" placeholder="메모" aria-label="주석 내용">${esc(a.text || '')}</textarea>
      <div class="p-row">${colorsHtml(a.color)}<input class="p-tags" placeholder="#태그 #태그" value="${esc((a.tags || []).map(t => '#' + t).join(' '))}" aria-label="태그"></div>
      ${a.kind === 'span' ? `<div class="p-links"><span class="p-linklist">${linksHtml()}</span><button type="button" class="m-btn p-addlink">다른 언어 연결</button></div><div class="p-pick" hidden></div>` : ''}
      <div class="p-acts"><button type="button" class="m-btn primary p-save">저장</button>${isNew ? '' : '<button type="button" class="m-btn danger p-del">삭제</button>'}</div>`;
    place(el, rect);
    wireColors(el);
    el.querySelector('.p-text').focus();
    el.querySelector('.p-x').onclick = closePop;
    const read = () => {
      a.text = el.querySelector('.p-text').value.trim();
      a.color = pickedColor(el);
      a.tags = el.querySelector('.p-tags').value.split(/[\s,]+/).map(s => s.replace(/^#/, '')).filter(Boolean);
      if (a.kind === 'span') a.links = draft.links;
      a.updated = Date.now();
    };
    el.querySelector('.p-save').onclick = () => {
      read(); if (isNew) M.anns.push(a);
      save(); closePop(); refresh();
    };
    el.querySelector('.p-del')?.addEventListener('click', () => {
      checkpoint('주석 삭제'); M.anns = M.anns.filter(x => x !== a); save(); closePop(); refresh();
      toast('주석을 지웠습니다', true);
    });
    if (a.kind === 'span') {
      const pick = el.querySelector('.p-pick');
      wireToggle(el.querySelector('.p-addlink'), pick, a.line, a.lang);
      onPick(pick, (lang, an, block, s, e) => {
        draft.links = draft.links.filter(k => k.lang !== lang).concat({ lang, ...an });
        el.querySelector('.p-linklist').innerHTML = linksHtml();
        // linking is allowed, but say so when those letters already carry another annotation
        const hit = overlapping(spanRangesIn(block, a.line, lang, a.id), s, e);
        if (hit.length) toast(`${TAG[lang]} 「${hit.map(r => (r.link || r.a).quote).join('」, 「')}」 주석과 겹칩니다 — 겹친 부분은 이중 밑줄로 표시됩니다`);
      });
      el.querySelector('.p-linklist').addEventListener('click', ev => {
        const b = ev.target.closest('[data-unlink]'); if (!b) return;
        draft.links = draft.links.filter(k => k.lang !== b.dataset.unlink);
        el.querySelector('.p-linklist').innerHTML = linksHtml();
      });
    }
  }

  function openTermEditor(t, rect, lineId) {
    closePop(); closeSelBar();
    const isNew = !M.terms.includes(t);
    // opened away from the script (term list): pick from the first line the term appears in
    const sameLine = !!lineId;
    if (!lineId && allForms(t).length) lineId = termLines(t)[0]?.l[0];
    const el = pop = document.createElement('div');
    el.className = 'm-pop term-pop'; el.setAttribute('role', 'dialog'); el.setAttribute('aria-label', '용어');
    // one row per language; ＋ adds another form (e.g. 방주 and 아크 for the same language)
    const formInput = (k, v) => `<span class="p-formitem"><input data-form="${k}" value="${esc(v)}" placeholder="${TAG[k]} 표기" aria-label="${V.LANG_NAME[k]} 표기"><button type="button" class="p-exact" aria-pressed="${isExact(t, k, v)}" title="완전일치: 대소문자와 단어 경계까지 같을 때만" aria-label="완전일치">${ICON_EXACT}</button><button type="button" class="p-delform" aria-label="이 표기 빼기">×</button></span>`;
    const exclInput = v => `<span class="p-formitem"><input data-excl value="${esc(v)}" placeholder="" aria-label="제외 표기"><button type="button" class="p-delform" aria-label="이 제외 표기 빼기">×</button></span>`;
    el.innerHTML = `
      <div class="p-head"><b>${isNew ? '용어 등록' : '용어 편집'}</b><button type="button" class="m-x p-x" aria-label="닫기">×</button></div>
      <input class="p-name" placeholder="용어 이름" value="${esc(t.name || '')}" aria-label="용어 이름">
      <div class="p-forms">${LANGS.map(k => `<div class="p-formrow"><button type="button" class="p-base" data-base="${k}" aria-pressed="${t.base === k}" title="기준 언어: 이 언어 표기가 있는 줄에서만 다른 언어도 용어로 봅니다" aria-label="${V.LANG_NAME[k]} 기준 언어">${ICON_PIN}${TAG[k]}</button>
        <span class="p-formlist" data-list="${k}">${(formsOf(t, k).length ? formsOf(t, k) : ['']).map(v => formInput(k, v)).join('')}</span>
        <button type="button" class="p-addform" data-add="${k}" aria-label="${V.LANG_NAME[k]} 표기 추가">＋</button></div>`).join('')}
        <div class="p-formrow p-exclrow" title="이 글자가 들어간 부분은 용어로 보지 않습니다 (모든 언어)"><i>제외</i>
          <span class="p-formlist" data-list="excl">${((t.excl || []).length ? t.excl : ['']).map(exclInput).join('')}</span>
          <button type="button" class="p-addform" data-add="excl" aria-label="제외 표기 추가">＋</button></div></div>
      ${lineId ? `<button type="button" class="m-btn p-pickform">${sameLine ? '같은 줄에서 고르기' : `예문에서 고르기 <span class="mono">${lineId}</span>`}</button><div class="p-pick" hidden></div>` : ''}
      <textarea class="p-note" placeholder="설명" aria-label="용어 설명">${esc(t.note || '')}</textarea>
      <div class="p-row">${colorsHtml(t.color)}</div>
      <div class="p-acts"><button type="button" class="m-btn primary p-save">저장</button>${isNew ? '' : '<button type="button" class="m-btn danger p-del">삭제</button><button type="button" class="m-btn p-view">모아 보기</button>'}</div>`;
    place(el, rect);
    wireColors(el);
    el.querySelector('.p-name').focus();
    el.querySelector('.p-x').onclick = closePop;
    const addForm = (k, v = '') => {
      const list = el.querySelector(`[data-list="${k}"]`);
      const empty = [...list.querySelectorAll('input')].find(i => !i.value.trim());   // reuse an empty box first
      if (empty) { empty.value = v; return empty; }
      list.insertAdjacentHTML('beforeend', formInput(k, v));
      return list.lastElementChild.querySelector('input');
    };
    el.querySelectorAll('[data-add]').forEach(b => b.onclick = () => {
      const list = el.querySelector(`[data-list="${b.dataset.add}"]`);
      list.insertAdjacentHTML('beforeend', b.dataset.add === 'excl' ? exclInput('') : formInput(b.dataset.add, ''));
      list.lastElementChild.querySelector('input').focus();
    });
    // × removes one form; the last box of a language is only cleared so the row stays
    el.querySelector('.p-forms').addEventListener('click', ev => {
      const bs = ev.target.closest('.p-base');   // one base language at most; click again to clear
      if (bs) { const on = bs.getAttribute('aria-pressed') !== 'true'; el.querySelectorAll('.p-base').forEach(b => b.setAttribute('aria-pressed', String(on && b === bs))); return; }
      const ex = ev.target.closest('.p-exact');
      if (ex) { ex.setAttribute('aria-pressed', String(ex.getAttribute('aria-pressed') !== 'true')); return; }
      const del = ev.target.closest('.p-delform'); if (!del) return;
      const item = del.closest('.p-formitem'), list = item.parentElement;
      if (list.children.length > 1) item.remove(); else item.querySelector('input').value = '';
    });
    if (lineId) {
      const pick = el.querySelector('.p-pick');
      wireToggle(el.querySelector('.p-pickform'), pick, lineId, null);
      onPick(pick, (lang, an) => {
        const v = an.quote.trim();
        if (![...el.querySelectorAll(`[data-form="${lang}"]`)].some(i => i.value.trim() === v)) addForm(lang, v);
      });
    }
    el.querySelector('.p-save').onclick = () => {
      t.exact = {};
      for (const k of LANGS) {
        const inputs = [...el.querySelectorAll(`[data-form="${k}"]`)].filter(i => i.value.trim());
        t.forms[k] = [...new Set(inputs.map(i => i.value.trim()))];
        t.exact[k] = [...new Set(inputs.filter(i => i.nextElementSibling?.getAttribute('aria-pressed') === 'true').map(i => i.value.trim()))];
      }
      t.excl = [...new Set([...el.querySelectorAll('[data-excl]')].map(i => i.value.trim()).filter(Boolean))];
      t.base = el.querySelector('.p-base[aria-pressed="true"]')?.dataset.base || '';
      t.name = el.querySelector('.p-name').value.trim() || allForms(t)[0] || '용어';
      t.note = el.querySelector('.p-note').value.trim(); t.color = pickedColor(el); t.updated = Date.now();
      if (!allForms(t).length) { toast('표기를 하나 이상 넣어 주세요'); return; }
      if (isNew) M.terms.push(t);
      termCache.clear(); save(); closePop(); refresh();
    };
    el.querySelector('.p-del')?.addEventListener('click', () => {
      checkpoint('용어 삭제'); M.terms = M.terms.filter(x => x !== t); termCache.clear(); save(); closePop(); refresh();
      toast('용어를 지웠습니다', true);
    });
    el.querySelector('.p-view')?.addEventListener('click', () => { closePop(); openTermView(t); });
  }

  // every line with the term, all languages side by side (C6)
  function openTermView(t) {
    closeModal();
    const hits = termLines(t), shown = hits.slice(0, 300);
    const el = modal = document.createElement('div');
    el.className = 'm-modal'; el.setAttribute('role', 'dialog'); el.setAttribute('aria-label', `용어 ${t.name}`);
    el.innerHTML = `<div class="mm-box">
      <div class="mm-head"><b>${esc(t.name)}</b> <span class="t-forms">${formsHtml(t)}</span>
        <span class="m-sub">${hits.length}줄${hits.length > shown.length ? ` (앞 ${shown.length}줄 표시)` : ''}</span><button type="button" class="m-x" aria-label="닫기">×</button></div>
      <div class="mm-list">${shown.map(({ e, l }) => `<div class="mm-row">
        <button class="m-link" data-l="${l[0]}">${l[0]}</button> <span class="m-sub">${esc(V.epLabel(e))}${l[1] ? ' · ' + esc(V.spkName(l[1], V.primary())) : ''}</span>
        ${LANGS.filter(k => rawText(l, k)).map(k => `<div class="mm-lang"><i>${TAG[k]}</i><span class="mm-text" data-lang="${k}">${V.rich(rawText(l, k))}</span></div>`).join('')}
      </div>`).join('')}</div></div>`;
    app.appendChild(el);
    el.querySelectorAll('.mm-row').forEach(row => {
      const l = lineMap.get(row.querySelector('.m-link').dataset.l)?.l;
      row.querySelectorAll('.mm-text').forEach(b => markTerms(b, b.dataset.lang, l));
    });
    el.querySelector('.m-x').onclick = closeModal;
    el.addEventListener('click', ev => { if (ev.target === el) closeModal(); });
  }

  // a new word annotation would overlap existing ones: widen one of them, edit it, or add a separate one anyway
  function openOverlapChooser(block, s, e, hit, rect, separate) {
    closePop(); closeSelBar();
    const text = block.textContent, el = pop = document.createElement('div');
    el.className = 'm-pop'; el.setAttribute('role', 'dialog'); el.setAttribute('aria-label', '겹치는 주석');
    el.innerHTML = `
      <div class="p-head"><b>겹치는 주석이 있습니다</b> <q>${esc(text.slice(s, e))}</q><button type="button" class="m-x p-x" aria-label="닫기">×</button></div>
      <div class="p-choices">${hit.map((h, i) => {
        const q = (h.link || h.a).quote, wider = Math.min(s, h.s) < h.s || Math.max(e, h.e) > h.e;
        return `<div class="p-choice" style="--ac:${colorOf(h.a.color)}"><span class="p-cq"><q>${esc(q)}</q><span>${esc(h.a.text || '(내용 없음)')}</span></span>
          ${wider ? `<button type="button" class="m-btn" data-grow="${i}">범위 넓히기</button>` : ''}<button type="button" class="m-btn" data-edit="${i}">편집</button></div>`;
      }).join('')}</div>
      <div class="p-acts"><button type="button" class="m-btn p-sep">그래도 따로 달기</button></div>`;
    place(el, rect);
    el.querySelector('.p-x').onclick = closePop;
    el.querySelector('.p-sep').onclick = separate;
    el.querySelector('.p-choices').onclick = ev => {
      const b = ev.target.closest('[data-grow],[data-edit]'); if (!b) return;
      const h = hit[b.dataset.grow ?? b.dataset.edit];
      if (b.dataset.edit != null) return openAnnEditor(h.a, rect);
      checkpoint('주석 범위 넓히기');
      Object.assign(h.link || h.a, anchorAt(text, Math.min(s, h.s), Math.max(e, h.e)));
      h.a.updated = Date.now();
      save(); closePop(); refresh();
      toast(`주석 범위를 「${(h.link || h.a).quote}」(으)로 넓혔습니다`, true);
    };
  }
  // one point carries several annotations (double underline): pick which one to open
  function openMarkChooser(ids, rect) {
    closePop(); closeSelBar();
    const list = ids.map(annById).filter(Boolean);
    const el = pop = document.createElement('div');
    el.className = 'm-pop'; el.setAttribute('role', 'dialog'); el.setAttribute('aria-label', '주석 고르기');
    el.innerHTML = `
      <div class="p-head"><b>이 부분의 주석 ${list.length}개</b><button type="button" class="m-x p-x" aria-label="닫기">×</button></div>
      <div class="p-choices">${list.map((a, i) => `<button type="button" class="p-choice" data-i="${i}" style="--ac:${colorOf(a.color)}"><span class="p-cq"><q>${esc(a.quote)}</q><span>${esc(a.text || '(내용 없음)')}</span></span></button>`).join('')}</div>`;
    place(el, rect);
    el.querySelector('.p-x').onclick = closePop;
    el.querySelector('.p-choices').onclick = ev => {
      const b = ev.target.closest('[data-i]'); if (b) openAnnEditor(list[b.dataset.i], rect);
    };
  }

  // selection toolbar over the script (B3, C3, A6)
  function showSelBar(block, range) {
    closeSelBar();
    const lineEl = block.closest('.ln'); if (!lineEl) return;
    const lineId = lineEl.id.slice(1), lang = block.dataset.lang, an = anchorOf(block, range);
    if (!an.quote.trim()) return;
    const s = startOf(block, range), e = s + an.quote.length;
    const r = lineMap.get(lineId); if (!r) return;
    const el = selBar = document.createElement('div');
    el.className = 'm-selbar'; el.setAttribute('role', 'toolbar'); el.setAttribute('aria-label', '선택한 글자');
    el.innerHTML = '<button type="button" data-act="ann">주석</button><button type="button" data-act="term">용어로 등록</button><button type="button" data-act="quote">노트에 인용</button>';
    const rect = range.getBoundingClientRect();
    place(el, rect);
    el.addEventListener('mousedown', ev => ev.preventDefault());   // keep the selection
    el.onclick = ev => {
      const act = ev.target.closest('[data-act]')?.dataset.act; if (!act) return;
      getSelection().removeAllRanges(); closeSelBar();
      if (act === 'ann') {
        const fresh = () => openAnnEditor({ id: uid(), kind: 'span', c: r.e.c, line: lineId, lang, ...an, text: '', color: 'yellow', tags: [], links: [] }, rect);
        const hit = overlapping(spanRangesIn(block, lineId, lang), s, e);
        const same = hit.find(h => h.s === s && h.e === e);
        if (same) openAnnEditor(same.a, rect);             // exactly the same letters: open what is there
        else if (hit.length) openOverlapChooser(block, s, e, hit, rect, fresh);
        else fresh();
      }
      else if (act === 'term') openTermEditor({ id: uid(), name: an.quote.trim(), forms: { [lang]: [an.quote.trim()] }, note: '', color: 'blue' }, rect, lineId);
      else insertIntoNote(`> ${an.quote.trim()} [[${lineId}]]`);
    };
  }

  /* ================= reader decoration ================= */
  function keepScroll(fn) { const b = $('rBody'), top = b.scrollTop; fn(); b.scrollTop = top; }
  function decorate(e) {
    closePop(); closeSelBar();
    // B2: episode annotation icon next to the title (faint until written)
    const pov = document.querySelector('#rHead .r-pov');
    if (pov) {
      const a = M.anns.find(x => x.kind === 'ep' && x.c === e.c);
      const b = document.createElement('button');
      b.type = 'button'; b.className = `m-epann${a ? '' : ' empty'}`; b.dataset.epAnn = e.c;
      b.innerHTML = ICON_EPANN; b.title = a ? a.text || '회차 주석' : '회차 주석 쓰기';
      b.setAttribute('aria-label', a ? '회차 주석 보기' : '회차 주석 쓰기');
      if (a) b.style.setProperty('--ac', colorOf(a.color));
      // quoting the episode into a note is separate from its annotation
      const q = document.createElement('button');
      q.type = 'button'; q.className = 'm-epann m-epquote empty'; q.dataset.epQuote = e.c;
      q.innerHTML = ICON_QUOTE; q.title = '노트에 인용'; q.setAttribute('aria-label', '이 회차를 노트에 인용');
      pov.append(b, q);
    }
    if (V.state.tab !== 'script') { if (ui.tab === 'ep') renderPanel(); return; }
    for (const lineEl of document.querySelectorAll('#rBody .ln[id^="L"]')) {
      const id = lineEl.id.slice(1);
      const l = lineMap.get(id)?.l;
      lineEl.querySelectorAll('[data-lang]').forEach(block => { markTerms(block, block.dataset.lang, l); markSpans(block, block.dataset.lang, id); });
      const la = M.anns.find(x => x.kind === 'line' && x.line === id);
      const tools = document.createElement('span');
      tools.className = 'm-tools';
      tools.innerHTML = (la ? `<button type="button" class="m-lineann" data-line-ann="${id}" style="--ac:${colorOf(la.color)}" title="${esc(la.text || '대사 주석')}" aria-label="대사 주석 보기">💬</button>`
        : `<button type="button" class="m-lineadd" data-line-ann="${id}" title="대사 주석 달기" aria-label="대사 주석 달기">＋</button>`) +
        // quoting into a note is its own action; it never creates an annotation
        `<button type="button" class="m-lineadd m-linequote" data-line-quote="${id}" title="노트에 인용" aria-label="이 대사를 노트에 인용">❝</button>` +
        (mentions.has(id) ? `<button type="button" class="m-notebadge" data-open-note="${[...mentions.get(id)][0]}" title="이 줄을 언급한 노트 열기">노트</button>` : '');
      lineEl.appendChild(tools);
    }
    if (ui.tab === 'ep') renderPanel();
  }

  // delegated handlers on the reader body / head (they are re-rendered, the containers stay)
  function annById(id) { return M.anns.find(a => a.id === id); }
  function goAnn(a) {
    if (!a) return;
    if (a.kind === 'ep' || !a.line) V.openEpisode(a.c, null, 'script'); else V.openEpisode(a.c, a.line, 'script');
  }
  function openNote(id) { if (!M.notes.some(n => n.id === id)) return; ui.note = id; ui.tab = 'notes'; ui.mode = 'view'; saveUi(); if (panel.hidden) setOpen(true); else renderPanel(); }
  function goLink(btn) {
    if (btn.dataset.c) { if (byChrono.get(+btn.dataset.c)) V.openEpisode(+btn.dataset.c, null, 'script'); else toast(`#${btn.dataset.c} 회차가 없습니다`); return; }
    const r = lineMap.get(btn.dataset.l);
    if (r) { closeModal(); V.openEpisode(r.e.c, btn.dataset.l, 'script'); } else toast(`${btn.dataset.l} 대사가 없습니다`);
  }
  function onClick(ev) {
    const t = ev.target;
    const ep = t.closest('[data-ep-ann]');
    if (ep) {
      const c = +ep.dataset.epAnn;
      const a = M.anns.find(x => x.kind === 'ep' && x.c === c) || { id: uid(), kind: 'ep', c, text: '', color: 'yellow', tags: [] };
      return openAnnEditor(a, ep.getBoundingClientRect());
    }
    const eq = t.closest('[data-ep-quote]');
    if (eq) { const e = byChrono.get(+eq.dataset.epQuote); if (e) insertIntoNote(`> ${V.epLabel(e)} [[#${e.c}]]`); return; }
    const lq = t.closest('[data-line-quote]');
    if (lq) {
      const id = lq.dataset.lineQuote, r = lineMap.get(id); if (!r) return;
      return insertIntoNote(`> ${V.plain(rawText(r.l, V.primary()) || r.l[3]).replace(/\n/g, ' ')} [[${id}]]`);
    }
    const ln = t.closest('[data-line-ann]');
    if (ln) {
      const id = ln.dataset.lineAnn, r = lineMap.get(id);
      const a = M.anns.find(x => x.kind === 'line' && x.line === id) || { id: uid(), kind: 'line', c: r.e.c, line: id, text: '', color: 'yellow', tags: [] };
      return openAnnEditor(a, ln.getBoundingClientRect());
    }
    const mark = t.closest('.ann-mark');
    if (mark) {
      const ids = [];
      for (let m = mark; m; m = m.parentElement.closest('.ann-mark')) if (!ids.includes(m.dataset.ann)) ids.push(m.dataset.ann);
      return ids.length > 1 ? openMarkChooser(ids, mark.getBoundingClientRect()) : openAnnEditor(annById(mark.dataset.ann), mark.getBoundingClientRect());
    }
    const term = t.closest('.term-mark');
    if (term) { const tt = M.terms.find(x => x.id === term.dataset.term); if (tt) openTermEditor(tt, term.getBoundingClientRect(), term.closest('.ln')?.id.slice(1)); return; }
    const nb = t.closest('[data-open-note]'); if (nb) return openNote(nb.dataset.openNote);
    const go = t.closest('[data-ann-go]'); if (go) return goAnn(annById(go.dataset.annGo));
    const ed = t.closest('[data-ann-edit]'); if (ed) { const a = annById(ed.dataset.annEdit); if (a) openAnnEditor(a, ed.getBoundingClientRect()); return; }
    const tv = t.closest('[data-term-view]'); if (tv) { const tt = M.terms.find(x => x.id === tv.dataset.termView); if (tt) openTermView(tt); return; }
    const te = t.closest('[data-term-edit]'); if (te) { const tt = M.terms.find(x => x.id === te.dataset.termEdit); if (tt) openTermEditor(tt, te.getBoundingClientRect()); return; }
    const lk = t.closest('.m-link'); if (lk) return goLink(lk);
  }
  $('rBody').addEventListener('click', onClick);
  $('rHead').addEventListener('click', onClick);
  panel.addEventListener('click', ev => {
    const tab = ev.target.closest('[data-mt]'); if (tab) return setTab(tab.dataset.mt);
    if (ev.target.closest('#tNew')) return openTermEditor({ id: uid(), name: '', forms: {}, note: '', color: 'blue' }, ev.target.getBoundingClientRect());
    onClick(ev);
  });
  document.addEventListener('click', ev => { if (modal && modal.contains(ev.target) && ev.target.closest('.m-link')) goLink(ev.target.closest('.m-link')); });
  $('rBody').addEventListener('mouseup', () => {
    setTimeout(() => {
      const sel = getSelection();
      if (!sel.rangeCount || sel.isCollapsed) { closeSelBar(); return; }
      const range = sel.getRangeAt(0);
      const block = range.startContainer.parentElement?.closest('#rBody .ln [data-lang]');
      if (block && block.contains(range.endContainer)) showSelBar(block, range); else closeSelBar();
    }, 0);
  });
  document.addEventListener('mousedown', ev => {
    if (selBar && !selBar.contains(ev.target)) closeSelBar();
    if (pop && !pop.contains(ev.target) && !ev.target.closest('[data-ep-ann],[data-line-ann],.ann-mark,.term-mark,[data-ann-edit],[data-term-edit],#tNew,#tNewData')) closePop();
  });

  /* ================= data tab: annotation list (D2) ================= */
  const vd = $('viewData');
  $('dtImgs').insertAdjacentHTML('afterend', '<button role="tab" id="dtAnns" aria-selected="false">주석</button>');
  $('dImgs').insertAdjacentHTML('afterend', `
    <div class="dbar" id="dAnnBar" hidden>
      <label>종류 <select id="aKind"><option value="">전체</option><option value="ep">회차</option><option value="line">대사</option><option value="span">단어</option></select></label>
      <label>색 <select id="aColor">${colorOpts('전체')}</select></label>
      <label>태그 <select id="aTag"></select></label>
      <label>찾기 <input id="aFind" type="search" placeholder="내용·인용"></label>
      <span class="info" id="aInfo"></span>
    </div>
    <div class="dlist dimgs" id="dAnns" hidden></div>`);
  $('dtAnns').onclick = () => V.setDataTab('anns');
  ['aKind', 'aColor', 'aTag'].forEach(id => $(id).onchange = renderAnnList);
  $('aFind').oninput = renderAnnList;
  $('dAnns').addEventListener('click', onClick);
  function renderAnnList() {
    const tagSel = $('aTag');
    tagSel.innerHTML = tagOpts('전체', tagSel.value);
    const list = filterAnns(M.anns, { kind: $('aKind').value, color: $('aColor').value, tag: tagSel.value, find: $('aFind').value }).sort(byPlace);
    $('aInfo').textContent = `${list.length}개 표시 (전체 ${M.anns.length}개) · 회차 순`;
    $('dAnns').innerHTML = list.length ? `<div class="a-list">${list.map(a => annItemHtml(a, true)).join('')}</div>` : '<div class="empty">주석이 없습니다.</div>';
  }

  /* ================= data tab: term list ================= */
  $('dtAnns').insertAdjacentHTML('afterend', '<button role="tab" id="dtTerms" aria-selected="false">용어</button>');
  $('dAnns').insertAdjacentHTML('afterend', `
    <div class="dbar" id="dTermBar" hidden>
      <label>정렬 <select id="tSort"><option value="name">이름순</option><option value="count">많이 나온 순</option><option value="updated">최근 수정순</option></select></label>
      <label>찾기 <input id="tFind" type="search" placeholder="이름·표기·설명"></label>
      <button class="btn" id="tNewData" type="button">＋ 새 용어</button>
      <span class="info" id="tInfo"></span>
    </div>
    <div class="dlist dimgs" id="dTerms" hidden></div>`);
  $('dtTerms').onclick = () => V.setDataTab('terms');
  $('tSort').onchange = renderTermList;
  $('tFind').oninput = renderTermList;
  $('tNewData').onclick = ev => openTermEditor({ id: uid(), name: '', forms: {}, note: '', color: 'blue' }, ev.currentTarget.getBoundingClientRect());
  $('dTerms').addEventListener('click', onClick);
  function renderTermList() {
    const q = $('tFind').value.trim().toLowerCase(), sort = $('tSort').value;
    const list = M.terms.filter(t => !q || `${t.name} ${allForms(t).join(' ')} ${(t.excl || []).join(' ')} ${t.note || ''}`.toLowerCase().includes(q));
    if (sort === 'count') list.sort((a, b) => termLines(b).length - termLines(a).length);
    else if (sort === 'updated') list.sort((a, b) => (b.updated || 0) - (a.updated || 0));
    else list.sort((a, b) => a.name.localeCompare(b.name, 'ko'));
    $('tInfo').textContent = `${list.length}개 표시 (전체 ${M.terms.length}개)`;
    $('dTerms').innerHTML = list.length ? `<div class="a-list t-list">${list.map(t => {
      const lines = termLines(t), eps = new Set(lines.map(h => h.e.c)).size;
      return `<div class="m-item term" style="--ac:${colorOf(t.color)}">
        <div class="t-name">${esc(t.name)}</div>
        <div class="t-forms">${formsHtml(t)}</div>
        ${t.note ? `<div class="m-text">${esc(t.note)}</div>` : ''}
        <div class="m-item-acts"><span>${lines.length}줄 · ${eps}회차</span><time>${fmtTime(t.updated)}</time><button data-term-view="${t.id}">모아 보기</button><button data-term-edit="${t.id}">편집</button></div>
      </div>`;
    }).join('')}</div>` : `<div class="empty">${M.terms.length ? '조건에 맞는 용어가 없습니다.' : '용어가 없습니다. 대본에서 글자를 선택해 \'용어로 등록\'을 누르거나 ＋ 새 용어로 만듭니다.'}</div>`;
  }

  /* ================= detail tab (B8) and search (D4) ================= */
  function detailHtml(e) {
    const list = annsOf(e);
    if (!list.length) return '';
    return `<div class="dsec"><h3>주석 — ${list.length}개</h3>${list.map(a => annItemHtml(a)).join('')}</div>`;
  }
  function searchHtml(q) {
    const ql = q.toLowerCase(), out = [];
    const snip = s => { const t = s.replace(/\s+/g, ' '), i = t.toLowerCase().indexOf(ql), st = Math.max(0, i - 30); return (st ? '…' : '') + esc(t.slice(st, i)) + '<mark>' + esc(t.slice(i, i + q.length)) + '</mark>' + esc(t.slice(i + q.length, i + q.length + 60)); };
    for (const n of M.notes) {
      const hay = `${n.title || ''}\n${n.body || ''}`;
      if (hay.toLowerCase().includes(ql)) out.push(`<button class="res res-memo" data-open-note="${n.id}"><div class="rm"><b class="src">노트</b> ${esc(n.title || '제목 없음')}</div><div class="rt">${snip(hay)}</div></button>`);
    }
    for (const a of M.anns) {
      const hay = `${a.text || ''} ${a.quote || ''} ${(a.tags || []).map(t => '#' + t).join(' ')}`;
      if (!hay.toLowerCase().includes(ql)) continue;
      const e = byChrono.get(a.c);
      out.push(`<button class="res res-memo" data-ann-go="${a.id}"><div class="rm"><b class="src">주석</b> ${KIND[a.kind]}${e ? ' · ' + esc(V.epLabel(e)) : ''}${a.line ? ' · ' + a.line : ''}</div><div class="rt">${snip(hay)}</div></button>`);
    }
    for (const t of M.terms) {
      const hay = `${t.name} ${allForms(t).join(' ')} ${t.note || ''}`;
      if (hay.toLowerCase().includes(ql)) out.push(`<button class="res res-memo" data-term-view="${t.id}"><div class="rm"><b class="src">용어</b> ${esc(t.name)}</div><div class="rt">${snip(hay)}</div></button>`);
    }
    return out.slice(0, 60).join('');
  }
  $('results').addEventListener('click', ev => {
    if (!ev.target.closest('.res-memo')) return;
    $('results').classList.remove('open');
    onClick(ev);
  });

  /* ================= export / import (E2, E3) ================= */
  function download(name, text, type) {
    const url = URL.createObjectURL(new Blob([text], { type: `${type};charset=utf-8` }));
    const a = document.createElement('a'); a.href = url; a.download = name; document.body.appendChild(a); a.click(); a.remove();
    setTimeout(() => URL.revokeObjectURL(url), 1000);
  }
  $('mExport').onclick = () => {
    const d = new Date(), stamp = `${d.getFullYear()}${String(d.getMonth() + 1).padStart(2, '0')}${String(d.getDate()).padStart(2, '0')}`;
    download(`infalsus-memo-${stamp}.json`, JSON.stringify({ app: 'infalsus-viewer-memo', ...M, exported: Date.now() }, null, 2), 'application/json');
  };
  $('mImport').onclick = () => $('mFile').click();
  $('mFile').onchange = async () => {
    const f = $('mFile').files[0]; $('mFile').value = '';
    if (!f) return;
    let data;
    try { data = JSON.parse(await f.text()); } catch { toast('JSON 파일을 읽지 못했습니다'); return; }
    if (!data || !Array.isArray(data.notes) || !Array.isArray(data.anns) || !Array.isArray(data.terms)) { toast('노트 백업 파일이 아닙니다'); return; }
    checkpoint('불러오기');
    let added = 0, updated = 0;
    for (const key of ['notes', 'anns', 'terms']) for (const item of data[key]) {
      if (!item || !item.id) continue;
      const i = M[key].findIndex(x => x.id === item.id);
      if (i < 0) { M[key].push(item); added++; }
      else if ((item.updated || 0) > (M[key][i].updated || 0)) { M[key][i] = item; updated++; }   // newer wins
    }
    normalizeTerms(); termCache.clear(); save(); refresh();
    toast(`불러오기: ${added}개 추가, ${updated}개 갱신`, true);
  };

  /* ================= keys, refresh, public hooks ================= */
  window.addEventListener('keydown', ev => {
    const editing = ev.target.matches?.('input, textarea, select, [contenteditable]');
    if (ev.key === 'Escape') {
      if (pop) { closePop(); ev.stopImmediatePropagation(); return; }
      if (selBar) { closeSelBar(); ev.stopImmediatePropagation(); return; }
      if (modal) { closeModal(); ev.stopImmediatePropagation(); return; }
    }
    if ((ev.ctrlKey || ev.metaKey) && !ev.shiftKey && ev.key.toLowerCase() === 'z' && !editing) { ev.preventDefault(); undo(); }
    if (editing && (pop?.contains(ev.target) || panel.contains(ev.target))) ev.stopImmediatePropagation();   // arrows / F stay in the text box
  }, true);
  $('memoBtn').onclick = () => setOpen(panel.hidden);
  $('mClose').onclick = () => setOpen(false);

  function refresh() {
    reindex();
    renderPanel();
    if (V.state.open) keepScroll(V.renderReader);
    if (!$('dAnns').hidden) renderAnnList();
    if (!$('dTerms').hidden) renderTermList();
    if ($('fAnn')?.checked) V.refreshData();
  }

  // reader closed: the 주석 tab goes back to listing every annotation
  const readerClosed = () => { closePop(); closeSelBar(); if (ui.tab === 'ep') renderPanel(); };
  window.IFMemo = { decorate, detailHtml, searchHtml, renderAnnList, renderTermList, readerClosed, lineHasAnn: id => annLines.has(id) };
  if (ui.open) setOpen(true);
  if (V.state.open) keepScroll(V.renderReader);
})();
