/**
 * core.js — финансовый движок «Латте» (личный финансовый трекер).
 *
 * Чистый модуль без DOM: все деньги в целых копейках (minor units),
 * все балансы выводятся из журнала операций, а не хранятся отдельно.
 * Это гарантирует, что правка/удаление операции корректно пересчитывает всё.
 */

export const SCHEMA_VERSION = 2;

/** Метка сборки: видна в настройках, чтобы точно знать, какая версия открыта. */
export const BUILD = '2026-11-02 · lumo 1.1';

export const TYPE = {
  INCOME: 'income',
  EXPENSE: 'expense',
  REFUND: 'refund',
  TRANSFER: 'transfer',
  ENV_TRANSFER: 'env_transfer',
  ENV_REBALANCE: 'env_rebalance',
  CRYPTO_BUY: 'crypto_buy',
  CRYPTO_SELL: 'crypto_sell',
  CRYPTO_SPEND: 'crypto_spend',
  TAX_PAYMENT: 'tax_payment',
  ADJUSTMENT: 'adjustment',
};

export const TYPE_LABELS = {
  income: 'Доход',
  expense: 'Расход',
  refund: 'Возврат',
  transfer: 'Перевод',
  env_transfer: 'Перевод конвертов',
  env_rebalance: 'Перераспределение конвертов',
  crypto_buy: 'Покупка крипты',
  crypto_sell: 'Продажа крипты',
  crypto_spend: 'Трата крипты',
  tax_payment: 'Уплата налога',
  adjustment: 'Корректировка',
};

/* ─────────────────────────── деньги ─────────────────────────── */

export const roundCents = (n) => Math.round(n);

/** '1 234,56' | '1234.56' | 1234.56 -> 123456 (копейки). null при ошибке. */
export function parseAmountToCents(input) {
  if (input === null || input === undefined) return null;
  let s = String(input).trim();
  if (!s) return null;
  s = s.replace(/[\s\u00a0\u202f₽$€]/g, '').replace(',', '.');
  if (!/^-?\d*(\.\d{0,2})?$/.test(s)) return null;
  if (s === '' || s === '-' || s === '.') return null;
  const num = Number(s);
  if (!Number.isFinite(num)) return null;
  const cents = Math.round(num * 100);
  return Number.isSafeInteger(cents) ? cents : null;
}

/** Копейки -> число для поля ввода (без локали). */
export function centsToInput(cents) {
  if (!Number.isFinite(cents)) return '';
  const sign = cents < 0 ? '-' : '';
  const abs = Math.abs(cents);
  const rub = Math.floor(abs / 100);
  const kop = abs % 100;
  return sign + (kop ? `${rub}.${String(kop).padStart(2, '0')}` : String(rub));
}

/** Строгое сложение копеек: защита от накопления ошибки float. */
export function sumCents(list) {
  let total = 0;
  for (const v of list) total += roundCents(v);
  return total;
}

export const qty8 = (n) => Math.round((Number(n) || 0) * 1e8) / 1e8;

/** Распределение суммы дохода по конвертам. Остаток всегда уходит в конверт-остаток. */
export function distribute(baseCents, envelopes) {
  const alloc = {};
  const base = roundCents(baseCents);
  let used = 0;
  const withPercent = envelopes.filter((e) => e.percent !== null && e.percent !== undefined && e.percent !== '');
  for (const env of withPercent) {
    const requested = roundCents((base * Number(env.percent)) / 100);
    const part = base >= 0 ? Math.max(0, Math.min(base - used, requested)) : requested;
    alloc[env.id] = part;
    used += part;
  }
  const rest = envelopes.find((e) => e.percent === null || e.percent === undefined || e.percent === '');
  if (rest) {
    alloc[rest.id] = base - used;
  } else if (used !== base) {
    // нет конверта-остатка: раздаём копейки по первому конверту, чтобы не терять деньги
    const first = envelopes[0];
    if (first) alloc[first.id] = (alloc[first.id] || 0) + (base - used);
  }
  return alloc;
}

export function taxAccrualFor(amountCents, ratePercent) {
  const rate = Number(ratePercent);
  if (!Number.isFinite(rate) || rate <= 0) return 0;
  return roundCents((roundCents(amountCents) * rate) / 100);
}

/* ─────────────────────────── журнал ─────────────────────────── */

export function sortTx(a, b) {
  if (a.date !== b.date) return a.date < b.date ? -1 : 1;
  return String(a.createdAt || '').localeCompare(String(b.createdAt || ''));
}

