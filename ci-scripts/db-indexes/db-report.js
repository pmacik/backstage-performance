#!/usr/bin/env node

const { Client } = require('pg');
const fs = require('fs');
const { getClientConfig, usageLines } = require('./pg-config');

const pgConfig = getClientConfig();

if (!pgConfig) {
  usageLines('db-report.js').forEach((line) => console.error(line));
  process.exit(1);
}

async function fetchDBStats() {
  const client = new Client(pgConfig);

  try {
    await client.connect();
    console.log('Connected to database...');

    // Query stats per tempo medio
    const slowestByAvg = await client.query(`
      SELECT
        calls,
        round(mean_exec_time::numeric, 2) as avg_ms,
        round(max_exec_time::numeric, 2) as max_ms,
        round(min_exec_time::numeric, 2) as min_ms,
        round(total_exec_time::numeric, 2) as total_ms,
        round(stddev_exec_time::numeric, 2) as stddev_ms,
        query
      FROM pg_stat_statements
      WHERE query NOT LIKE '%pg_stat%'
        AND query NOT LIKE 'COMMIT%'
        AND query NOT LIKE 'BEGIN%'
      ORDER BY mean_exec_time DESC
      LIMIT 20
    `);

    // Query stats per tempo totale (più chiamate)
    const slowestByTotal = await client.query(`
      SELECT
        calls,
        round(mean_exec_time::numeric, 2) as avg_ms,
        round(max_exec_time::numeric, 2) as max_ms,
        round(total_exec_time::numeric, 2) as total_ms,
        query
      FROM pg_stat_statements
      WHERE query NOT LIKE '%pg_stat%'
        AND query NOT LIKE 'COMMIT%'
        AND query NOT LIKE 'BEGIN%'
      ORDER BY total_exec_time DESC
      LIMIT 20
    `);

    // Query più chiamate
    const mostCalled = await client.query(`
      SELECT
        calls,
        round(mean_exec_time::numeric, 2) as avg_ms,
        round(total_exec_time::numeric, 2) as total_ms,
        query
      FROM pg_stat_statements
      WHERE query NOT LIKE '%pg_stat%'
        AND query NOT LIKE 'COMMIT%'
        AND query NOT LIKE 'BEGIN%'
      ORDER BY calls DESC
      LIMIT 20
    `);

    await client.end();
    console.log('Database stats collected.');

    return {
      slowestByAvg: slowestByAvg.rows,
      slowestByTotal: slowestByTotal.rows,
      mostCalled: mostCalled.rows
    };

  } catch (err) {
    console.error('Database error:', err.message);
    process.exit(1);
  }
}

