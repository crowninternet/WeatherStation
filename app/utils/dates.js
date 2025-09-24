const dayjs = require('dayjs');
const utc = require('dayjs/plugin/utc');
const timezone = require('dayjs/plugin/timezone');

dayjs.extend(utc);
dayjs.extend(timezone);

/**
 * Convert UTC ISO string to local timezone
 */
function toLocalTime(utcISO, timezone = process.env.TIMEZONE || 'UTC') {
  return dayjs(utcISO).tz(timezone);
}

/**
 * Format date for display
 */
function formatDate(date, format = 'YYYY-MM-DD HH:mm:ss') {
  return dayjs(date).format(format);
}

/**
 * Parse date input (supports YYYY-MM-DD and ISO strings)
 */
function parseDate(dateStr) {
  if (!dateStr) return null;
  
  // If it's just a date (YYYY-MM-DD), treat as start of day in local timezone
  if (/^\d{4}-\d{2}-\d{2}$/.test(dateStr)) {
    return dayjs.tz(dateStr, process.env.TIMEZONE || 'UTC').startOf('day').utc();
  }
  
  return dayjs(dateStr).utc();
}

/**
 * Get date range for queries
 */
function getDateRange(from, to) {
  const fromDate = parseDate(from);
  const toDate = parseDate(to);
  
  return {
    from: fromDate ? fromDate.toISOString() : null,
    to: toDate ? toDate.toISOString() : null
  };
}

/**
 * Get default date range (last 30 days)
 */
function getDefaultDateRange() {
  const now = dayjs().utc();
  const thirtyDaysAgo = now.subtract(30, 'day');
  
  return {
    from: thirtyDaysAgo.toISOString(),
    to: now.toISOString()
  };
}

module.exports = {
  toLocalTime,
  formatDate,
  parseDate,
  getDateRange,
  getDefaultDateRange
};




