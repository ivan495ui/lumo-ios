/**
 * commands.js — единственное место, где из «черновика» операции
 * собирается полноценная запись: налоговое начисление и распределение по конвертам.
 * UI и тесты используют один и тот же путь, поэтому расчёты не расходятся.
 */

import { TYPE, distribute, taxAccrualFor, roundCents } from './core.js';

export function isTaxableCategory(state, categoryId) {
  const cat = state.categories.find((c) => c.id === categoryId);
  return !!(cat && cat.kind === 'income' && cat.taxable);
}

/** Готовит операцию к сохранению. Не пишет в состояние. */
export function prepareTransaction(state, draft, existing = null) {
  const t = { ...draft };
  t.amount = roundCents(t.amount || 0);
  if (!t.date) t.date = new Date().toISOString().slice(0, 10);

  if (t.type === TYPE.INCOME) {
    const originalTaxable = existing?.taxable ?? (Number(existing?.taxAccrued) > 0);
    const taxable = t.taxable === null || t.taxable === undefined
      ? existing?.type === TYPE.INCOME && existing.categoryId === t.categoryId
        ? originalTaxable : isTaxableCategory(state, t.categoryId)
      : !!t.taxable;
    const sameTax = existing?.type === TYPE.INCOME && existing.categoryId === t.categoryId &&
      (draft.taxable == null || originalTaxable === !!draft.taxable);
    const rate = sameTax ? Number(existing.taxRate) || 0 : state.settings.taxEnabled ? Number(state.settings.taxRate) || 0 : 0;
    t.taxable = taxable;
    t.taxRate = taxable ? rate : null;
    t.taxAccrued = taxable ? taxAccrualFor(t.amount, rate) : 0;
    if (sameTax && t.amount === existing.amount) t.taxAccrued = existing.taxAccrued || 0;
    if (t.taxAccrued > t.amount) t.taxAccrued = t.amount;
    const base = t.amount - t.taxAccrued;
    t.alloc = sameTax && t.amount === existing.amount && existing.alloc
      ? { ...existing.alloc } : distribute(base, state.envelopes);
    if (t.reserved === null || t.reserved === undefined) {
      t.reserved = state.settings.autoReserve !== false;
    }
  } else {
    t.taxAccrued = 0;
    t.taxRate = null;
    t.alloc = null;
    t.reserved = t.reserved !== false;
  }
  return t;
}

/** Сумма распределения по конвертам (для превью в форме). */
export function previewAllocation(state, amountCents, categoryId) {
  const taxable = isTaxableCategory(state, categoryId);
  const rate = state.settings.taxEnabled ? Number(state.settings.taxRate) || 0 : 0;
  const tax = taxable ? taxAccrualFor(amountCents, rate) : 0;
  const base = roundCents(amountCents) - tax;
  return { tax, base, alloc: distribute(base, state.envelopes) };
}