export function cmpTxDesc(a, b) {
  if (a.date !== b.date) return a.date < b.date ? 1 : -1;
  return String(b.createdAt || '').localeCompare(String(a.createdAt || ''));
}

export function findAccount(state, id) {
  return state.accounts.find((a) => a.id === id) || null;
}

export function cryptoAssets(state) {
  const out = [];
  for (const acc of state.accounts) {
    if (acc.kind !== 'crypto') continue;
    for (const asset of acc.assets || []) out.push({ ...asset, accountId: acc.id });
  }
  return out;
}

/**
 * Главный расчёт. Всё в копейках.
 * Возвращает снимок: балансы счетов, конвертов, налоговый резерв, крипта.
 */
export function computeState(state) {
  const accounts = state.accounts.map((a) => ({ ...a }));
  const fiat = {};
  for (const a of accounts) fiat[a.id] = roundCents(a.opening || 0);

  const assets = cryptoAssets(state);
  const qty = {};
  for (const asset of assets) qty[asset.id] = qty8(asset.initialQty || 0);

  const envBalances = {};
  for (const e of state.envelopes) envBalances[e.id] = 0;

  const tax = {
    accrued: 0,
    reserved: 0,
    pending: 0,
    paid: 0,
    items: [],
  };

  const tx = [...state.transactions].sort(sortTx);

  for (const t of tx) {
    const amount = roundCents(t.amount || 0);
    switch (t.type) {
      case TYPE.INCOME: {
        if (fiat[t.accountId] !== undefined) fiat[t.accountId] += amount;
        const alloc = t.alloc || {};
        for (const envId of Object.keys(alloc)) {
          if (envBalances[envId] === undefined) continue;
          envBalances[envId] += roundCents(alloc[envId]);
        }
        if (amount > 0) {
          const accrued = roundCents(t.taxAccrued || 0);
          if (accrued > 0) {
            const reserved = t.reserved !== false;
            tax.accrued += accrued;
            if (reserved) tax.reserved += accrued;
            tax.items.push({
              txId: t.id,
              date: t.date,
              amount: accrued,
              reserved,
              rate: t.taxRate ?? null,
              base: amount,
            });
          }
        }
        break;
      }
      case TYPE.EXPENSE: {
        if (fiat[t.accountId] !== undefined) fiat[t.accountId] -= amount;
        if (t.envelopeId && envBalances[t.envelopeId] !== undefined) {
          envBalances[t.envelopeId] -= amount;
        }
        break;
      }
      case TYPE.REFUND: {
        if (fiat[t.accountId] !== undefined) fiat[t.accountId] += amount;
        if (t.envelopeId && envBalances[t.envelopeId] !== undefined) {
          envBalances[t.envelopeId] += amount;
        }
        break;
      }
      case TYPE.TRANSFER: {
        if (fiat[t.accountId] !== undefined) fiat[t.accountId] -= amount;
        if (fiat[t.toAccountId] !== undefined) fiat[t.toAccountId] += amount;
        break;
      }
      case TYPE.ENV_TRANSFER: {
        if (envBalances[t.envelopeId] !== undefined) envBalances[t.envelopeId] -= amount;
        if (envBalances[t.toEnvelopeId] !== undefined) envBalances[t.toEnvelopeId] += amount;
        break;
      }
      case TYPE.ENV_REBALANCE: {
        for (const [id, delta] of Object.entries(t.alloc || {})) {
          if (envBalances[id] !== undefined) envBalances[id] += roundCents(delta);
        }
        break;
      }
      case TYPE.CRYPTO_BUY: {
        if (qty[t.assetId] !== undefined) qty[t.assetId] = qty8(qty[t.assetId] + Number(t.qty || 0));
        if (amount > 0 && fiat[t.accountId] !== undefined) fiat[t.accountId] -= amount;
        break;
      }
      case TYPE.CRYPTO_SELL: {
        if (qty[t.assetId] !== undefined) qty[t.assetId] = qty8(qty[t.assetId] - Number(t.qty || 0));
        if (amount > 0 && fiat[t.accountId] !== undefined) fiat[t.accountId] += amount;
        break;
      }
      case TYPE.CRYPTO_SPEND: {
        if (qty[t.assetId] !== undefined) qty[t.assetId] = qty8(qty[t.assetId] - Number(t.qty || 0));
        if (t.envelopeId && envBalances[t.envelopeId] !== undefined && amount > 0) {
          envBalances[t.envelopeId] -= amount;
        }
        break;
      }
      case TYPE.TAX_PAYMENT: {
        if (fiat[t.accountId] !== undefined) fiat[t.accountId] -= amount;
        tax.paid += amount;
        break;
      }
      case TYPE.ADJUSTMENT: {
        if (fiat[t.accountId] !== undefined) fiat[t.accountId] += amount;
        break;
      }
      default:
        break;
    }
  }

  tax.pending = Math.max(0, tax.accrued - tax.reserved);
  tax.reserveAvailable = Math.max(0, tax.reserved - tax.paid);
  tax.overpaid = Math.max(0, tax.paid - tax.reserved);

  const assetsOut = assets.map((a) => {
    const quantity = qty8(qty[a.id] || 0);
    const price = roundCents(a.price || 0);
    return { ...a, qty: quantity, value: roundCents(quantity * price) };
  });
  const cryptoValue = sumCents(assetsOut.map((a) => a.value));

  let fiatTotal = 0;
  const accountsOut = accounts.map((a) => {
    if (a.kind === 'crypto') {
      const value = sumCents(assetsOut.filter((x) => x.accountId === a.id).map((x) => x.value));
      return { ...a, balance: value, isCrypto: true };
    }
    const balance = roundCents(fiat[a.id] || 0);
    fiatTotal += balance;
    return { ...a, balance, isCrypto: false };
  });

  const envelopes = state.envelopes.map((e) => ({
    ...e,
    balance: roundCents(envBalances[e.id] || 0),
    share: e.percent === null || e.percent === undefined || e.percent === '' ? null : Number(e.percent),
  }));
  const envelopeTotal = sumCents(envelopes.map((e) => e.balance));

  return {
    accounts: accountsOut,
    fiatTotal,
    cryptoValue,
    cryptoAssets: assetsOut,
    total: fiatTotal + cryptoValue,
    envelopes,
    envelopeTotal,
    tax,
    available: fiatTotal - tax.reserveAvailable,
    unallocated: fiatTotal - tax.reserveAvailable - envelopeTotal,
  };
}

