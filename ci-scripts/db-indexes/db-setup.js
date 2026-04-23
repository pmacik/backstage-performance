#!/usr/bin/env node

const { Client } = require('pg');
const { getClientConfig, usageLines } = require('./pg-config');

const pgConfig = getClientConfig();

if (!pgConfig) {
  usageLines('db-setup.js').forEach((line) => console.error(line));
  process.exit(1);
}

async function setup() {
  const client = new Client(pgConfig);

  try {
    await client.connect();
    console.log('Connected to database...');

    // Enable pg_stat_statements extension
    await client.query('CREATE EXTENSION IF NOT EXISTS pg_stat_statements');
    console.log('✅ pg_stat_statements extension enabled.');

    // Reset stats
    await client.query('SELECT pg_stat_statements_reset()');
    console.log('✅ Statistics reset.');

    await client.end();
  } catch (err) {
    console.error('❌ Error:', err.message);
    console.error('\nNote: You may need superuser privileges to create extensions.');
    console.error('Ask your DBA or run: CREATE EXTENSION IF NOT EXISTS pg_stat_statements;');
    process.exit(1);
  }
}

setup();
