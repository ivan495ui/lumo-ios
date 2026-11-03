/**
 * store.js — состояние, сохранение в localStorage, операции над журналом.
 * Storage можно подменить (используется в тестах).
 */

import { createDefaultState, migrate, makeId } from './schema.js';
import { prepareTransaction } from './commands.js';
import { validateTransaction, SCHEMA_VERSION, isoToday, computeState, distribute, TYPE } from './core.js';

export const STORAGE_KEY = 'latte.finance.state.v1';
const BACKUP_KEY = 'latte.finance.backup.v1';

function clone(obj) {
  if (typeof structuredClone === 'function') return structuredClone(obj);
  return JSON.parse(JSON.stringify(obj));
}

class MemoryStorage {
  constructor() { this.map = new Map(); }
  getItem(k) { return this.map.has(k) ? this.map.get(k) : null; }
  setItem(k, v) { this.map.set(k, String(v)); }
  removeItem(k) { this.map.delete(k); }
}

export class ValidationError extends Error {
  constructor(errors) {
    super(errors.join('. '));
    this.name = 'ValidationError';
    this.errors = errors;
  }
}

function validatePercents(envelopes) {
  const fixed = envelopes.filter((e) => e.percent !== null);
  if (fixed.some((e) => !Number.isFinite(e.percent) || e.percent < 0 || e.percent > 100) ||
      fixed.reduce((sum, e) => sum + e.percent, 0) > 100.0000001) {
    throw new Error('Доли должны быть от 0 до 100%, а их сумма — не больше 100%');
  }
}

