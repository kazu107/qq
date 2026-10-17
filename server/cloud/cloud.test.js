"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const { randomUUID } = require("node:crypto");
const { validatePayload } = require("./store");
const { accountFixture, BrowserSession, testDatabaseEnv } = require("../../tests/helpers/account_fixture");
const save = points => ({ schema_version: 1, current_run: {}, suspended_runs: {}, meta_progress: { points }, settings: { screen_hint: "hub" } });
test("cloud payload rejects device permissions, foreign Ranked ownership and malformed structures", () => {
  assert.doesNotThrow(() => validatePayload(save(10), "owner"));
  assert.throws(() => validatePayload({ ...save(10), settings: { developer_mode: true } }, "owner"));
  assert.throws(() => validatePayload({ ...save(10), current_run: { ranking: { ticket: { user_id: "another" } } } }, "owner"));
  assert.throws(() => validatePayload({ ...save(10), meta_progress: [] }, "owner"));
  assert.throws(() => validatePayload({ ...save(10), unexpected: true }, "owner"));
});
test("cloud owner isolation, CSRF, concurrent devices, retries, revisions, restoration and retention", { skip: !testDatabaseEnv() }, async () => {
  const fixture = await accountFixture();
  try {
    const guest = new BrowserSession(fixture.origin), a = new BrowserSession(fixture.origin), b = new BrowserSession(fixture.origin);
    await a.login(); await a.write("/api/account/username", { username: "CloudA" });
    fixture.mock.state.googleSubject = "cloud-user-b";
    await b.login(); await b.write("/api/account/username", { username: "CloudB" });
    const owner = (await a.profile()).user.id, other = (await b.profile()).user.id;
    const writer = randomUUID(), secondWriter = randomUUID();
    async function request(browser, method, path, body, account = owner, origin = fixture.origin) {
      const profile = await browser.profile();
      return browser.request("/api/cloud/" + path, { method, headers: { "X-QQ-Account": account, "X-QQ-Writer": writer, Origin: origin, "Content-Type": "application/json", "X-CSRF-Token": profile.csrfToken || "" }, ...(body ? { body: JSON.stringify(body) } : {}) });
    }
    assert.equal((await request(guest, "GET", "save")).status, 401);
    assert.equal((await request(b, "GET", "save", null, owner)).status, 409);
    assert.equal((await request(a, "POST", "claim", { writer_id: writer }, owner, "https://evil.invalid")).status, 403);
    assert.equal((await request(a, "POST", "claim", { writer_id: writer })).status, 200);
    const body = { writer_id: writer, base_revision: 0, request_id: randomUUID(), payload: save(50) };
    const first = await (await request(a, "PUT", "save", body)).json(); assert.equal(first.revision, 1);
    const retry = await (await request(a, "PUT", "save", body)).json(); assert.equal(retry.revision, 1);
    assert.equal((await request(a, "PUT", "save", { ...body, request_id: randomUUID() })).status, 409);
    assert.equal((await request(a, "POST", "claim", { writer_id: secondWriter })).status, 409);
    assert.equal((await request(a, "POST", "claim", { writer_id: secondWriter, takeover: true })).status, 200);
    assert.equal((await request(a, "PUT", "save", { ...body, base_revision: 1, request_id: randomUUID() })).status, 409);
    for (let index = 1; index <= 7; index++) {
      const response = await request(a, "PUT", "save", { writer_id: secondWriter, base_revision: index, request_id: randomUUID(), payload: save(50 + index) });
      assert.equal(response.status, 200);
    }
    const history = await (await request(a, "GET", "history")).json(); assert.equal(history.history.length, 5);
    const restored = await (await request(a, "POST", "restore", { writer_id: secondWriter, base_revision: 8, request_id: randomUUID(), revision: 4 })).json();
    assert.equal(restored.revision, 9); assert.equal(restored.payload.meta_progress.points, 53);
    const read = await (await request(a, "GET", "save")).json(); assert.equal(read.payload.meta_progress.points, 53);
    assert.equal((await (await request(b, "GET", "save", null, other)).json()).payload, null);
    assert.equal((await request(b, "POST", "restore", { writer_id: secondWriter, base_revision: 0, request_id: randomUUID(), revision: 4 }, other)).status, 409);
    await request(a, "POST", "release", { writer_id: secondWriter });
    assert.equal((await request(a, "PUT", "save", { ...body, base_revision: 9, writer_id: secondWriter, request_id: randomUUID() })).status, 409);
    assert.equal((await request(a, "POST", "claim", { writer_id: writer })).status, 200);
    await a.write("/api/account/logout"); assert.equal((await request(a, "GET", "save")).status, 401);
  } finally { await fixture.close(); }
});
