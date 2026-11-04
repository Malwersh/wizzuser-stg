'use strict';
// One commercial-preview invocation only. Never share account or pricing reads
// across requests; the final order request performs its own fresh validation.
function createCheckoutPricingReads(db) {
  const pending = new Map();
  const stats = { requests: 0, hits: 0 };
  const canonical = v => Array.isArray(v) ? v.map(canonical) : v && typeof v === 'object'
    ? Object.fromEntries(Object.keys(v).sort().map(k => [k, canonical(v[k])])) : v;
  return {
    stats,
    db: { async send(command) {
      const kind = command.constructor.name.replace(/\d+$/, '');
      const input = command.input;
      if (kind !== 'GetCommand' || input.ConsistentRead !== true) return db.send(command);
      const key = JSON.stringify(canonical(input));
      if (pending.has(key)) { stats.hits++; return structuredClone(await pending.get(key)); }
      stats.requests++;
      if (pending.size >= 128) return db.send(command);
      const result = Promise.resolve().then(() => db.send(command));
      pending.set(key, result);
      try { return structuredClone(await result); }
      catch (error) { pending.delete(key); throw error; }
    } },
  };
}
module.exports = { createCheckoutPricingReads };
