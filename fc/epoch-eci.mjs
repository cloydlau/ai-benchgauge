import { normalizedBrandKey } from './brands.mjs';
import { countryCode } from './countries.mjs';

// Epoch publishes RFC 4180 CSV, including quoted names and JSON model versions.
export function csvRows(source) {
  const rows = []; let row = [], field = '', quoted = false, closed = false;
  const input = source.replace(/^\uFEFF/, '');
  for (let i = 0; i < input.length; i++) {
    const c = input[i];
    if (quoted) {
      if (c !== '"') field += c;
      else if (input[i + 1] === '"') { field += '"'; i++; }
      else { quoted = false; closed = true; }
    } else if (c === ',' || c === '\n' || c === '\r') {
      row.push(field); field = ''; closed = false;
      if (c !== ',') {
        if (row.some(value => value.length)) rows.push(row);
        row = [];
        if (c === '\r' && input[i + 1] === '\n') i++;
      }
    } else if (c === '"' && !field && !closed) quoted = true;
    else {
      if (closed || c === '"') throw new Error('Invalid ECI CSV');
      field += c;
    }
  }
  if (quoted) throw new Error('Truncated ECI CSV');
  row.push(field);
  if (row.some(value => value.length)) rows.push(row);
  return rows;
}

const countryNames = new Map();
const english = new Intl.DisplayNames(['en'], { type: 'region', fallback: 'none' });
for (let a = 65; a <= 90; a++) for (let b = 65; b <= 90; b++) {
  const code = countryCode(String.fromCharCode(a, b));
  if (code) countryNames.set(english.of(String.fromCharCode(a, b))?.toLowerCase(), code);
}
countryNames.set('united states of america', 'US');
export function epochCountryCode(value) { return countryCode(value) ?? countryNames.get(String(value ?? '').toLowerCase()); }

export function parseEpochECI(source, now) {
  const [header = [], ...data] = csvRows(source);
  const required = ['Model', 'Display name', 'eci', 'Organization', 'Country (of organization)', 'Accessibility group'];
  if (new Set(header).size !== header.length || required.some(key => !header.includes(key))) throw new Error('Invalid ECI header');
  const seen = new Set();
  const entries = data.map(row => {
    if (row.length !== header.length) throw new Error('Incomplete ECI row');
    const value = Object.fromEntries(header.map((key, index) => [key, row[index].trim()]));
    const modelID = value.Model, name = value['Display name'] || modelID, organization = value.Organization;
    const score = /^[+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?$/.test(value.eci) ? Number(value.eci) : NaN;
    if (!modelID || !name || name.length > 256 || modelID.length > 256 || organization.length > 256
      || /[\x00-\x1f\x7f]/.test(modelID + name + organization)
      || !Number.isFinite(score) || Math.abs(score) > 100000 || seen.has(modelID)) throw new Error('Invalid ECI model');
    seen.add(modelID);
    const openness = ({ 'Open weights': 'open', 'Closed weights': 'closed' })[value['Accessibility group']];
    const code = epochCountryCode(value['Country (of organization)']);
    const countryHint = code && organization ? { key: normalizedBrandKey(organization), countryCode: code } : null;
    return { modelID, name, score, ...(organization && { organization }), ...(openness && { openness }), ...(countryHint && { countryHint }) };
  });
  if (entries.length < 20 || entries.length > 5000) throw new Error('Incomplete ECI data');
  entries.sort((a, b) => b.score - a.score || (a.name.normalize('NFC') < b.name.normalize('NFC') ? -1 : 1));
  // `date` is the model's release date, not a source update timestamp.
  return { kind: 'epochECI', title: 'Epoch Capabilities Index', sourceNote: 'Epoch AI · ECI',
    fetchedAt: new Date(now).toISOString(), entries: entries.map((entry, index) => ({ rank: index + 1, ...entry })) };
}