export function createStore({ storage, key = STORAGE_KEY, strictEnvelopeBalances = false } = {}) {
  const backend = storage || (typeof localStorage !== 'undefined' ? localStorage : new MemoryStorage());
  const listeners = new Set();
  let state = load();
  let hadSavedState = true;
  try { hadSavedState = Boolean(backend.getItem(key) || backend.getItem(BACKUP_KEY)); } catch { /* не затирать облако при недоступном localStorage */ }

  function load() {
    const readKey = (k) => {
      const raw = backend.getItem(k);
      if (!raw) return null;
      const parsed = JSON.parse(raw);
      return migrate(parsed);
    };
    try {
      const main = readKey(key);
      if (main) return main;
    } catch (err) {
      console.warn('Основная запись повреждена, пробую резервную копию', err);
    }
    try {
      const backup = readKey(BACKUP_KEY);
      if (backup) return backup;
    } catch {
      /* резервная копия тоже недоступна */
    }
    return createDefaultState();
  }

  function persist(next) {
    const json = JSON.stringify(next);
    backend.setItem(key, json);
    try {
      backend.setItem(BACKUP_KEY, json);
    } catch {
      /* резервная копия не критична */
    }
  }

  function emit() {
    for (const fn of listeners) fn(state);
  }

  function commit(next, { silent = false } = {}) {
    const prev = state;
    try {
      persist(next);
    } catch (err) {
      state = prev;
      throw new Error('Не удалось сохранить данные: возможно, закончилось место в браузере. Экспортируйте резервную копию.');
    }
    state = next;
    if (!silent) emit();
    return state;
  }

  function update(mutator) {
    const next = clone(state);
    mutator(next);
    // Imports may contain an old negative holding. Keep that history readable,
    // but never create a new deficit or deepen an existing one during a mutation.
    const before = computeState(state);
    const after = computeState(next);
    const previousQty = new Map(before.cryptoAssets.map((asset) => [asset.id, asset.qty]));
    for (const asset of after.cryptoAssets) {
      if (asset.qty < Math.min(0, previousQty.get(asset.id) ?? 0)) {
        throw new Error(`Изменение оставит отрицательный остаток ${asset.symbol}. Сначала исправьте связанные операции.`);
      }
    }
    if (strictEnvelopeBalances) {
      const balances = new Map(before.envelopes.map((envelope) => [envelope.id, envelope.balance]));
      for (const envelope of after.envelopes) {
        if (envelope.balance < Math.min(0, balances.get(envelope.id) ?? 0)) {
          throw new Error(`В конверте «${envelope.name}» не хватает денег. Выберите «Из всех денег» или измените сумму.`);
        }
      }
      if (after.unallocated < Math.min(0, before.unallocated)) {
        throw new Error('Не хватает свободных денег. Выберите «Из всех денег» или уменьшите сумму.');
      }
      if (after.available < Math.min(0, before.available)) {
        throw new Error('Не хватает денег без налогового резерва. Уменьшите сумму или сначала исправьте связанные операции.');
      }
      const accounts = new Map(before.accounts.filter((account) => account.kind !== 'crypto').map((account) => [account.id, account.balance]));
      for (const account of after.accounts.filter((value) => value.kind !== 'crypto')) {
        if (account.balance < Math.min(0, accounts.get(account.id) ?? 0)) {
          throw new Error(`На счёте «${account.name}» недостаточно денег. Выберите другой счёт или сначала запишите перевод.`);
        }
      }
    }
    return commit(next);
  }

  // Largest remainder allocation in integer minor units. No donor can be
  // overdrawn; stable array order breaks ties for a one-cent remainder.
  function proportionalCoverage(amount, donors) {
    const total = donors.reduce((sum, donor) => sum + donor.balance, 0);
    if (amount > total) throw new Error('Для покрытия расхода не хватает денег в конвертах');
    if (!amount) return {};
    const denominator = BigInt(total);
    const rows = donors.map((donor, index) => {
      const numerator = BigInt(amount) * BigInt(donor.balance);
      return { id: donor.id, index, cents: Number(numerator / denominator), remainder: numerator % denominator };
    });
    let rest = amount - rows.reduce((sum, row) => sum + row.cents, 0);
    for (const row of [...rows].sort((a, b) => a.remainder === b.remainder ? a.index - b.index : a.remainder > b.remainder ? -1 : 1)) {
      if (rest-- <= 0) break;
      row.cents++;
    }
    return Object.fromEntries(rows.filter((row) => row.cents).map((row) => [row.id, -row.cents]));
  }

  function expensePlan(draft, existingID = null, options = {}) {
    const current = existingID ? state.transactions.find((t) => t.id === existingID) : null;
    if (existingID && (!current || current.type !== TYPE.EXPENSE)) throw new Error('Расход не найден');
    const mode = options.mode || (draft.envelopeId ? 'envelope' : 'smart');
    if (!['smart', 'free', 'envelope'].includes(mode)) throw new Error('Выберите способ оплаты расхода');
    const baseState = clone(state);
    baseState.transactions = baseState.transactions.filter((t) => !existingID || (t.id !== existingID && t.coverageFor !== existingID));
    const base = normalizeDraft({ ...current, ...draft, type: TYPE.EXPENSE,
      id: current?.id || '__expense_preview__', createdAt: current?.createdAt || '__preview__',
      envelopeId: mode === 'envelope' ? draft.envelopeId : null });
    const prepared = prepareTransaction(baseState, base, current);
    const errors = validateTransaction(baseState, prepared);
    if (errors.length) throw new ValidationError(errors);
    if (mode === 'envelope' && !prepared.envelopeId) throw new Error('Выберите конверт');
    const before = computeState(baseState);
    const oldCoverage = current ? state.transactions.filter((t) => t.coverageFor === current.id) : [];
    const oldMode = current?.envelopeId ? 'envelope' : oldCoverage.length ? 'smart' : 'free';
    const sameFunding = current && mode === oldMode && prepared.amount === current.amount &&
      prepared.accountId === current.accountId && prepared.envelopeId === current.envelopeId;
    if (!sameFunding && prepared.amount > Math.max(0, before.available)) throw new Error('Для этого расхода не хватает денег без налогового резерва');
    if (!sameFunding && prepared.amount > Math.max(0, before.accounts.find((account) => account.id === prepared.accountId)?.balance || 0)) {
      throw new Error('На выбранном счёте недостаточно денег. Выберите другой счёт или сначала запишите перевод.');
    }
    let coverage = [];
    if (sameFunding) {
      coverage = oldCoverage.map((t) => ({ ...clone(t), date: prepared.date }));
    } else if (mode === 'smart') {
      const freeUsed = Math.min(prepared.amount, Math.max(0, before.unallocated));
      const needed = prepared.amount - freeUsed;
      if (needed) {
        const alloc = proportionalCoverage(needed, before.envelopes.filter((envelope) => envelope.balance > 0));
        coverage.push({ id: '__coverage_preview__', type: TYPE.ENV_REBALANCE, amount: 0, date: prepared.date,
          alloc, coverageFor: prepared.id, comment: 'Покрытие расхода из конвертов', createdAt: '__preview__' });
      }
    } else if (mode === 'free' && prepared.amount > Math.max(0, before.unallocated)) {
      throw new Error('Свободных денег не хватает. Выберите «Из всех денег» для покрытия из конвертов.');
    } else if (mode === 'envelope' && prepared.amount > (before.envelopes.find((e) => e.id === prepared.envelopeId)?.balance || 0)) {
      throw new Error('В выбранном конверте не хватает денег. Выберите «Из всех денег» для покрытия из остальных.');
    }
    const after = computeState({ ...baseState, transactions: [...baseState.transactions, ...coverage, prepared] });
    const rows = before.envelopes.map((envelope) => {
      const balance = after.envelopes.find((e) => e.id === envelope.id).balance;
      return { id: envelope.id, name: envelope.name, before: envelope.balance,
        used: envelope.balance - balance, after: balance };
    });
    const fingerprint = JSON.stringify([state, draft, existingID || null, mode]);
    return { baseState, prepared, coverage, preview: { amount: prepared.amount, mode, rows,
      freeBefore: before.unallocated, freeAfter: after.unallocated,
      freeUsed: Math.max(0, before.unallocated - after.unallocated), fingerprint } };
  }

  function releasePlan(amount) {
    if (!Number.isSafeInteger(amount) || amount <= 0) throw new Error('Укажите положительную сумму для освобождения');
    const before = computeState(state);
    if (amount > Math.max(0, before.available)) throw new Error('Не хватает денег без налогового резерва');
    const alloc = proportionalCoverage(amount, before.envelopes.filter((envelope) => envelope.balance > 0));
    const rows = before.envelopes.map((envelope) => ({ id: envelope.id, name: envelope.name,
      before: envelope.balance, used: -(alloc[envelope.id] || 0), after: envelope.balance + (alloc[envelope.id] || 0) }));
    return { alloc, preview: { amount, mode: 'release', rows, freeBefore: before.unallocated,
      freeAfter: before.unallocated + amount, freeUsed: 0, fingerprint: JSON.stringify([state, amount, 'release']) } };
  }

  function normalizeDraft(draft) {
    const t = { ...draft };
    t.amount = Math.round(Number(t.amount) || 0);
    t.qty = Number(t.qty) || 0;
    t.date = t.date || isoToday();
    t.comment = (t.comment || '').trim().slice(0, 280);
    return t;
  }

  const api = {
    get() { return state; },
    snapshot() { return clone(state); },
    hasSavedState() { return hadSavedState; },
    subscribe(fn) {
      listeners.add(fn);
      return () => listeners.delete(fn);
    },
    update,

    addTransaction(draft) {
      const base = normalizeDraft(draft);
      const prepared = prepareTransaction(state, {
        ...base,
        id: makeId('tx'),
        createdAt: new Date().toISOString(),
      });
      const errors = validateTransaction(state, prepared);
      if (errors.length) throw new ValidationError(errors);
      update((s) => { s.transactions.push(prepared); });
      return prepared;
    },

    updateTransaction(id, draft) {
      const current = state.transactions.find((t) => t.id === id);
      if (!current) throw new Error('Операция не найдена');
      if (strictEnvelopeBalances && current.coverageFor) throw new Error('Покрытие связано с расходом. Измените сам расход.');
      if (strictEnvelopeBalances && state.transactions.some((t) => t.coverageFor === id)) {
        throw new Error('Для изменения этого расхода используйте предпросмотр покрытия.');
      }
      const base = normalizeDraft({ ...current, ...draft, id });
      // налогооблагаемость берём из категории, если её не задали явно в форме
      if (!Object.prototype.hasOwnProperty.call(draft, 'taxable')) delete base.taxable;
      // при правке суммы дохода налог и распределение пересчитываются заново
      const prepared = prepareTransaction(state, base, current);
      prepared.updatedAt = new Date().toISOString();
      const errors = validateTransaction(state, prepared);
      if (errors.length) throw new ValidationError(errors);
      update((s) => {
        const idx = s.transactions.findIndex((t) => t.id === id);
        if (idx >= 0) s.transactions[idx] = prepared;
      });
      return prepared;
    },

    deleteTransaction(id) {
      if (strictEnvelopeBalances && state.transactions.find((t) => t.id === id)?.coverageFor) {
        throw new Error('Покрытие связано с расходом. Удалите сам расход.');
      }
      update((s) => { s.transactions = s.transactions.filter((t) => t.id !== id && (!strictEnvelopeBalances || t.coverageFor !== id)); });
    },

    previewExpense(draft, existingID = null, options = {}) {
      return expensePlan(draft, existingID, options).preview;
    },

    saveExpense(draft, existingID = null, options = {}, fingerprint) {
      const plan = expensePlan(draft, existingID, options);
      if (plan.preview.fingerprint !== fingerprint) throw new Error('Суммы изменились. Проверьте покрытие расхода ещё раз.');
      const id = existingID || makeId('tx');
      const now = new Date().toISOString();
      const expense = { ...plan.prepared, id, createdAt: existingID ? plan.prepared.createdAt : now,
        ...(existingID ? { updatedAt: now } : {}) };
      const coverage = plan.coverage.map((t) => ({ ...t,
        id: t.id === '__coverage_preview__' ? makeId('tx') : t.id, coverageFor: id,
        createdAt: t.createdAt === '__preview__' ? now : t.createdAt }));
      update((s) => { s.transactions = [...plan.baseState.transactions, ...coverage, expense]; });
      return expense;
    },

    previewRelease(amount) { return releasePlan(amount).preview; },

    releaseEnvelopeFunds(amount, fingerprint) {
      const plan = releasePlan(amount);
      if (plan.preview.fingerprint !== fingerprint) throw new Error('Суммы изменились. Проверьте освобождение денег ещё раз.');
      const transaction = { id: makeId('tx'), type: TYPE.ENV_REBALANCE, amount: 0, date: isoToday(),
        alloc: plan.alloc, comment: 'Освобождение денег из конвертов', createdAt: new Date().toISOString() };
      update((s) => { s.transactions.push(transaction); });
      return transaction;
    },

    setReserved(id, reserved) {
      update((s) => {
        const t = s.transactions.find((x) => x.id === id);
        if (t && t.type === 'income') t.reserved = !!reserved;
      });
    },

    reserveAll() {
      update((s) => {
        for (const t of s.transactions) {
          if (t.type === 'income' && (t.taxAccrued || 0) > 0) t.reserved = true;
        }
      });
    },

    updateSettings(patch) {
      update((s) => { s.settings = { ...s.settings, ...patch }; });
    },

    saveAccount(account) {
      if (!Number.isSafeInteger(account.opening ?? 0)) throw new Error('Некорректный стартовый баланс');
      update((s) => {
        const idx = s.accounts.findIndex((a) => a.id === account.id);
        if (idx >= 0) s.accounts[idx] = { ...s.accounts[idx], ...account };
        else s.accounts.push({ ...account, id: account.id || makeId('acc'), archived: false });
      });
    },

    deleteAccount(id) {
      const assetIds = new Set((state.accounts.find((a) => a.id === id)?.assets || []).map((a) => a.id));
      const used = state.transactions.some((t) => t.accountId === id || t.toAccountId === id || assetIds.has(t.assetId));
      if (used) throw new Error('По счёту есть операции. Удалить нельзя — можно скрыть счёт.');
      update((s) => { s.accounts = s.accounts.filter((a) => a.id !== id); });
    },

    saveEnvelope(envelope) {
      const proposed = state.envelopes.map((e) => e.id === envelope.id ? { ...e, ...envelope } : e);
      validatePercents(proposed);
      update((s) => {
        const idx = s.envelopes.findIndex((e) => e.id === envelope.id);
        if (idx >= 0) s.envelopes[idx] = { ...s.envelopes[idx], ...envelope };
      });
    },

    setEnvelopePercents(byId) {
      validatePercents(state.envelopes.map((e) => byId[e.id] === undefined ? e : { ...e, percent: byId[e.id] }));
      update((s) => {
        s.envelopes = s.envelopes.map((e) => (byId[e.id] === undefined ? e : { ...e, percent: byId[e.id] }));
      });
    },

    previewRebalance() {
      const d = computeState(state);
      if (d.available < 0) throw new Error('Сначала устраните отрицательный остаток на счетах');
      const target = distribute(d.available, state.envelopes);
      const rows = d.envelopes.map((e) => ({ id: e.id, name: e.name, before: e.balance, after: target[e.id] || 0 }));
      return { rows, available: d.available, free: d.unallocated,
        fingerprint: JSON.stringify([d.available, rows, state.envelopes.map((e) => e.percent)]) };
    },

    rebalanceEnvelopes(fingerprint) {
      const preview = api.previewRebalance();
      if (preview.fingerprint !== fingerprint) throw new Error('Суммы изменились. Откройте расчёт заново');
      const alloc = Object.fromEntries(preview.rows.map((r) => [r.id, r.after - r.before]));
      if (!Object.values(alloc).some(Boolean)) return false;
      const t = { id: makeId('tx'), type: TYPE.ENV_REBALANCE, date: isoToday(), amount: 0,
        alloc, comment: 'По текущим долям, без криптовалюты и налогового резерва', createdAt: new Date().toISOString() };
      const errors = validateTransaction(state, t);
      if (errors.length) throw new ValidationError(errors);
      update((s) => s.transactions.push(t));
      return true;
    },

    saveCategory(category) {
      update((s) => {
        const idx = s.categories.findIndex((c) => c.id === category.id);
        if (idx >= 0) s.categories[idx] = { ...s.categories[idx], ...category };
        else s.categories.push({ ...category, id: category.id || makeId('cat') });
      });
    },

    deleteCategory(id) {
      const used = state.transactions.some((t) => t.categoryId === id);
      if (used) throw new Error('Категория используется в операциях — её нельзя удалить');
      update((s) => { s.categories = s.categories.filter((c) => c.id !== id); });
    },

    saveAsset(accountId, asset) {
      if (!Number.isSafeInteger(asset.price) || asset.price < 0 || !Number.isFinite(asset.initialQty)) throw new Error('Проверьте количество и курс актива');
      update((s) => {
        const acc = s.accounts.find((a) => a.id === accountId);
        if (!acc) throw new Error('Криптосчёт не найден');
        acc.assets = acc.assets || [];
        const idx = acc.assets.findIndex((a) => a.id === asset.id);
        if (idx >= 0) acc.assets[idx] = { ...acc.assets[idx], ...asset, updatedAt: new Date().toISOString() };
        else acc.assets.push({ ...asset, id: asset.id || makeId('asset'), updatedAt: new Date().toISOString() });
      });
    },

    updateAssetPrice(accountId, assetId, priceCents) {
      update((s) => {
        const acc = s.accounts.find((a) => a.id === accountId);
        const asset = acc && (acc.assets || []).find((a) => a.id === assetId);
        if (asset) {
          asset.price = Math.round(priceCents);
          asset.updatedAt = new Date().toISOString();
        }
      });
    },

    deleteAsset(accountId, assetId) {
      if (state.transactions.some((t) => t.assetId === assetId)) throw new Error('По активу есть операции — его нельзя удалить');
      update((s) => {
        const acc = s.accounts.find((a) => a.id === accountId);
        if (acc) acc.assets = (acc.assets || []).filter((a) => a.id !== assetId);
      });
    },

    exportJSON() {
      return JSON.stringify({ app: 'lumo', version: SCHEMA_VERSION, exportedAt: new Date().toISOString(), state }, null, 2);
    },

    importJSON(text) {
      let parsed;
      try {
        parsed = JSON.parse(text);
      } catch {
        throw new Error('Файл повреждён: это не JSON');
      }
      const raw = parsed && parsed.state ? parsed.state : parsed;
      if (!raw || !Array.isArray(raw.transactions) || !Array.isArray(raw.accounts)) {
        throw new Error('В файле нет данных трекера');
      }
      const next = migrate(raw);
      return commit(next);
    },

    reset() {
      const fresh = createDefaultState();
      return commit(fresh);
    },

    storageBytes() {
      const raw = backend.getItem(key) || '';
      return new Blob([raw]).size;
    },
  };

  return api;
}

export const store = createStore();
