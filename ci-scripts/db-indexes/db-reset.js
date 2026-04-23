#!/usr/bin/env node

const { Client } = require('pg');
const { getClientConfig, usageLines } = require('./pg-config');

const pgConfig = getClientConfig();

if (!pgConfig) {
  usageLines('db-reset.js').forEach((line) => console.error(line));
  process.exit(1);
}

async function resetStats() {
  const client = new Client(pgConfig);

  try {
    await client.connect();
    console.log('Connected to database...');

    await client.query('SELECT pg_stat_statements_reset()');
    console.log('✅ pg_stat_statements reset successfully.');

    await client.end();
  } catch (err) {
    console.error('❌ Error:', err.message);
    console.error('\nMake sure pg_stat_statements extension is enabled:');
    console.error('  CREATE EXTENSION IF NOT EXISTS pg_stat_statements;');
    process.exit(1);
  }
}

resetStats();
