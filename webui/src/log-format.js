const escapeHtml = value => String(value).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;').replace(/'/g, '&#39;');
const escapeRegExp = value => value.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');

// Match only plaintext. Even keywords such as INFO, class, < or & cannot rewrite
// generated markup. Intersect syntax/search ranges so cross-token matches work.
export function formatLogLine(rawLine, keyword = '') {
  const raw = String(rawLine);
  const syntax = [];
  const search = [];
  const token = /(\d{4}-\d{2}-\d{2}[ T]\d{2}:\d{2}:\d{2})|(\b(?:[0-9]{1,3}\.){3}[0-9]{1,3}(?:\/[0-9]{1,2})?\b)|(\bINFO\b|\[INFO\])|(\bWARN(?:ING)?\b|\[WARN(?:ING)?\])|(\bERROR\b|\[ERROR\]|\bFAIL\b)/g;
  for (const match of raw.matchAll(token)) {
    const type = match[1] ? 'time' : match[2] ? 'ip' : match[3] ? 'info' : match[4] ? 'warn' : 'error';
    syntax.push({ start: match.index, end: match.index + match[0].length, type });
  }
  if (keyword) {
    const pattern = new RegExp(escapeRegExp(String(keyword)), 'gi');
    for (const match of raw.matchAll(pattern)) search.push({ start: match.index, end: match.index + match[0].length });
  }
  const boundaries = [...new Set([0, raw.length, ...syntax.flatMap(r => [r.start, r.end]), ...search.flatMap(r => [r.start, r.end])])].sort((a, b) => a - b);
  let html = '', s = 0, k = 0;
  for (let i = 0; i < boundaries.length - 1; i++) {
    const start = boundaries[i], end = boundaries[i + 1];
    while (syntax[s] && syntax[s].end <= start) s++;
    while (search[k] && search[k].end <= start) k++;
    const classes = [];
    if (syntax[s]?.start <= start && syntax[s].end >= end) classes.push(`log-token-${syntax[s].type}`);
    if (search[k]?.start <= start && search[k].end >= end) classes.push('log-token-highlight');
    const content = escapeHtml(raw.slice(start, end));
    html += classes.length ? `<span class="${classes.join(' ')}">${content}</span>` : content;
  }
  return `<div class="log-line">${html}</div>`;
}

export function filterLogLines(lines, keyword) {
  const needle = String(keyword).toLowerCase();
  return needle ? lines.filter(line => line.toLowerCase().includes(needle)) : lines;
}