/* ─────────────────────────── агрегаты для статистики ─────────────────────────── */

export function txTouchesAccount(t, accountId) {
  if (!accountId) return true;
  if (t.accountId === accountId) return true;
  if (t.toAccountId === accountId) return true;
  return false;
}

/** Доходы/расходы без крипты, переводов и налога. */
export function summarize(state, list) {
  let income = 0;
  let expenseGross = 0;
  let refunds = 0;
  let taxPaid = 0;
  let cryptoSpent = 0;
  let cryptoBuy = 0;
  let cryptoSell = 0;
  const byCategory = new Map();
  const byIncomeCategory = new Map();
  const byAccount = new Map();

  for (const t of list) {
    const amount = roundCents(t.amount || 0);
    switch (t.type) {
      case TYPE.INCOME: {
        income += amount;
        const key = t.categoryId || 'none';
        byIncomeCategory.set(key, (byIncomeCategory.get(key) || 0) + amount);
        byAccount.set(t.accountId, (byAccount.get(t.accountId) || 0) + amount);
        break;
      }
      case TYPE.EXPENSE: {
        expenseGross += amount;
        const key = t.categoryId || 'none';
        byCategory.set(key, (byCategory.get(key) || 0) + amount);
        byAccount.set(t.accountId, (byAccount.get(t.accountId) || 0) - amount);
        break;
      }
      case TYPE.REFUND: {
        refunds += amount;
        const key = t.categoryId || 'none';
        byCategory.set(key, (byCategory.get(key) || 0) - amount);
        byAccount.set(t.accountId, (byAccount.get(t.accountId) || 0) + amount);
        break;
      }
      case TYPE.CRYPTO_SPEND:
        cryptoSpent += amount;
        break;
      case TYPE.CRYPTO_BUY:
        cryptoBuy += amount;
        break;
      case TYPE.CRYPTO_SELL:
        cryptoSell += amount;
        break;
      case TYPE.TAX_PAYMENT:
        taxPaid += amount;
        break;
      default:
        break;
    }
  }

  const expenses = expenseGross - refunds;
  return {
    income,
    expenses,
    expenseGross,
    refunds,
    net: income - expenses,
    taxPaid,
    cryptoSpent,
    cryptoBuy,
    cryptoSell,
    byCategory: [...byCategory.entries()]
      .map(([id, amount]) => ({ id, amount }))
      .filter((x) => x.amount !== 0)
      .sort((a, b) => b.amount - a.amount),
    byIncomeCategory: [...byIncomeCategory.entries()]
      .map(([id, amount]) => ({ id, amount }))
      .sort((a, b) => b.amount - a.amount),
    byAccount,
  };
}

