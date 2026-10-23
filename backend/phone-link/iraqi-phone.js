'use strict';

// Iraq mobile numbers only. Canonical storage is E.164 (+9647XXXXXXXXX).
function normalizeIraqiPhone(input) {
  if (typeof input !== 'string') throw new TypeError('Phone must be a string');
  const digits = input.trim().replace(/[٠-٩۰-۹]/g, c => {
    const n = c.charCodeAt(0);
    return String(n >= 0x6f0 ? n - 0x6f0 : n - 0x660);
  }).replace(/[\s()\-]/g, '');
  let national;
  if (/^\+9647[0-9]{9}$/.test(digits)) national = digits.slice(4);
  else if (/^009647[0-9]{9}$/.test(digits)) national = digits.slice(5);
  else if (/^9647[0-9]{9}$/.test(digits)) national = digits.slice(3);
  else if (/^07[0-9]{9}$/.test(digits)) national = digits.slice(1);
  else if (/^7[0-9]{9}$/.test(digits)) national = digits;
  else throw new Error('Only Iraqi mobile numbers (+964) are supported');
  return '+964' + national;
}
module.exports = { normalizeIraqiPhone };
