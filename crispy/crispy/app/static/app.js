/* CRISpy front end.
   No framework: one form, one event stream, one renderer. */

const thread = document.getElementById('thread');
const opener = document.getElementById('opener');
const form   = document.getElementById('composer');
const input  = document.getElementById('q');
const send   = document.getElementById('send');

/* The raw SQL, kept out of the DOM. innerText is a rendering of the highlighted
   markup rather than the source: it normalises whitespace and depends on CSS.
   The clipboard gets the exact string the server produced. */
const SQL_STORE = [];

/* What survives between turns, and the question left hanging when CRISpy asks
   one. Held here rather than on the server because it belongs to this
   conversation: a second tab is a second conversation and should not inherit
   the first one's programme. */
let scope   = null;
let pending = null;

/* ------------------------------------------------------------- composer */

input.addEventListener('input', () => {
  input.style.height = 'auto';
  input.style.height = Math.min(input.scrollHeight, 144) + 'px';
});

input.addEventListener('keydown', e => {
  if (e.key === 'Enter' && !e.shiftKey) { e.preventDefault(); form.requestSubmit(); }
});

document.querySelectorAll('.sample').forEach(b => {
  b.addEventListener('click', () => { input.value = b.dataset.q; form.requestSubmit(); });
});

document.getElementById('about-toggle').addEventListener('click', e => {
  const panel = document.getElementById('about');
  const open  = panel.hasAttribute('hidden');
  panel.toggleAttribute('hidden', !open);
  e.currentTarget.setAttribute('aria-expanded', String(open));
});

form.addEventListener('submit', e => {
  e.preventDefault();
  const q = input.value.trim();
  if (!q) return;
  addTurn('user', esc(q));
  input.value = '';
  input.style.height = 'auto';
  ask({ question: q, scope, pending });
});

/* ------------------------------------------------------- the event stream */

async function ask(body) {
  opener?.remove();
  send.disabled = true;
  document.body.classList.add('working');

  const turn  = addTurn('crispy', '');
  const slot  = turn.querySelector('.turn-body');
  const steps = document.createElement('div');
  steps.className = 'steps';
  slot.appendChild(steps);

  try {
    const res = await fetch('/api/plan', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(body)
    });

    /* Server-sent events, read as they arrive. Each step lands the moment the
       model returns it, so a pipeline that takes several seconds shows what it
       understood while it is still deciding rather than after. */
    const reader  = res.body.getReader();
    const decoder = new TextDecoder();
    let buffer = '';

    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      buffer += decoder.decode(value, { stream: true });

      let cut;
      while ((cut = buffer.indexOf('\n\n')) >= 0) {
        const raw = buffer.slice(0, cut).replace(/^data: /, '');
        buffer = buffer.slice(cut + 2);
        if (!raw.trim()) continue;

        const ev = JSON.parse(raw);
        if (ev.type === 'step') {
          steps.appendChild(stepRow(ev.step, ev.detail));
          window.scrollTo({ top: document.body.scrollHeight, behavior: 'smooth' });
        } else {
          steps.remove();
          finish(slot, ev.payload);
        }
      }
    }
  } catch (err) {
    slot.innerHTML =
      `<p class="ask">The planner did not respond. Check that OPENAI_API_KEY is
       set in <code>.env</code> and that the container can reach the API.</p>`;
  } finally {
    send.disabled = false;
    document.body.classList.remove('working');
    window.scrollTo({ top: document.body.scrollHeight, behavior: 'smooth' });
  }
}

function stepRow(step, detail) {
  const el = document.createElement('div');
  el.className = 'step';
  el.innerHTML = `<span class="step-name">${esc(step)}</span>
                  <span class="step-detail">${esc(detail)}</span>`;
  return el;
}

/* ---------------------------------------------------------------- render */

function finish(slot, d) {
  pending = d.pending || null;
  if (d.scope) scope = d.scope;

  if (d.kind === 'clarify') {
    slot.innerHTML = `<div class="ask">${esc(d.message)}</div>`
                   + options(d.options) + trace(d.trace);
    wireChoices(slot);
    return;
  }
  if (d.kind !== 'plan') {
    slot.innerHTML = `<p class="plain">${esc(d.message || '')}</p>` + trace(d.trace);
    return;
  }

  const first = d.results[0];
  let html = scopeLine(first.resolved) + ruler(first.sql);

  for (const r of d.results) {
    html += `
      <div class="card">
        <div class="card-head">
          <span class="card-id">${esc(r.query_id)}</span>
          <span class="card-title">${esc(r.title)}</span>
          <span class="card-answers">${esc(r.answers)}</span>
        </div>
        <div class="sqlbar">
          <span>Snowflake · ready to run</span>
          <button class="copy" type="button"
                  data-sql-id="${SQL_STORE.push(r.sql) - 1}">Copy SQL</button>
        </div>
        <pre class="sql"><code>${highlight(r.sql)}</code></pre>
        ${chips(r.applied)}
      </div>`;
    for (const n of r.notes || []) html += `<div class="note">${esc(n)}</div>`;
  }

  if (d.alternatives && d.alternatives.length) {
    /* A candidate the resolver set aside because it is off air. Answering was
       the right call, but the person who wanted the other one should not have
       to retype the question to get it. */
    html += `<div class="alts">
      <span class="alts-label">Did you mean</span>` +
      d.alternatives.map((o, i) => `
        <button class="alt" type="button" data-alt="${i}">
          ${esc(o.label)}<span class="alt-sub">${esc(o.sub)}</span>
        </button>`).join('') +
      `<script type="application/json" class="alt-data">${
         JSON.stringify(d.alternatives.map(o => o.value))}<\/script></div>`;
  }

  slot.innerHTML = html + trace(d.trace);
  wireCopy(slot);
  wireAlts(slot);
  renderScopeBar();
}