/** Месячная серия 'YYYY-MM' -> {income, expenses, taxAccrued, taxPaid} */
export function monthlySeries(list, months) {
  const map = new Map();
  for (const m of months) map.set(m, { month: m, income: 0, expenses: 0, taxAccrued: 0, taxPaid: 0, refunds: 0 });
  for (const t of list) {
    const m = String(t.date || '').slice(0, 7);
    if (!map.has(m)) continue;
    const row = map.get(m);
    const amount = roundCents(t.amount || 0);
    if (t.type === TYPE.INCOME) row.income += amount;
    else if (t.type === TYPE.EXPENSE) row.expenses += amount;
    else if (t.type === TYPE.REFUND) row.refunds += amount;
    else if (t.type === TYPE.TAX_PAYMENT) row.taxPaid += amount;
    if (t.type === TYPE.INCOME) row.taxAccrued += roundCents(t.taxAccrued || 0);
  }
  return [...map.values()].map((r) => ({ ...r, expenses: r.expenses - r.refunds }));
}

/** Накопленный баланс (только фиат) по дням — для графика динамики. */
export function balanceSeries(state, fromDate, toDate) {
  const opening = state.accounts.filter((a) => a.kind !== 'crypto').reduce((s, a) => s + roundCents(a.opening || 0), 0);
  const tx = [...state.transactions].sort(sortTx).filter((t) => t.date <= toDate);
  const points = [];
  let value = opening;
  const start = fromDate < (tx[0]?.date || fromDate) ? fromDate : fromDate;
  points.push({ date: start, value });
  for (const t of tx) {
    const amount = roundCents(t.amount || 0);
    if (t.date < start) {
      // операции до периода — только влияют на стартовое значение
      if (t.type === TYPE.INCOME) value += amount;
      else if (t.type === TYPE.EXPENSE) value -= amount;
      else if (t.type === TYPE.REFUND) value += amount;
      else if (t.type === TYPE.TRANSFER) { /* внутренние */ }
      else if (t.type === TYPE.CRYPTO_BUY) value -= amount;
      else if (t.type === TYPE.CRYPTO_SELL) value += amount;
      else if (t.type === TYPE.TAX_PAYMENT) value -= amount;
      else if (t.type === TYPE.ADJUSTMENT) value += amount;
      const last = points[points.length - 1];
      last.value = value;
      continue;
    }
    if (t.type === TYPE.INCOME) value += amount;
    else if (t.type === TYPE.EXPENSE) value -= amount;
    else if (t.type === TYPE.REFUND) value += amount;
    else if (t.type === TYPE.CRYPTO_BUY) value -= amount;
    else if (t.type === TYPE.CRYPTO_SELL) value += amount;
    else if (t.type === TYPE.TAX_PAYMENT) value -= amount;
    else if (t.type === TYPE.ADJUSTMENT) value += amount;
    points.push({ date: t.date, value });
  }
  points.push({ date: toDate, value });
  return points;
}

/* ─────────────────────────── валидация ─────────────────────────── */

const FIAT_KINDS = ['card', 'cash'];

export function accountIsFiat(state, id) {
  const a = findAccount(state, id);
  return !!a && FIAT_KINDS.includes(a.kind);
}