function generateHTML(stats) {
  const timestamp = new Date().toISOString();

  return `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>PostgreSQL Query Performance Report</title>
  <script src="https://cdn.tailwindcss.com"></script>
  <style>
    .query-text {
      font-family: 'Monaco', 'Menlo', monospace;
      font-size: 11px;
      white-space: pre-wrap;
      word-break: break-all;
      max-height: 100px;
      overflow-y: auto;
    }
    .tooltip {
      position: relative;
      cursor: help;
      border-bottom: 1px dotted #999;
    }
    .tooltip .tooltiptext {
      visibility: hidden;
      width: 280px;
      background-color: #1f2937;
      color: #fff;
      text-align: left;
      border-radius: 6px;
      padding: 8px 12px;
      position: absolute;
      z-index: 1;
      bottom: 125%;
      left: 50%;
      margin-left: -140px;
      opacity: 0;
      transition: opacity 0.3s;
      font-size: 12px;
      line-height: 1.4;
    }
    .tooltip .tooltiptext::after {
      content: "";
      position: absolute;
      top: 100%;
      left: 50%;
      margin-left: -5px;
      border-width: 5px;
      border-style: solid;
      border-color: #1f2937 transparent transparent transparent;
    }
    .tooltip:hover .tooltiptext {
      visibility: visible;
      opacity: 1;
    }
  </style>
</head>
<body class="bg-gray-50 p-4">
  <div class="max-w-7xl mx-auto">
    <!-- Header -->
    <div class="bg-gradient-to-r from-green-600 to-teal-600 text-white p-4 rounded-lg mb-4">
      <h1 class="text-2xl font-bold">PostgreSQL Query Performance Report</h1>
      <p class="text-sm opacity-90 mt-1">Generated: ${timestamp}</p>
    </div>

    <!-- Summary Stats -->
    <div class="grid grid-cols-3 gap-3 mb-4">
      <div class="bg-white p-4 rounded-lg shadow-sm">
        <h2 class="text-sm font-semibold text-gray-600 mb-1">SLOWEST QUERIES</h2>
        <p class="text-2xl font-bold text-red-600">${stats.slowestByAvg.length}</p>
        <p class="text-xs text-gray-500 mt-1">By average execution time</p>
      </div>
      <div class="bg-white p-4 rounded-lg shadow-sm">
        <h2 class="text-sm font-semibold text-gray-600 mb-1">TOTAL TIME HOGS</h2>
        <p class="text-2xl font-bold text-orange-600">${stats.slowestByTotal.length}</p>
        <p class="text-xs text-gray-500 mt-1">By cumulative time spent</p>
      </div>
      <div class="bg-white p-4 rounded-lg shadow-sm">
        <h2 class="text-sm font-semibold text-gray-600 mb-1">MOST CALLED</h2>
        <p class="text-2xl font-bold text-blue-600">${stats.mostCalled.length}</p>
        <p class="text-xs text-gray-500 mt-1">By number of executions</p>
      </div>
    </div>

    <!-- Slowest by Average -->
    <div class="bg-white p-4 rounded-lg shadow-sm mb-4">
      <h2 class="text-lg font-semibold text-gray-700 mb-3">Top 20 Slowest Queries (by avg time)</h2>
      <div class="overflow-x-auto">
        <table class="w-full text-sm">
          <thead>
            <tr class="border-b border-gray-200">
              <th class="text-left py-2 px-2 font-semibold text-gray-700">
                <span class="tooltip">Calls
                  <span class="tooltiptext">Number of times this query was executed</span>
                </span>
              </th>
              <th class="text-right py-2 px-2 font-semibold text-gray-700">
                <span class="tooltip">Avg (ms)
                  <span class="tooltiptext">Average execution time - main bottleneck indicator</span>
                </span>
              </th>
              <th class="text-right py-2 px-2 font-semibold text-gray-700">
                <span class="tooltip">Min (ms)
                  <span class="tooltiptext">Fastest execution time</span>
                </span>
              </th>
              <th class="text-right py-2 px-2 font-semibold text-gray-700">
                <span class="tooltip">Max (ms)
                  <span class="tooltiptext">Slowest execution time</span>
                </span>
              </th>
              <th class="text-right py-2 px-2 font-semibold text-gray-700">
                <span class="tooltip">Total (ms)
                  <span class="tooltiptext">Total time spent on this query</span>
                </span>
              </th>
              <th class="text-right py-2 px-2 font-semibold text-gray-700">
                <span class="tooltip">StdDev
                  <span class="tooltiptext">Standard deviation - high = inconsistent performance</span>
                </span>
              </th>
              <th class="text-left py-2 px-2 font-semibold text-gray-700">Query</th>
            </tr>
          </thead>
          <tbody>
            ${stats.slowestByAvg.map(row => `
              <tr class="border-b border-gray-100 hover:bg-gray-50">
                <td class="py-2 px-2 font-mono">${row.calls}</td>
                <td class="py-2 px-2 text-right font-mono font-semibold ${row.avg_ms > 1000 ? 'text-red-600' : row.avg_ms > 500 ? 'text-orange-600' : 'text-green-600'}">${row.avg_ms}</td>
                <td class="py-2 px-2 text-right font-mono text-gray-600">${row.min_ms}</td>
                <td class="py-2 px-2 text-right font-mono text-red-600">${row.max_ms}</td>
                <td class="py-2 px-2 text-right font-mono">${row.total_ms}</td>
                <td class="py-2 px-2 text-right font-mono text-gray-600">${row.stddev_ms || 'N/A'}</td>
                <td class="py-2 px-2 query-text">${escapeHtml(row.query)}</td>
              </tr>
            `).join('')}
          </tbody>
        </table>
      </div>
    </div>

    <!-- Slowest by Total Time -->
    <div class="bg-white p-4 rounded-lg shadow-sm mb-4">
      <h2 class="text-lg font-semibold text-gray-700 mb-3">Top 20 Queries by Total Time (time hogs)</h2>
      <div class="overflow-x-auto">
        <table class="w-full text-sm">
          <thead>
            <tr class="border-b border-gray-200">
              <th class="text-left py-2 px-2 font-semibold text-gray-700">Calls</th>
              <th class="text-right py-2 px-2 font-semibold text-gray-700">Avg (ms)</th>
              <th class="text-right py-2 px-2 font-semibold text-gray-700">Max (ms)</th>
              <th class="text-right py-2 px-2 font-semibold text-gray-700">Total (ms)</th>
              <th class="text-left py-2 px-2 font-semibold text-gray-700">Query</th>
            </tr>
          </thead>
          <tbody>
            ${stats.slowestByTotal.map(row => `
              <tr class="border-b border-gray-100 hover:bg-gray-50">
                <td class="py-2 px-2 font-mono">${row.calls}</td>
                <td class="py-2 px-2 text-right font-mono">${row.avg_ms}</td>
                <td class="py-2 px-2 text-right font-mono text-red-600">${row.max_ms}</td>
                <td class="py-2 px-2 text-right font-mono font-semibold text-orange-600">${row.total_ms}</td>
                <td class="py-2 px-2 query-text">${escapeHtml(row.query)}</td>
              </tr>
            `).join('')}
          </tbody>
        </table>
      </div>
    </div>

    <!-- Most Called -->
    <div class="bg-white p-4 rounded-lg shadow-sm mb-4">
      <h2 class="text-lg font-semibold text-gray-700 mb-3">Top 20 Most Called Queries</h2>
      <div class="overflow-x-auto">
        <table class="w-full text-sm">
          <thead>
            <tr class="border-b border-gray-200">
              <th class="text-left py-2 px-2 font-semibold text-gray-700">Calls</th>
              <th class="text-right py-2 px-2 font-semibold text-gray-700">Avg (ms)</th>
              <th class="text-right py-2 px-2 font-semibold text-gray-700">Total (ms)</th>
              <th class="text-left py-2 px-2 font-semibold text-gray-700">Query</th>
            </tr>
          </thead>
          <tbody>
            ${stats.mostCalled.map(row => `
              <tr class="border-b border-gray-100 hover:bg-gray-50">
                <td class="py-2 px-2 font-mono font-semibold text-blue-600">${row.calls}</td>
                <td class="py-2 px-2 text-right font-mono">${row.avg_ms}</td>
                <td class="py-2 px-2 text-right font-mono">${row.total_ms}</td>
                <td class="py-2 px-2 query-text">${escapeHtml(row.query)}</td>
              </tr>
            `).join('')}
          </tbody>
        </table>
      </div>
    </div>

  </div>
</body>
</html>`;
}

function escapeHtml(text) {
  return text
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#039;');
}

async function main() {
  console.log('Fetching database query statistics...');
  const stats = await fetchDBStats();

  const html = generateHTML(stats);
  const timestamp = new Date().toISOString().replace(/[:.]/g, '-').slice(0, -5);
  var filename;
  if (process.env.REPORT_FILE) {
    filename = process.env.REPORT_FILE;
  } else {
    filename = `db-queries-${timestamp}.html`;
  }

  fs.writeFileSync(filename, html);
  console.log(`\n✅ Report generated: ${filename}`);
  console.log(`   Open it in your browser to view query performance.`);
}

main().catch(err => {
  console.error('Error:', err);
  process.exit(1);
});
