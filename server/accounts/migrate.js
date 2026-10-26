"use strict";

const { AccountStore } = require("./store");
const { RankingStore } = require("../ranking/store");

async function main(env = process.env) {
  if (env.AUTH_ENABLED !== "true") {
    console.log("Account schema migration skipped: authentication is disabled.");
    return;
  }
  if (!env.DATABASE_URL) throw new Error("DATABASE_URL is required when AUTH_ENABLED=true");
  const store = new AccountStore(env);
  try {
    await store.migrate();
    console.log("ACCOUNT_SCHEMA_MIGRATION_OK: additive account, ranked-run, cloud-save and guest-transfer tables");
    const season = await new RankingStore(store.pool).ensureSeason();
    console.log(season ? "RANKED_SEASON_READY" : "RANKED_PREPARING", season?.id || "no season created");
  } finally { await store.close(); }
}

if (require.main === module) main().catch(error => {
  console.error("Account schema migration failed:", error.code || error.name);
  process.exitCode = 1;
});
module.exports = { main };