export function validateTransaction(state, t) {
  const errors = [];
  const amount = roundCents(t.amount || 0);
  const acc = findAccount(state, t.accountId);
  if (!Object.values(TYPE).includes(t.type)) errors.push('Неизвестный тип операции');
  if (!Number.isSafeInteger(t.amount)) errors.push('Введите корректную сумму в пределах точности');

  if (!t.date || !/^\d{4}-\d{2}-\d{2}$/.test(t.date)) errors.push('Укажите дату операции');
  else {
    const date = new Date(`${t.date}T12:00:00Z`);
    if (!Number.isFinite(date.getTime()) || date.toISOString().slice(0, 10) !== t.date) errors.push('Такой даты не существует');
  }

  const needsFiat = [TYPE.INCOME, TYPE.EXPENSE, TYPE.REFUND, TYPE.TRANSFER, TYPE.TAX_PAYMENT, TYPE.ADJUSTMENT];
  if (needsFiat.includes(t.type) && !acc) errors.push('Выберите счёт');
  if (needsFiat.includes(t.type) && acc && acc.kind === 'crypto') {
    errors.push('Для криптосчёта используйте покупку, продажу или трату крипты');
  }

  if (t.type === TYPE.ADJUSTMENT) {
    if (amount === 0) errors.push('Сумма корректировки не может быть нулевой');
  } else if (![TYPE.CRYPTO_BUY, TYPE.CRYPTO_SELL, TYPE.CRYPTO_SPEND, TYPE.ENV_REBALANCE].includes(t.type)) {
    if (!(amount > 0)) errors.push('Сумма должна быть больше нуля');
  }

  if (t.type === TYPE.TRANSFER) {
    if (!findAccount(state, t.toAccountId)) errors.push('Выберите счёт получателя');
    if (t.toAccountId === t.accountId) errors.push('Счёт списания и зачисления совпадают');
    if (findAccount(state, t.toAccountId)?.kind === 'crypto') errors.push('Перевод на криптосчёт не поддерживается');
  }

  if (t.type === TYPE.ENV_TRANSFER) {
    if (!t.envelopeId || !t.toEnvelopeId) errors.push('Выберите оба конверта');
    if (t.envelopeId === t.toEnvelopeId) errors.push('Выберите разные конверты');
  }
  for (const id of [t.envelopeId, t.toEnvelopeId].filter(Boolean)) {
    if (!state.envelopes.some((e) => e.id === id)) errors.push('Конверт не найден');
  }
  if (t.type === TYPE.ENV_REBALANCE) {
    if (amount !== 0 || !t.alloc || !Object.keys(t.alloc).length) errors.push('Нет распределения');
    for (const [id, delta] of Object.entries(t.alloc || {})) {
      if (!state.envelopes.some((e) => e.id === id) || !Number.isSafeInteger(delta)) errors.push('Некорректное распределение');
    }
  }

  if ([TYPE.CRYPTO_BUY, TYPE.CRYPTO_SELL, TYPE.CRYPTO_SPEND].includes(t.type)) {
    if (!cryptoAssets(state).some((a) => a.id === t.assetId)) errors.push('Выберите существующий криптоактив');
    if (!Number.isFinite(Number(t.qty)) || qty8(t.qty) <= 0) errors.push('Количество должно быть больше нуля (до 8 знаков)');
    if ([TYPE.CRYPTO_SELL, TYPE.CRYPTO_SPEND].includes(t.type) && Number.isFinite(Number(t.qty))) {
      const before = computeState({ ...state, transactions: state.transactions.filter((x) => x.id !== t.id) });
      const held = before.cryptoAssets.find((a) => a.id === t.assetId)?.qty || 0;
      if (qty8(t.qty) > held) errors.push('Недостаточно криптовалюты для списания');
    }
    if (amount < 0) errors.push('Стоимость не может быть отрицательной');
    if (t.type === TYPE.CRYPTO_SPEND && !(amount > 0)) errors.push('Укажите стоимость списанной крипты');
    if (amount > 0 && t.accountId && !accountIsFiat(state, t.accountId)) {
      errors.push('Денежная часть операции возможна только с карты или наличных');
    }
  }

  if (t.type === TYPE.TAX_PAYMENT && !(amount > 0)) errors.push('Сумма налога должна быть больше нуля');

  return errors;
}

/* ─────────────────────────── даты ─────────────────────────── */

export const isoToday = (d = new Date()) => {
  const y = d.getFullYear();
  const m = String(d.getMonth() + 1).padStart(2, '0');
  const day = String(d.getDate()).padStart(2, '0');
  return `${y}-${m}-${day}`;
};

export const monthKey = (iso) => String(iso || '').slice(0, 7);

export function addMonths(key, delta) {
  const [y, m] = key.split('-').map(Number);
  const d = new Date(Date.UTC(y, m - 1 + delta, 1));
  return `${d.getUTCFullYear()}-${String(d.getUTCMonth() + 1).padStart(2, '0')}`;
}

export function monthRange(key) {
  const [y, m] = key.split('-').map(Number);
  const last = new Date(Date.UTC(y, m, 0)).getUTCDate();
  return { from: `${key}-01`, to: `${key}-${String(last).padStart(2, '0')}` };
}

export function lastMonths(n, endKey) {
  const out = [];
  for (let i = n - 1; i >= 0; i--) out.push(addMonths(endKey, -i));
  return out;
}

export const inRange = (date, from, to) => date >= from && date <= to;
