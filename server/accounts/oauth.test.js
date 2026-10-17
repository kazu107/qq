"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const { OAuthProviders, SERVERS } = require("./oauth");

const GITHUB_ISSUER = "https://github.com/login/oauth";

function githubFixture() {
  const calls = [];
  const oauth = new OAuthProviders({ GITHUB_CLIENT_ID: "test-client", GITHUB_CLIENT_SECRET: "test-only-secret" }, {
    async fetch(url, options) {
      calls.push(new URL(url).href);
      if (new URL(url).href === "https://github.com/login/oauth/access_token") {
        const body = new URLSearchParams(options.body);
        assert.equal(body.get("code"), "test-code");
        assert.equal(body.get("code_verifier"), "v".repeat(43));
        assert.equal(body.get("client_id"), "test-client");
        assert.equal(body.get("client_secret"), "test-only-secret");
        assert.equal(new Headers(options.headers).get("accept"), "application/json");
        return Response.json({ access_token: "test-only-access-token", scope: "", token_type: "bearer" });
      }
      assert.equal(new URL(url).href, "https://api.github.com/user");
      assert.equal(new Headers(options.headers).get("authorization"), "Bearer test-only-access-token");
      return Response.json({ id: 12345, login: "mutable-name" });
    },
  });
  const url = new URL("https://game.example/auth/github/callback?code=test-code&state=test-state");
  return { oauth, calls, url, attempt: { verifier: "v".repeat(43), nonce: "unused-for-github" } };
}

test("GitHub production metadata matches its RFC 9207 issuer including /login/oauth", () => {
  assert.equal(SERVERS.github.issuer, GITHUB_ISSUER);
});

test("GitHub accepts a real-shaped code/iss/state response and empty token scope without an ID token", async () => {
  const fixture = githubFixture();
  fixture.url.searchParams.set("iss", GITHUB_ISSUER);
  assert.equal(await fixture.oauth.identity("github", fixture.url, fixture.attempt), "12345");
  assert.equal(fixture.calls.length, 2);
});

test("GitHub rejects mismatched or duplicate issuers before sending credentials or exchanging a code", async () => {
  for (const values of [["https://attacker.invalid"], [GITHUB_ISSUER, GITHUB_ISSUER], ["https://github.com"]]) {
    const fixture = githubFixture();
    for (const value of values) fixture.url.searchParams.append("iss", value);
    await assert.rejects(fixture.oauth.identity("github", fixture.url, fixture.attempt));
    assert.deepEqual(fixture.calls, []);
  }
});

test("GitHub legacy code/state responses without iss remain compatible", async () => {
  const fixture = githubFixture();
  assert.equal(await fixture.oauth.identity("github", fixture.url, fixture.attempt), "12345");
});