/* Clicking an option sends the value itself, not a phrase to be matched again.
   That is the difference between answering the question and asking a narrower
   version of it: a PROGRAM_CODE cannot be ambiguous. */
function options(list) {
  if (!list || !list.length) return '';
  return `<div class="choices">` + list.map((o, i) => `
    <button class="choice" type="button" data-choice="${i}">
      <span class="choice-label">${esc(o.label)}</span>
      ${o.sub ? `<span class="choice-sub">${esc(o.sub)}</span>` : ''}
    </button>`).join('')
    + `</div><script type="application/json" class="choice-data">${
         JSON.stringify(list.map(o => o.value))}<\/script>`;
}

function wireChoices(root) {
  const data = root.querySelector('.choice-data');
  if (!data) return;
  const values = JSON.parse(data.textContent);
  root.querySelectorAll('.choice').forEach(btn => {
    btn.addEventListener('click', () => {
      const v = values[Number(btn.dataset.choice)];
      root.querySelectorAll('.choice').forEach(b => {
        b.disabled = true;
        b.classList.toggle('picked', b === btn);
      });
      addTurn('user', esc(btn.querySelector('.choice-label').textContent));
      ask({ question: '', scope, pending, choice: v });
    });
  });
}

function wireAlts(root) {
  const data = root.querySelector('.alt-data');
  if (!data) return;
  const values = JSON.parse(data.textContent);
  root.querySelectorAll('.alt').forEach(btn => {
    btn.addEventListener('click', () => {
      const v = values[Number(btn.dataset.alt)];
      root.querySelectorAll('.alt').forEach(b => { b.disabled = true; });
      addTurn('user', esc(btn.childNodes[0].textContent.trim()));
      ask({ question: '', scope, pending, choice: v });
    });
  });
}

function scopeLine(fields) {
  /* Every resolved field with where its value came from. A default, a carried
     value and a stated one are indistinguishable in the SQL, and only one of
     them is something the person chose this turn. The source column is how a
     reader tells whether the query answers the question they asked. */
  if (!Array.isArray(fields)) return '';
  return `<div class="scope-table">` + fields.map(f => `
    <div class="scope-row${/carried/i.test(f.source) ? ' carried' : ''}">
      <span class="scope-field">${esc(f.field)}</span>
      <span class="scope-value">${esc(f.value)}</span>
      <span class="scope-source">${esc(f.source)}</span>
    </div>`).join('') + `</div>`;
}

/* The bar above the composer: what a follow-up will inherit if it says nothing,
   and the button that empties it. The reported CRIS failure was carry-over
   nobody could see, so this is the fix as much as the carry-over itself. */
function renderScopeBar() {
  document.getElementById('scopebar')?.remove();
  if (!scope) return;
  const bits = [
    ['Network', scope.network], ['Program', scope.program],
    ['Season', scope.season], ['Demo', scope.demo], ['Stream', scope.stream]
  ].filter(([, v]) => v);
  if (!bits.length) return;

  const bar = document.createElement('div');
  bar.id = 'scopebar';
  bar.className = 'scopebar';
  bar.innerHTML = `<span class="scopebar-label">Following up on</span>` +
    bits.map(([k, v]) =>
      `<span class="scopebar-chip">${esc(k)} <b>${esc(v)}</b></span>`).join('') +
    `<button type="button" id="scope-clear">Clear</button>`;
  form.querySelector('.wrap').prepend(bar);
  document.getElementById('scope-clear').addEventListener('click', () => {
    scope = null; pending = null;
    bar.remove();
    addTurn('crispy', '<p class="plain">Context cleared. The next question '
                    + 'starts fresh.</p>');
  });
}

function chips(applied) {
  const ks = Object.keys(applied || {});
  if (!ks.length) return '';
  return `<div class="applied">` +
    ks.map(k => `<span class="chip">${esc(k)} <b>${esc(applied[k])}</b></span>`).join('') +
    `</div>`;
}

function trace(steps) {
  if (!steps || !steps.length) return '';
  return `<details class="trace"><summary>How CRISpy read this</summary>
    <ul class="trace-list">` +
    steps.map(s => `<li><b>${esc(s.step)}</b><span>${esc(s.detail)}</span></li>`).join('') +
    `</ul></details>`;
}

