// Native transport only. Financial calculations remain in the audited core above.
let nativeStore = createStore({ strictEnvelopeBalances: true });
const mutators = new Set(['addTransaction', 'updateTransaction', 'deleteTransaction', 'setReserved',
  'reserveAll', 'updateSettings', 'saveAccount', 'deleteAccount', 'saveEnvelope', 'setEnvelopePercents',
  'rebalanceEnvelopes', 'saveCategory', 'deleteCategory', 'saveAsset', 'deleteAsset', 'saveExpense', 'releaseEnvelopeFunds']);

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
      } else if (operation === 'previewExpense') value = nativeStore.previewExpense(payload.draft, payload.id || null, { mode: payload.mode });
      else if (operation === 'previewRelease') value = nativeStore.previewRelease(payload.amount);
      else if (operation === 'previewRebalance') value = nativeStore.previewRebalance();
      else if (mutators.has(operation)) value = nativeStore[operation](...(payload.args || [])) ?? null;
      else throw new Error('Неизвестная команда');
      return JSON.stringify({ ok: true, value });
    } catch (error) {
      return JSON.stringify({ ok: false, error: String(error.message || error) });
    }
  }
};
