#!/usr/bin/env node

const { Client } = require('pg');
const { getClientConfig, usageLines } = require('./pg-config');

const pgConfig = getClientConfig();

if (!pgConfig) {
  usageLines('db-recreate-indexes.js').forEach((line) => console.error(line));
  process.exit(1);
}

async function recreateIndexes() {
  const client = new Client(pgConfig);

  try {
    await client.connect();
    console.log('\n============================================================================');
    console.log('DATABASE CONNECTION & VERIFICATION');
    console.log('============================================================================\n');

    // Get database name
    const dbResult = await client.query('SELECT current_database()');
    console.log(`✓ Connected to database: ${dbResult.rows[0].current_database}\n`);

    // List all tables in public schema
    console.log('Checking for existing tables...');
    const tablesResult = await client.query(`
      SELECT tablename
      FROM pg_tables
      WHERE schemaname = 'public'
      ORDER BY tablename
    `);

    console.log('Tables found:');
    tablesResult.rows.forEach(row => {
      console.log(`  - ${row.tablename}`);
    });
    console.log('');

    // Verify required tables exist
    const tableNames = tablesResult.rows.map(r => r.tablename);
    const requiredTables = ['search', 'final_entities'];
    const missingTables = requiredTables.filter(t => !tableNames.includes(t));

    if (missingTables.length > 0) {
      console.error(`❌ Error: Required tables missing: ${missingTables.join(', ')}`);
      console.error('\nPlease ensure the following tables exist before creating indexes:');
      missingTables.forEach(table => console.error(`  - ${table}`));
      process.exit(1);
    }

    console.log('✓ All required tables exist (search, final_entities)\n');

    console.log('============================================================================');
    console.log('RECREATING PERFORMANCE INDEXES');
    console.log('============================================================================\n');

    // Create idx_search_facets
    console.log('Creating idx_search_facets...');
    console.log('Purpose: Covering index for facet aggregation queries');
    console.log('Expected time: ~45 seconds\n');
    const start1 = Date.now();
    await client.query(`
      CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_search_facets
        ON search(key, original_value, entity_id)
        WHERE original_value IS NOT NULL
    `);
    console.log(`✓ idx_search_facets created (${Math.round((Date.now() - start1) / 1000)}s)\n`);

    // Create idx_search_key_value_entity_id
    console.log('Creating idx_search_key_value_entity_id...');
    console.log('Purpose: Composite index for entity filtering with CTEs');
    console.log('Expected time: ~60 seconds\n');
    const start2 = Date.now();
    await client.query(`
      CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_search_key_value_entity_id
        ON search(key, value, entity_id)
    `);
    console.log(`✓ idx_search_key_value_entity_id created (${Math.round((Date.now() - start2) / 1000)}s)\n`);

    // Create idx_final_entities_entity_id_filtered
    console.log('Creating idx_final_entities_entity_id_filtered...');
    console.log('Purpose: Partial index for JOIN optimization');
    console.log('Expected time: ~2 seconds\n');
    const start3 = Date.now();
    await client.query(`
      CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_final_entities_entity_id_filtered
        ON final_entities(entity_id)
        WHERE final_entity IS NOT NULL
    `);
    console.log(`✓ idx_final_entities_entity_id_filtered created (${Math.round((Date.now() - start3) / 1000)}s)\n`);

    // Update statistics
    console.log('Running VACUUM ANALYZE to update statistics...');
    const start4 = Date.now();
    await client.query('VACUUM ANALYZE search');
    await client.query('VACUUM ANALYZE final_entities');
    console.log(`✓ Statistics updated (${Date.now() - start4}ms)\n`);

    // Verify indexes
    // console.log('============================================================================');
    // console.log('VERIFICATION');
    // console.log('============================================================================\n');

    // const result = await client.query(`
    //   SELECT
    //     tablename,
    //     indexname,
    //     pg_size_pretty(pg_relation_size(indexrelid)) AS index_size
    //   FROM pg_stat_user_indexes
    //   WHERE indexname IN (
    //     'idx_search_facets',
    //     'idx_search_key_value_entity_id',
    //     'idx_final_entities_entity_id_filtered'
    //   )
    //   ORDER BY tablename, indexname
    // `);

    // console.log('Indexes created:');
    // result.rows.forEach(row => {
    //   console.log(`  ${row.tablename}.${row.indexname} - ${row.index_size}`);
    // });

    console.log('\n============================================================================');
    console.log('RECREATION COMPLETE');
    console.log('============================================================================\n');
    console.log('Successfully recreated 3 performance optimization indexes.\n');

    await client.end();
  } catch (err) {
    console.error('❌ Error:', err.message);
    console.error('\nFull error:', err);
    process.exit(1);
  }
}

recreateIndexes();
