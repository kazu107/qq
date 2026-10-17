"use strict";

const fs = require("node:fs");
const path = require("node:path");
const { randomUUID } = require("node:crypto");
const { Pool } = require("pg");

function poolOptions(env) {
  const url = new URL(env.DATABASE_URL);
  if (!["postgres:", "postgresql:"].includes(url.protocol)) throw new Error("invalid_database_url");
  const local = ["localhost", "127.0.0.1", "[::1]"].includes(url.hostname) && env.NODE_ENV !== "production";
  // Do not let connection-string sslmode silently disable certificate verification.
  for (const key of [...url.searchParams.keys()]) {
    if (/^ssl|^uselibpqcompat$|^host$|^port$/i.test(key)) url.searchParams.delete(key);
  }
  let ca;
  if (env.AUTH_DATABASE_CA_BASE64) {
    ca = Buffer.from(env.AUTH_DATABASE_CA_BASE64, "base64").toString("utf8");
    if (!ca.includes("-----BEGIN CERTIFICATE-----")) throw new Error("invalid_database_ca");
  } else if (env.DYNO && fs.existsSync("/usr/lib/ssl/certs/ca-certificates.crt")) {
    ca = fs.readFileSync("/usr/lib/ssl/certs/ca-certificates.crt", "utf8");
  }
  return { connectionString: url.href, ssl: local ? false : { rejectUnauthorized: true, ...(ca ? { ca } : {}) },
    max: 4, idleTimeoutMillis: 10000, connectionTimeoutMillis: 5000, statement_timeout: 10000, allowExitOnIdle: true };
}

function publicUser(row) {
  return { id: row.id, username: row.username, createdAt: new Date(row.created_at).toISOString() };
}

class AccountStore {
  constructor(env) {
    this.pool = new Pool(poolOptions(env));
    this.pool.on("error", () => {});
    this.checkedAt = 0;
    this.closePromise = null;
    this.lastCleanup = 0;
  }

  async ready() {
    if (Date.now() - this.checkedAt < 30000) return;
    await this.pool.query("SELECT 1 FROM qq_accounts_users LIMIT 0");
    this.checkedAt = Date.now();
  }

  async migrate() {
    const client = await this.pool.connect();
    try {
      await client.query("BEGIN");
      await client.query("SELECT pg_advisory_xact_lock(813601442)");
      await client.query(fs.readFileSync(path.join(__dirname, "schema.sql"), "utf8"));
      await client.query("COMMIT");
    } catch (error) {
      await client.query("ROLLBACK");
      throw error;
    } finally { client.release(); }
  }

  async saveAttempt(attempt) {
    await this.pool.query(`INSERT INTO qq_accounts_oauth_attempts
      (state_hash, binding_hash, provider, verifier, nonce, language, expires_at) VALUES ($1,$2,$3,$4,$5,$6,$7)`,
    [attempt.stateHash, attempt.bindingHash, attempt.provider, attempt.verifier, attempt.nonce, attempt.language, attempt.expiresAt]);
  }

  async consumeAttempt(stateHash, bindingHash, provider) {
    const result = await this.pool.query(`DELETE FROM qq_accounts_oauth_attempts
      WHERE state_hash=$1 AND binding_hash=$2 AND provider=$3 AND expires_at>now() RETURNING *`, [stateHash, bindingHash, provider]);
    return result.rows[0] || null;
  }

  async getOrCreateUser(provider, subject) {
    const client = await this.pool.connect();
    try {
      await client.query("BEGIN");
      await client.query("SELECT pg_advisory_xact_lock(hashtextextended($1, 0))", [provider + ":" + subject]);
      let result = await client.query(`SELECT u.* FROM qq_accounts_users u JOIN qq_accounts_identities i ON i.user_id=u.id
        WHERE i.provider=$1 AND i.subject=$2`, [provider, subject]);
      if (!result.rowCount) {
        result = await client.query("INSERT INTO qq_accounts_users (id) VALUES ($1) RETURNING *", [randomUUID()]);
        await client.query("INSERT INTO qq_accounts_identities (provider,subject,user_id) VALUES ($1,$2,$3)", [provider, subject, result.rows[0].id]);
      }
      await client.query("COMMIT");
      return publicUser(result.rows[0]);
    } catch (error) {
      await client.query("ROLLBACK");
      throw error;
    } finally { client.release(); }
  }

  async createSession(tokenHash, userId, expiresAt) {
    await this.pool.query("INSERT INTO qq_accounts_sessions (token_hash,user_id,expires_at) VALUES ($1,$2,$3)", [tokenHash, userId, expiresAt]);
  }

  async getSession(tokenHash) {
    const result = await this.pool.query(`SELECT u.* FROM qq_accounts_sessions s JOIN qq_accounts_users u ON u.id=s.user_id
      WHERE s.token_hash=$1 AND s.expires_at>now()`, [tokenHash]);
    return result.rowCount ? publicUser(result.rows[0]) : null;
  }

  async deleteSession(tokenHash) {
    await this.pool.query("DELETE FROM qq_accounts_sessions WHERE token_hash=$1", [tokenHash]);
  }

  async setUsername(userId, username, key) {
    try {
      const result = await this.pool.query(`UPDATE qq_accounts_users SET username=$2, username_key=$3
        WHERE id=$1 AND username IS NULL RETURNING *`, [userId, username, key]);
      if (!result.rowCount) return { error: "username_already_set" };
      return { user: publicUser(result.rows[0]) };
    } catch (error) {
      if (error.code === "23505") return { error: "username_taken" };
      throw error;
    }
  }

  async cleanup() {
    if (Date.now() - this.lastCleanup < 3600000) return;
    this.lastCleanup = Date.now();
    await this.pool.query("DELETE FROM qq_accounts_oauth_attempts WHERE expires_at<=now()");
    await this.pool.query("DELETE FROM qq_accounts_sessions WHERE expires_at<=now()");
  }

  close() {
    if (!this.closePromise) this.closePromise = this.pool.end();
    return this.closePromise;
  }
}

module.exports = { AccountStore, poolOptions };
