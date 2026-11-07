// The month calendar under the clocks (SPEC.md §8.2), ported from tide's
// shell/lib/popover.mjs. Months are 0-based, as in Date.

const DAY = 86400000;
const MONTHS = ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"];

// The ISO 8601 week number of a date: weeks start on Monday, and week 1
// holds the year's first Thursday.
export function isoWeek(year, month, date) {
  const d = new Date(Date.UTC(year, month, date));
  // The Thursday of this week decides its year.
  const thursday = d.getTime() + (3 - ((d.getUTCDay() + 6) % 7)) * DAY;
  const yearStart = Date.UTC(new Date(thursday).getUTCFullYear(), 0, 1);
  return Math.floor((thursday - yearStart) / (7 * DAY)) + 1;
}

// "September 2026".
export function monthTitle(year, month) {
  return `${MONTHS[month]} ${year}`;
}

// The month after (`step` 1) or before (-1): {year, month}.
export function stepMonth(year, month, step) {
  const m = year * 12 + month + step;
  return { year: Math.floor(m / 12), month: ((m % 12) + 12) % 12 };
}

// The shown month as weeks from Monday: [{week, days: [{date, outside,
// today}]}]. `today` is {year, month, date}, or null; days from the months
// either side are `outside`.
export function monthGrid(year, month, today) {
  const first = Date.UTC(year, month, 1);
  const back = (new Date(first).getUTCDay() + 6) % 7;
  const weeks = [];
  let ms = first - back * DAY;
  do {
    const days = [];
    for (let i = 0; i < 7; i++, ms += DAY) {
      const d = new Date(ms);
      const y = d.getUTCFullYear();
      const m = d.getUTCMonth();
      const date = d.getUTCDate();
      days.push({ date, outside: m !== month, today: !!today && today.year === y && today.month === m && today.date === date });
    }
    const monday = new Date(ms - 7 * DAY);
    weeks.push({ week: isoWeek(monday.getUTCFullYear(), monday.getUTCMonth(), monday.getUTCDate()), days });
  } while (new Date(ms).getUTCMonth() === month);
  return weeks;
}
