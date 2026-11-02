/**
 * schema.js — схема данных по умолчанию и миграции.
 * Здесь нет DOM и localStorage: модуль используется и приложением, и тестами.
 */

import { SCHEMA_VERSION, isoToday } from './core.js';

export const DEFAULT_CATEGORIES = [
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

export function createDefaultState() {
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
export function migrate(raw) {
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

export function makeId(prefix = 'tx') {
  const rand = Math.random().toString(36).slice(2, 8);
  return `${prefix}_${Date.now().toString(36)}${rand}`;
}
