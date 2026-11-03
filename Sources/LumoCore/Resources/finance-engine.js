// Generated from the audited web core. Do not edit.
(function () {
'use strict';
// core.js sha256:4b2d463286b67041c1619ff48a53d5ffaf93c4bb90a5191da6322253a135f614
/**
 * core.js — финансовый движок «Латте» (личный финансовый трекер).
 *
 * Чистый модуль без DOM: все деньги в целых копейках (minor units),
 * все балансы выводятся из журнала операций, а не хранятся отдельно.
 * Это гарантирует, что правка/удаление операции корректно пересчитывает всё.
 */

const SCHEMA_VERSION = 2;

/** Метка сборки: видна в настройках, чтобы точно знать, какая версия открыта. */
const BUILD = '2026-11-02 · lumo 1.1';

const TYPE = {
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

const TYPE_LABELS = {
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

const roundCents = (n) => Math.round(n);

/** '1 234,56' | '1234.56' | 1234.56 -> 123456 (копейки). null при ошибке. */
function parseAmountToCents(input) {
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
function centsToInput(cents) {
  if (!Number.isFinite(cents)) return '';
  const sign = cents < 0 ? '-' : '';
  const abs = Math.abs(cents);
  const rub = Math.floor(abs / 100);
  const kop = abs % 100;
  return sign + (kop ? `${rub}.${String(kop).padStart(2, '0')}` : String(rub));
}

/** Строгое сложение копеек: защита от накопления ошибки float. */
function sumCents(list) {
  let total = 0;
  for (const v of list) total += roundCents(v);
  return total;
}

const qty8 = (n) => Math.round((Number(n) || 0) * 1e8) / 1e8;

/** Распределение суммы дохода по конвертам. Остаток всегда уходит в конверт-остаток. */
function distribute(baseCents, envelopes) {
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

function taxAccrualFor(amountCents, ratePercent) {
  const rate = Number(ratePercent);
  if (!Number.isFinite(rate) || rate <= 0) return 0;
  return roundCents((roundCents(amountCents) * rate) / 100);
}

/* ─────────────────────────── журнал ─────────────────────────── */

function sortTx(a, b) {
  if (a.date !== b.date) return a.date < b.date ? -1 : 1;
  return String(a.createdAt || '').localeCompare(String(b.createdAt || ''));
}

function cmpTxDesc(a, b) {
  if (a.date !== b.date) return a.date < b.date ? 1 : -1;
  return String(b.createdAt || '').localeCompare(String(a.createdAt || ''));
}

function findAccount(state, id) {
  return state.accounts.find((a) => a.id === id) || null;
}

function cryptoAssets(state) {
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
function computeState(state) {
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

function txTouchesAccount(t, accountId) {
  if (!accountId) return true;
  if (t.accountId === accountId) return true;
  if (t.toAccountId === accountId) return true;
  return false;
}

/** Доходы/расходы без крипты, переводов и налога. */
function summarize(state, list) {
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
function monthlySeries(list, months) {
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
function balanceSeries(state, fromDate, toDate) {
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

function accountIsFiat(state, id) {
  const a = findAccount(state, id);
  return !!a && FIAT_KINDS.includes(a.kind);
}

function validateTransaction(state, t) {
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

const isoToday = (d = new Date()) => {
  const y = d.getFullYear();
  const m = String(d.getMonth() + 1).padStart(2, '0');
  const day = String(d.getDate()).padStart(2, '0');
  return `${y}-${m}-${day}`;
};

const monthKey = (iso) => String(iso || '').slice(0, 7);

function addMonths(key, delta) {
  const [y, m] = key.split('-').map(Number);
  const d = new Date(Date.UTC(y, m - 1 + delta, 1));
  return `${d.getUTCFullYear()}-${String(d.getUTCMonth() + 1).padStart(2, '0')}`;
}

function monthRange(key) {
  const [y, m] = key.split('-').map(Number);
  const last = new Date(Date.UTC(y, m, 0)).getUTCDate();
  return { from: `${key}-01`, to: `${key}-${String(last).padStart(2, '0')}` };
}

function lastMonths(n, endKey) {
  const out = [];
  for (let i = n - 1; i >= 0; i--) out.push(addMonths(endKey, -i));
  return out;
}

const inRange = (date, from, to) => date >= from && date <= to;

// schema.js sha256:87bebb8f8a448da399a2dd9b07d285894eda1127b638859c299acfedfffbc575
/**
 * schema.js — схема данных по умолчанию и миграции.
 * Здесь нет DOM и localStorage: модуль используется и приложением, и тестами.
 */


const DEFAULT_CATEGORIES = [
  { id: 'cat_income_freelance', kind: 'income', name: 'Фриланс', taxable: true, icon: 'briefcase' },
  { id: 'cat_income_salary', kind: 'income', name: 'Зарплата', taxable: true, icon: 'building' },
  { id: 'cat_income_music', kind: 'income', name: 'Музыка', taxable: true, icon: 'music' },
  { id: 'cat_income_gift', kind: 'income', name: 'Подарок', taxable: false, icon: 'gift' },
  { id: 'cat_income_other', kind: 'income', name: 'Другой доход', taxable: false, icon: 'sparkles' },

  { id: 'cat_food', kind: 'expense', name: 'Еда', taxable: false, icon: 'cup' },
  { id: 'cat_transport', kind: 'expense', name: 'Транспорт', taxable: false, icon: 'bus' },
  { id: 'cat_home', kind: 'expense', name: 'Дом', taxable: false, icon: 'home' },
  { id: 'cat_health', kind: 'expense', name: 'Здоровье', taxable: false, icon: 'heart' },
  { id: 'cat_fun', kind: 'expense', name: 'Развлечения', taxable: false, icon: 'star' },
  { id: 'cat_music_gear', kind: 'expense', name: 'Музыка и техника', taxable: false, icon: 'music' },
  { id: 'cat_subs', kind: 'expense', name: 'Подписки', taxable: false, icon: 'repeat' },
  { id: 'cat_other', kind: 'expense', name: 'Другое', taxable: false, icon: 'dots' },
];

function createDefaultState() {
  return {
    version: SCHEMA_VERSION,
    createdAt: new Date().toISOString(),
    settings: {
      currency: 'BYN',
      locale: 'ru-RU',
      balanceView: 'fiat', // 'fiat' | 'total'
      hideCrypto: false, // спрятать криптовалюту из интерфейса целиком
      autoReserve: true,
      taxEnabled: false,
      taxRate: 10,
    },
    accounts: [
      { id: 'acc_card', kind: 'card', name: 'Банковская карта', opening: 0, archived: false, color: '#4690FF' },
      { id: 'acc_cash', kind: 'cash', name: 'Наличные', opening: 0, archived: false, color: '#7EE0B8' },
      { id: 'acc_crypto', kind: 'crypto', name: 'Криптовалюта', opening: 0, archived: false, color: '#F2A65A', assets: [] },
    ],
    envelopes: [
      { id: 'env_music', name: 'Музыка', percent: 32, goal: 0, color: '#4690FF', icon: 'music' },
      { id: 'env_personal', name: 'Личные расходы', percent: 32, goal: 0, color: '#9B8CFF', icon: 'user' },
      { id: 'env_savings', name: 'Накопления', percent: null, goal: 0, color: '#4FD1A5', icon: 'shield' },
    ],
    categories: DEFAULT_CATEGORIES.map((c) => ({ ...c })),
    transactions: [],
  };
}

/** Приводит любой загруженный объект к актуальной схеме, не теряя данные. */
function migrate(raw) {
  const base = createDefaultState();
  if (!raw || typeof raw !== 'object') return base;

  const previousVersion = Number(raw.version) || 1;
  const state = {
    ...base,
    ...raw,
    settings: { ...base.settings, ...(raw.settings || {}) },
    accounts: Array.isArray(raw.accounts) && raw.accounts.length ? raw.accounts.map(normalizeAccount) : base.accounts,
    envelopes: Array.isArray(raw.envelopes) && raw.envelopes.length ? raw.envelopes.map(normalizeEnvelope) : base.envelopes,
    categories: Array.isArray(raw.categories) && raw.categories.length ? raw.categories : base.categories,
    transactions: Array.isArray(raw.transactions) ? raw.transactions.map(normalizeTx).filter(Boolean) : [],
  };

  // v2: учёт по умолчанию ведётся в белорусских рублях.
  // Меняем валюту только у пустого журнала, чтобы не переписать уже введённые суммы.
  if (previousVersion < 2 && state.settings.currency === 'RUB' && state.transactions.length === 0) {
    state.settings.currency = 'BYN';
  }

  state.version = SCHEMA_VERSION;
  return state;
}

function normalizeAccount(a) {
  return {
    id: String(a.id),
    kind: ['card', 'cash', 'crypto'].includes(a.kind) ? a.kind : 'card',
    name: String(a.name || 'Счёт'),
    opening: Number.isFinite(a.opening) ? Math.round(a.opening) : 0,
    archived: !!a.archived,
    color: a.color || '#4690FF',
    assets: Array.isArray(a.assets)
      ? a.assets.map((x) => ({
          id: String(x.id),
          symbol: String(x.symbol || 'COIN'),
          name: String(x.name || x.symbol || 'Актив'),
          price: Number.isFinite(x.price) ? Math.round(x.price) : 0,
          initialQty: Number(x.initialQty) || 0,
          updatedAt: x.updatedAt || null,
        }))
      : [],
  };
}

function normalizeEnvelope(e) {
  const percent = e.percent === null || e.percent === undefined || e.percent === '' ? null : Number(e.percent);
  return {
    id: String(e.id),
    name: String(e.name || 'Конверт'),
    percent: Number.isFinite(percent) ? percent : null,
    goal: Number.isFinite(e.goal) ? Math.round(e.goal) : 0,
    color: e.color || '#4690FF',
    icon: e.icon || 'wallet',
  };
}

function normalizeTx(t) {
  if (!t || !t.type || !t.id) return null;
  return {
    id: String(t.id),
    type: t.type,
    date: String(t.date || isoToday()),
    amount: Number.isFinite(t.amount) ? Math.round(t.amount) : 0,
    accountId: t.accountId || null,
    toAccountId: t.toAccountId || null,
    categoryId: t.categoryId || null,
    envelopeId: t.envelopeId || null,
    toEnvelopeId: t.toEnvelopeId || null,
    assetId: t.assetId || null,
    qty: Number(t.qty) || 0,
    comment: t.comment || '',
    alloc: t.alloc && typeof t.alloc === 'object' ? t.alloc : null,
    taxAccrued: Number.isFinite(t.taxAccrued) ? Math.round(t.taxAccrued) : 0,
    taxRate: t.taxRate ?? null,
    taxable: t.taxable === undefined ? null : t.taxable,
    reserved: t.reserved !== false,
    createdAt: t.createdAt || new Date().toISOString(),
    updatedAt: t.updatedAt || null,
  };
}

function makeId(prefix = 'tx') {
  const rand = Math.random().toString(36).slice(2, 8);
  return `${prefix}_${Date.now().toString(36)}${rand}`;
}

// commands.js sha256:401dadaa1ff837471f84ca2e9942f1062470fa3aca80040f7e526b419c47f652
/**
 * commands.js — единственное место, где из «черновика» операции
 * собирается полноценная запись: налоговое начисление и распределение по конвертам.
 * UI и тесты используют один и тот же путь, поэтому расчёты не расходятся.
 */


function isTaxableCategory(state, categoryId) {
  const cat = state.categories.find((c) => c.id === categoryId);
  return !!(cat && cat.kind === 'income' && cat.taxable);
}

/** Готовит операцию к сохранению. Не пишет в состояние. */
function prepareTransaction(state, draft, existing = null) {
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
function previewAllocation(state, amountCents, categoryId) {
  const taxable = isTaxableCategory(state, categoryId);
  const rate = state.settings.taxEnabled ? Number(state.settings.taxRate) || 0 : 0;
  const tax = taxable ? taxAccrualFor(amountCents, rate) : 0;
  const base = roundCents(amountCents) - tax;
  return { tax, base, alloc: distribute(base, state.envelopes) };
}

// store.js sha256:8fba1419992ec7795fc0947a523bcccda9532af9efb41e15bddd7d482bbb27a7
/**
 * store.js — состояние, сохранение в localStorage, операции над журналом.
 * Storage можно подменить (используется в тестах).
 */




const STORAGE_KEY = 'latte.finance.state.v1';
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

class ValidationError extends Error {
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

function createStore({ storage, key = STORAGE_KEY } = {}) {
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
    const previousQty = new Map(computeState(state).cryptoAssets.map((asset) => [asset.id, asset.qty]));
    for (const asset of computeState(next).cryptoAssets) {
      if (asset.qty < Math.min(0, previousQty.get(asset.id) ?? 0)) {
        throw new Error(`Изменение оставит отрицательный остаток ${asset.symbol}. Сначала исправьте связанные операции.`);
      }
    }
    return commit(next);
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
      update((s) => { s.transactions = s.transactions.filter((t) => t.id !== id); });
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

const store = createStore();

// Native transport only. Financial calculations remain in the audited core above.
let nativeStore = createStore();
const mutators = new Set(['addTransaction', 'updateTransaction', 'deleteTransaction', 'setReserved',
  'reserveAll', 'updateSettings', 'saveAccount', 'deleteAccount', 'saveEnvelope', 'setEnvelopePercents',
  'rebalanceEnvelopes', 'saveCategory', 'deleteCategory', 'saveAsset', 'deleteAsset']);

function nativeSnapshot(month) {
  const state = nativeStore.snapshot();
  const key = /^\d{4}-\d{2}$/.test(month || '') ? month : monthKey(isoToday());
  const range = monthRange(key);
  const summary = summarize(state, state.transactions.filter(t => inRange(t.date, range.from, range.to)));
  return { state, derived: computeState(state), month: key,
    summary: { ...summary, byAccount: Object.fromEntries(summary.byAccount) },
    months: monthlySeries(state.transactions, lastMonths(6, key)) };
}

globalThis.LumoBridge = {
  request(operation, payloadText) {
    // Never interpolate payload into executable JS: JSContext calls this function with strings.
    try {
      const payload = JSON.parse(payloadText || '{}');
      let value = null;
      if (operation === 'snapshot') value = nativeSnapshot(payload.month);
      else if (operation === 'export') value = nativeStore.exportJSON();
      else if (operation === 'import') {
        const parsed = JSON.parse(payload.text);
        const raw = parsed.state || parsed;
        if (Number(raw.version) > SCHEMA_VERSION) throw new Error('Эта копия создана более новой версией lumo');
        if (!raw || !Array.isArray(raw.accounts) || !Array.isArray(raw.transactions)) throw new Error('В файле нет данных трекера');
        if (raw.transactions.some(t => !t || !t.id || !Object.values(TYPE).includes(t.type))) throw new Error('В копии есть неизвестные операции');
        nativeStore.importJSON(payload.text);
      } else if (operation === 'parseAmount') {
        value = parseAmountToCents(payload.text);
        if (value === null) throw new Error('Введите сумму с точностью до двух знаков');
      } else if (operation === 'prepare') {
        const existing = nativeStore.get().transactions.find(t => t.id === payload.id) || null;
        value = prepareTransaction(nativeStore.get(), payload.draft, existing);
      } else if (operation === 'previewRebalance') value = nativeStore.previewRebalance();
      else if (mutators.has(operation)) value = nativeStore[operation](...(payload.args || [])) ?? null;
      else throw new Error('Неизвестная команда');
      return JSON.stringify({ ok: true, value });
    } catch (error) {
      return JSON.stringify({ ok: false, error: String(error.message || error) });
    }
  }
};

})();
