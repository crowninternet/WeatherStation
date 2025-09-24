/**
 * Convert array of objects to CSV string
 */
function arrayToCSV(data, headers = null) {
  if (!data || data.length === 0) {
    return '';
  }
  
  // If headers not provided, use object keys from first item
  const csvHeaders = headers || Object.keys(data[0]);
  
  // Escape CSV values
  function escapeCSV(value) {
    if (value === null || value === undefined) {
      return '';
    }
    
    const str = String(value);
    
    // If value contains comma, quote, or newline, wrap in quotes and escape quotes
    if (str.includes(',') || str.includes('"') || str.includes('\n')) {
      return `"${str.replace(/"/g, '""')}"`;
    }
    
    return str;
  }
  
  // Build CSV rows
  const rows = [];
  
  // Header row
  rows.push(csvHeaders.map(escapeCSV).join(','));
  
  // Data rows
  data.forEach(item => {
    const row = csvHeaders.map(header => escapeCSV(item[header]));
    rows.push(row.join(','));
  });
  
  return rows.join('\n');
}

/**
 * Generate CSV filename with timestamp
 */
function generateCSVFilename(prefix = 'export') {
  const now = new Date();
  const timestamp = now.toISOString().replace(/[:.]/g, '-').split('T')[0];
  return `${prefix}_${timestamp}.csv`;
}

module.exports = {
  arrayToCSV,
  generateCSVFilename
};




