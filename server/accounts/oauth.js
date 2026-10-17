"use strict";

const oidc = require("openid-client");

const SERVERS = Object.freeze({
  google: { issuer: "https://accounts.google.com", authorization_endpoint: "https://accounts.google.com/o/oauth2/v2/auth",
    token_endpoint: "https://oauth2.googleapis.com/token", jwks_uri: "https://www.googleapis.com/oauth2/v3/certs",
    id_token_signing_alg_values_supported: ["RS256"], code_challenge_methods_supported: ["S256"] },
  github: { issuer: "https://github.com", authorization_endpoint: "https://github.com/login/oauth/authorize",
    token_endpoint: "https://github.com/login/oauth/access_token", code_challenge_methods_supported: ["S256"] },
});

class OAuthProviders {
  constructor(env, testing = {}) {
    this.configs = new Map();
    this.fetch = testing.fetch || fetch;
    this.userEndpoint = testing.githubUserEndpoint || "https://api.github.com/user";
    for (const provider of ["google", "github"]) {
      const prefix = provider.toUpperCase();
      if (!env[`${prefix}_CLIENT_ID`] || !env[`${prefix}_CLIENT_SECRET`]) continue;
      const config = new oidc.Configuration(testing.servers?.[provider] || SERVERS[provider], env[`${prefix}_CLIENT_ID`], env[`${prefix}_CLIENT_SECRET`]);
      config.timeout = 10;
      if (testing.fetch) config[oidc.customFetch] = testing.fetch;
      if (testing.allowInsecure) oidc.allowInsecureRequests(config);
      if (provider === "google") oidc.enableNonRepudiationChecks(config);
      this.configs.set(provider, config);
    }
  }

  enabled(provider) { return this.configs.has(provider); }

  async authorizationUrl(provider, { state, verifier, nonce, redirectUri }) {
    const parameters = { state, redirect_uri: redirectUri, code_challenge: await oidc.calculatePKCECodeChallenge(verifier), code_challenge_method: "S256" };
    if (provider === "google") Object.assign(parameters, { scope: "openid", nonce, prompt: "select_account" });
    else Object.assign(parameters, { scope: "", prompt: "select_account" });
    return oidc.buildAuthorizationUrl(this.configs.get(provider), parameters).href;
  }

  async identity(provider, currentUrl, attempt) {
    const checks = { pkceCodeVerifier: attempt.verifier, expectedState: currentUrl.searchParams.get("state") };
    if (provider === "google") Object.assign(checks, { expectedNonce: attempt.nonce, idTokenExpected: true });
    const tokens = await oidc.authorizationCodeGrant(this.configs.get(provider), currentUrl, checks);
    if (provider === "google") {
      const sub = tokens.claims()?.sub;
      if (typeof sub !== "string" || !sub || sub.length > 255) throw new Error("invalid_subject");
      return sub;
    }
    const response = await this.fetch(this.userEndpoint, { redirect: "error", signal: AbortSignal.timeout(10000),
      headers: { Authorization: `Bearer ${tokens.access_token}`, Accept: "application/vnd.github+json", "User-Agent": "QueueQuest", "X-GitHub-Api-Version": "2022-11-28" } });
    if (!response.ok) throw new Error("github_identity_failed");
    const text = await response.text();
    if (text.length > 65536) throw new Error("invalid_identity_response");
    const user = JSON.parse(text);
    if (!Number.isSafeInteger(user.id) || user.id <= 0) throw new Error("invalid_subject");
    return String(user.id);
  }
}

module.exports = { OAuthProviders, SERVERS };
