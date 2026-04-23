'use strict';

/**
 * Resolve node-postgres Client config from DB_URL or discrete env vars.
 * Use POSTGRES_* vars when passwords contain URL-reserved characters (/ : @ etc.).
 */
function getClientConfig(argv = process.argv) {
  const dbUrl = process.env.DB_URL || argv[2];
  if (dbUrl) {
    return { connectionString: dbUrl };
  }

  const user = process.env.POSTGRES_USER;
  const password = process.env.POSTGRES_PASSWORD;
  const database =
    process.env.POSTGRES_DATABASE_NAME ||
    process.env.POSTGRES_DATABASE ||
    process.env.PGDATABASE;

  if (user != null && user !== '' && password != null && database != null && database !== '') {
    return {
      user,
      password,
      host: process.env.POSTGRES_HOST || process.env.PGHOST || 'localhost',
      port: parseInt(process.env.POSTGRES_PORT || process.env.PGPORT || '5432', 10),
      database,
    };
  }

  return null;
}

function usageLines(scriptName) {
  return [
    `Usage: node ${scriptName} <postgres_connection_string>`,
    `   or: DB_URL=postgres://... node ${scriptName}`,
    `   or: POSTGRES_USER=... POSTGRES_PASSWORD=... POSTGRES_DATABASE_NAME=... \\`,
    `       [POSTGRES_HOST=localhost] [POSTGRES_PORT=5432] node ${scriptName}`,
  ];
}

module.exports = { getClientConfig, usageLines };
