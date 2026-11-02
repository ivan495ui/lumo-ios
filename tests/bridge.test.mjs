import { test } from 'node:test';
import assert from 'node:assert/strict';
import vm from 'node:vm';
import { readFile } from 'node:fs/promises';
import { migrate } from '../Vendor/Finance/schema.js';
const script = await readFile(new URL('../Sources/LumoCore/Resources/finance-engine.js', import.meta.url), 'utf8');

function engine() {
  const context = vm.createContext({ console: { warn() {} } });
  vm.runInContext(script, context);
  function call(op, payload = {}) {
    const result = JSON.parse(context.LumoBridge.request(op, JSON.stringify(payload)));
    if (!result.ok) throw new Error(result.error);
    return result.value;
  }
  const mutate = (op, ...args) => call(op, { args });
  return { call, mutate, snapshot: month => call('snapshot', { month }) };
}
const income = { type: 'income', amount: 100000, accountId: 'acc_card', categoryId: 'cat_income_music', date: '2026-11-02' };

test('bundled bridge starts without browser globals and keeps native defaults', () => {
  const s = engine().snapshot('2026-11');
  assert.equal(s.state.settings.currency, 'BYN');
  assert.equal(s.state.settings.taxEnabled, false);
  assert.deepEqual(s.state.envelopes.map(e => e.percent), [32, 32, null]);
  assert.equal(s.derived.total, 0);
});
test('income, expense, fiat transfer and crypto preserve the invariant', () => {
  const e = engine();
  e.mutate('addTransaction', income);
  e.mutate('addTransaction', { type: 'expense', amount: 8500, accountId: 'acc_card', envelopeId: 'env_personal', date: income.date });
  e.mutate('addTransaction', { type: 'transfer', amount: 12000, accountId: 'acc_card', toAccountId: 'acc_cash', date: income.date });
  e.mutate('saveAsset', 'acc_crypto', { id: 'usdt', symbol: 'USDT', name: 'Tether', price: 330, initialQty: 120 });
  const { derived: d, summary } = e.snapshot('2026-11');
  assert.equal(d.fiatTotal, 91500); assert.equal(d.cryptoValue, 39600); assert.equal(d.total, 131100);
  assert.equal(d.fiatTotal, d.envelopeTotal + d.tax.reserveAvailable + d.unallocated);
  assert.equal(summary.income, 100000); assert.equal(summary.expenses, 8500);
  assert.deepEqual(d.envelopes.map(x => x.balance), [32000, 23500, 36000]);
});
test('month navigation filters totals without changing full state', () => {
  const e = engine(); e.mutate('addTransaction', income);
  e.mutate('addTransaction', { ...income, date: '2026-10-31', amount: 300 });
  assert.equal(e.snapshot('2026-10').summary.income, 300);
  assert.equal(e.snapshot('2026-11').summary.income, 100000);
  assert.equal(e.snapshot().derived.fiatTotal, 100300);
});
test('manual crypto receiving has no fiat debit, sell cannot overspend', () => {
  const e = engine(); e.mutate('saveAsset', 'acc_crypto', { id: 'usdt', symbol: 'USDT', name: 'Tether', price: 330, initialQty: 0 });
  e.mutate('addTransaction', { type: 'crypto_buy', amount: 3300, accountId: null, assetId: 'usdt', qty: 10, date: income.date });
  assert.equal(e.snapshot().derived.fiatTotal, 0);
  assert.equal(e.snapshot().derived.cryptoValue, 3300);
  assert.throws(() => e.mutate('addTransaction', { type: 'crypto_sell', amount: 3630, accountId: 'acc_card', assetId: 'usdt', qty: 11, date: income.date }), /Недостаточно/);
});
test('old web export roundtrips through native without losing allocation and tax history', () => {
  const e = engine(); e.mutate('updateSettings', { taxEnabled: true, taxRate: 10 }); e.mutate('addTransaction', income);
  const old = JSON.parse(e.call('export')); old.app = 'latte';
  const n = engine(); n.call('import', { text: JSON.stringify(old) });
  assert.deepEqual(n.snapshot().state, migrate(old.state));
  n.mutate('updateSettings', { taxEnabled: false, taxRate: 99 });
  const t = n.snapshot().state.transactions[0];
  n.mutate('updateTransaction', t.id, { comment: 'Только комментарий', taxable: true });
  assert.equal(n.snapshot().state.transactions[0].taxAccrued, 10000);
  assert.deepEqual(n.snapshot().state.transactions[0].alloc, t.alloc);
});
test('rebalance preview is explicit and rejects stale values', () => {
  const e = engine(); e.mutate('saveAccount', { id: 'acc_card', opening: 10001 });
  assert.equal(e.snapshot().derived.envelopeTotal, 0);
  const p = e.call('previewRebalance');
  assert.equal(p.rows.reduce((s, x) => s + x.after, 0), 10001);
  e.mutate('rebalanceEnvelopes', p.fingerprint);
  assert.equal(e.snapshot().derived.envelopeTotal, 10001);
  assert.throws(() => e.mutate('rebalanceEnvelopes', p.fingerprint), /изменились/);
});
test('JS input is passed as JSON data, never executed', () => {
  const e = engine(); const comment = "'); globalThis.hacked = true; // 😀 Привет";
  e.mutate('addTransaction', { ...income, comment });
  assert.equal(e.snapshot().state.transactions[0].comment, comment);
  assert.throws(() => e.call('eval', { text: '1+1' }), /Неизвестная/);
});
test('future or unknown-operation imports fail without replacing ledger', () => {
  const e = engine(); e.mutate('addTransaction', income);
  const original = e.call('export'); const data = JSON.parse(original);
  data.state.version = 999;
  assert.throws(() => e.call('import', { text: JSON.stringify(data) }), /новой/);
  data.state.version = 2; data.state.transactions[0].type = 'unknown';
  assert.throws(() => e.call('import', { text: JSON.stringify(data) }), /неизвестные/);
  assert.deepEqual(JSON.parse(e.call('export')).state, JSON.parse(original).state);
});