function addTurn(who, html) {
  const node = document.getElementById(who === 'user' ? 'tpl-user' : 'tpl-crispy')
                       .content.cloneNode(true);
  const art = node.querySelector('.turn');
  art.querySelector('.turn-body').innerHTML = html;
  thread.appendChild(node);
  window.scrollTo({ top: document.body.scrollHeight, behavior: 'smooth' });
  return art;
}

/* ------------------------------------------------- the broadcast day ruler */

function ruler(sql) {
  const grab = n => {
    const m = sql.match(new RegExp('SET\\s+' + n + '\\s*=\\s*(\\d+)\\s*;'));
    return m ? parseInt(m[1], 10) : null;
  };
  const from = grab('p_win_start_2959'), to = grab('p_win_end_2959');
  const DAY_A = 600, DAY_B = 2960;
  const pct = v => ((v - DAY_A) / (DAY_B - DAY_A)) * 100;

  let ticks = '';
  for (let h = 600; h <= 2900; h += 100) {
    ticks += `<span class="ruler-tick${h % 300 === 0 ? ' major' : ''}"
                    style="left:${pct(h)}%"></span>`;
  }
  const band = (from !== null && to !== null)
    ? `<span class="ruler-band" style="left:${pct(from)}%;width:${pct(to) - pct(from)}%"></span>`
    : '';
  const label = (from !== null && to !== null)
    ? `Window ${clock(from)}–${clock(to)}, exclusive at the end`
    : 'Whole broadcast day';

  return `
    <div class="ruler">
      <div class="ruler-track">${ticks}${band}</div>
      <div class="ruler-labels"><span>6:00A</span><span>NOON</span><span>8:00P</span><span>5:59A</span></div>
      <div class="ruler-note">${esc(label)} · Nielsen broadcast day, 0600–2959</div>
    </div>`;
}

function clock(v) {
  const h = Math.floor(v / 100), m = String(v % 100).padStart(2, '0');
  const h24 = h % 24, ap = h24 < 12 ? 'A' : 'P';
  return `${h24 % 12 === 0 ? 12 : h24 % 12}:${m}${ap}`;
}

/* ------------------------------------------------------------ highlighting */

const KEYWORDS = new Set(`
SET WITH SELECT DISTINCT FROM JOIN LEFT RIGHT INNER OUTER CROSS ON USING
WHERE AND OR NOT NULL AS GROUP BY ORDER PARTITION OVER QUALIFY HAVING LIMIT
CASE WHEN THEN ELSE END UNION ALL INTERSECT EXCEPT IS IN BETWEEN LIKE ILIKE
EXISTS ROWS RANGE UNBOUNDED PRECEDING FOLLOWING CURRENT ROW DESC ASC NULLS
FIRST LAST TRUE FALSE CREATE OR REPLACE TABLE CLUSTER
COALESCE NULLIF ROUND COUNT SUM AVG MIN MAX RANK ROW_NUMBER LAG LEAD
FIRST_VALUE LAST_VALUE IFF IDENTIFIER TO_DATE TO_VARCHAR TRY_TO_NUMBER
DATEADD DATEDIFF GREATEST LEAST CAST EQUAL_NULL MOD REGEXP_LIKE
REGEXP_REPLACE UPPER LOWER TRIM CURRENT_TIMESTAMP
`.trim().split(/\s+/));

/* Tokenise the RAW sql and escape each token as it is appended. Escaping first
   and running regexes over the result is subtly wrong in a way that only shows
   on copy: the escaped quote is &#39;, the number rule matched the 39 inside
   it, and the entity came apart into literal text. Escaping last is the rule. */
const TOKEN = /(\/\*[\s\S]*?\*\/|--[^\n]*)|('(?:''|[^'])*')|(\$\w+)|(\b\d+\b)|([A-Za-z_]\w*)/g;

function highlight(sql) {
  const out = [];
  let last = 0, m;
  TOKEN.lastIndex = 0;
  while ((m = TOKEN.exec(sql)) !== null) {
    out.push(esc(sql.slice(last, m.index)));
    if      (m[1]) out.push(`<span class="c">${esc(m[1])}</span>`);
    else if (m[2]) out.push(`<span class="s">${esc(m[2])}</span>`);
    else if (m[3]) out.push(`<span class="v">${esc(m[3])}</span>`);
    else if (m[4]) out.push(`<span class="n">${esc(m[4])}</span>`);
    else {
      const w = m[5];
      out.push(KEYWORDS.has(w.toUpperCase()) ? `<span class="k">${esc(w)}</span>` : esc(w));
    }
    last = TOKEN.lastIndex;
  }
  out.push(esc(sql.slice(last)));
  return out.join('');
}

function wireCopy(root) {
  root.querySelectorAll('.copy').forEach(btn => {
    btn.addEventListener('click', async () => {
      const sql = SQL_STORE[Number(btn.dataset.sqlId)];
      try {
        await navigator.clipboard.writeText(sql);
        btn.textContent = 'Copied'; btn.classList.add('done');
        setTimeout(() => { btn.textContent = 'Copy SQL'; btn.classList.remove('done'); }, 1800);
      } catch { btn.textContent = 'Press ⌘C'; }
    });
  });
}

function esc(s) {
  return String(s ?? '')
    .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;').replace(/'/g, '&#39;');
}
