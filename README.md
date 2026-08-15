# Instagram Comment Automation (n8n + Meta Graph API)

An n8n workflow that listens for new comments on your Instagram professional
account's posts and Reels, sends a keyword-driven **private reply (DM)** to
the commenter, and — only if that DM actually succeeded — publishes a
**public reply** under the comment.

Two workflows are provided:

| File | Purpose |
|---|---|
| [`workflows/instagram-comment-automation.json`](workflows/instagram-comment-automation.json) | Main workflow: webhook, dedup, keyword matching, private reply, public reply, retries. |
| [`workflows/retry-failed-public-replies.json`](workflows/retry-failed-public-replies.json) | Companion workflow. Retries **only** the public reply for comments where the DM already succeeded but the public reply didn't — it never re-sends the DM. |

Target n8n version: **self-hosted n8n 1.70 or later** (Docker or npm). No
community nodes are used — only core nodes (`Webhook`, `Respond to Webhook`,
`HTTP Request`, `Code`, `IF`, `Postgres`, `Wait`, `NoOp`, `Schedule Trigger`,
`Manual Trigger`).

Graph API version used throughout: **v23.0**. Meta ships a new version
roughly every 6 months and deprecates old ones after ~2 years — check
https://developers.facebook.com/docs/graph-api/changelog before you go live
and bump the `v23.0` segment in the two `HTTP Request` node URLs if needed.

---

## 1. Prerequisites

- A Meta App in [developers.facebook.com](https://developers.facebook.com/apps/) with the **Instagram** product added.
- An Instagram **professional account** (Business or Creator) connected to a **Facebook Page** (this workflow uses the classic "Instagram API with Facebook Login" flow — `graph.facebook.com`, Page Access Token).
- A **Postgres** database reachable from your n8n instance (for the dedup / status table).
- n8n self-hosted, 1.70+, with the ability to set environment variables (`.env` file, Docker `-e` flags, or your process manager's env config). **n8n Cloud does not allow custom environment variables** — if you're on Cloud, replace every `{{$env.XXX}}` expression with an n8n `Set`/credential-based equivalent instead.

---

## 2. Environment variables

| Variable | Used for |
|---|---|
| `INSTAGRAM_ACCESS_TOKEN` | Page/long-lived access token used as `Authorization: Bearer ...` on every Graph API call. |
| `INSTAGRAM_USER_ID` | Your own Instagram-scoped user ID (IGSID). Used both to filter out your own comments and as the `{ig-user-id}` path segment when sending private replies. |
| `INSTAGRAM_VERIFY_TOKEN` | Arbitrary string you also enter in the Meta App Dashboard's webhook subscription form. Used to validate the `GET` verification handshake. |

No secret is ever hardcoded in the JSON files — every credential is read from `$env` at runtime, exactly as required.

---

## 3. Credentials to create in n8n

| Credential type | Used by | Notes |
|---|---|---|
| **Postgres** | Every node named `Reserve Comment (Atomic)`, `Update Row - *`, `Save Success`, `Find Failed Public Replies` | Not pre-filled in the exported JSON (credentials cannot be exported portably) — after importing, open each Postgres node and assign your credential once; n8n will remember it per node. |

The Meta access token is **not** an n8n credential in this design — it is read from `$env.INSTAGRAM_ACCESS_TOKEN` directly inside the `HTTP Request` nodes' header, as requested. If you prefer to manage it as a proper n8n credential instead, replace the `Authorization` header value with an n8n **HTTP Header Auth** or **HTTP Bearer Auth** credential on the four `HTTP Request` nodes (`Send Private Reply`, `Reply to Comment`, and their retry-workflow counterpart).

---

## 4. Meta Developers setup

1. Create/select an App at [developers.facebook.com/apps](https://developers.facebook.com/apps/), type "Business".
2. Add the **Instagram** product.
3. Under **Instagram → API setup with Facebook Login**, connect the Facebook Page that manages your Instagram professional account, and generate a Page access token (exchange it for a long-lived token — Meta's long-lived tokens last ~60 days and must be refreshed before expiry; automating that refresh is outside this workflow's scope).
4. Note your Instagram-scoped user ID (shown in the same setup screen) → this is `INSTAGRAM_USER_ID`.
5. Under **App Review → Permissions and Features**, request:
   - `instagram_basic`
   - `instagram_manage_comments`
   - `instagram_manage_messages`
   - `pages_show_list`
   - `pages_read_engagement`

   See §7 below — in Development Mode these work for the app's own Admins/Developers/Testers without App Review; you need App Review only to use them with any other Instagram professional account.
6. Under **Webhooks**, subscribe your app to the **Instagram** object, field **`comments`**.

---

## 5. Webhook configuration in n8n

1. Import `workflows/instagram-comment-automation.json` into n8n.
2. Activate the workflow, then open the `Instagram Webhook Events (POST)` node to copy its **Production URL** (something like `https://your-n8n-host/webhook/instagram-comments`). The `Instagram Webhook Verify (GET)` node listens on the **same path**, differentiated by HTTP method — n8n supports two separate Webhook nodes sharing one path this way.
3. In the Meta App Dashboard's Webhooks screen, paste that URL as the **Callback URL**, and enter the exact same string you put in `INSTAGRAM_VERIFY_TOKEN` as the **Verify Token**.
4. Click **Verify and Save** — Meta sends a `GET` with `hub.mode=subscribe`, `hub.verify_token=<your token>`, `hub.challenge=<random int>`. The `Verify Meta Webhook` Code node checks the token and the `Verified?` IF node returns `hub.challenge` verbatim with HTTP 200 (or 403 if the token doesn't match).
5. Subscribe to the `comments` field for your Instagram object.

**Not implemented — hardening you should add before production:** signature verification of the `X-Hub-Signature-256` header (Meta signs every POST body with your App Secret using HMAC-SHA256). This requires enabling the Webhook node's "Raw Body" option and computing the HMAC over the exact raw bytes, whose exact wiring differs slightly across n8n versions — verify it against your installed version rather than trust a guess baked into the exported JSON. Reference: https://developers.facebook.com/docs/graph-api/webhooks/getting-started (see "Validating Payloads").

---

## 6. Meta permissions required

| Permission | Why |
|---|---|
| `instagram_basic` | Baseline read access to the connected Instagram professional account. |
| `instagram_manage_comments` | Read comments, and publish public replies via `POST /{ig-comment-id}/replies`. |
| `instagram_manage_messages` | Send private replies via `POST /{ig-user-id}/messages`. Comment permissions and message permissions are separate — you need both. |
| `pages_show_list` | List the Pages your token can manage, required to resolve the connected Instagram account. |
| `pages_read_engagement` | Read Page/Instagram engagement data used by the comments webhook. |

All five require **App Review** before they work for any Instagram account other than your app's own Admins/Developers/Testers (see §11).

---

## 7. Endpoints used

| Node | Endpoint | Docs |
|---|---|---|
| `Send Private Reply` (+ retry) | `POST https://graph.facebook.com/v23.0/{ig-user-id}/messages` | https://developers.facebook.com/docs/instagram-platform/private-replies/ |
| `Reply to Comment` (+ retry) | `POST https://graph.facebook.com/v23.0/{ig-comment-id}/replies` | https://developers.facebook.com/docs/instagram-platform/instagram-graph-api/reference/ig-comment/replies/ |
| Webhook verification | `GET` with `hub.mode` / `hub.verify_token` / `hub.challenge` | https://developers.facebook.com/docs/graph-api/webhooks/getting-started |
| Comments webhook payload shape | `field: "comments"`, `value: {id, text, media, from, parent_id, ...}` | https://developers.facebook.com/docs/graph-api/webhooks/reference/instagram |

---

## 8. Configuration: how to change things

Everything below lives in exactly one `Code` node each — the rest of the workflow never needs to change.

### Keywords, priority, DM messages, generic fallback
Node **`Message Rules Configuration`**. It holds a JS array:

```js
const rules = [
  { name: 'prix', keywords: ['prix', 'tarif', ...], dmMessages: ['...', '...'] },
  { name: 'guide', keywords: [...], dmMessages: [...] },
  { name: 'formation', keywords: [...], dmMessages: [...] },
];
const defaultDmMessages = ['...', '...'];
```

- **Add a keyword**: add a string to a rule's `keywords` array. Matching is case-insensitive and accent-insensitive (comment text is lowercased and stripped of accents/punctuation by the `Normalize Comment Text` node before matching, and keywords are normalized the same way at match time).
- **Add a new rule**: append a new `{ name, keywords, dmMessages }` object.
- **Change priority**: reorder the `rules` array — `Match Keyword Rule` walks it top to bottom and stops at the first match. Nothing else references rule order.
- **Change a DM's wording**: edit the strings in `dmMessages`. Use `{{username}}` anywhere you want the commenter's handle inserted.
- **Change the generic fallback**: edit `defaultDmMessages` (used when no rule matches).
- **Change links**: replace the `[LIEN]` / `[LIEN_OU_INFORMATION]` placeholders with your real URLs.

### Public replies
Node **`Public Replies Configuration`** — a flat array of strings. Add, remove or reword freely; one is chosen at random per comment by `Select Random Public Reply`.

### Random selection & `{{username}}`
`Select Random DM` picks a uniformly random entry from the matched rule's `dmMessages` (or `defaultDmMessages`), substitutes `{{username}}`, and then runs a safety check that strips any literal `undefined`, `null`, or leftover `{{...}}` placeholder before the text is ever sent — so a missing username degrades gracefully to a message without a name rather than a broken-looking DM.

---

## 9. Persistent storage & deduplication

Postgres table `ig_processed_comments` ([`sql/schema.sql`](sql/schema.sql)), with `comment_id` as the `PRIMARY KEY`.

`Reserve Comment (Atomic)` runs a single statement:

```sql
INSERT INTO ig_processed_comments (comment_id, media_id, comment_text, username, created_at)
VALUES ($1, $2, $3, $4, now())
ON CONFLICT (comment_id) DO NOTHING
RETURNING comment_id;
```

This is genuinely atomic under concurrent executions (two webhook deliveries for the same comment racing each other): the database's unique-key constraint guarantees only one `INSERT` wins. If the row already exists, zero rows are returned and — because n8n stops propagating an item once a node produces no output for it — nothing downstream runs for that duplicate. There is deliberately no separate "check, then insert" step, because that pattern is *not* atomic and would race under concurrency.

Columns stored: `comment_id, media_id, comment_text, username, matched_rule, selected_dm, selected_public_reply, dm_status, public_reply_status, status, created_at, processed_at, error_message` — matching the fields requested.

**Known residual gap**: if the n8n process crashes in the few milliseconds between a successful Meta API call and the following `Postgres UPDATE`, that particular status update is lost (the DM or reply was actually sent, but the database won't know it). This is a standard at-least-once-delivery tradeoff; a subsequent duplicate webhook delivery for the same `comment_id` will be dropped by the reservation step (row already exists) rather than double-sending, so the failure mode is "status under-reported," never "message sent twice."

---

## 10. Error handling & status semantics

| Situation | `dm_status` | `public_reply_status` | `status` |
|---|---|---|---|
| Ignored (own comment, invalid payload, duplicate) | *(no row written)* | | |
| DM sent, public reply sent | `sent` | `sent` | `done` |
| DM sent, public reply failed | `sent` | `failed` | `error` |
| DM failed | `failed` | `skipped` | `error` |

Retry logic (`Classify DM Error` / `Classify Public Reply Error` Code nodes, applied identically to both Meta calls):

- `429`, `500`, `502`, `503`, `504` → retryable. Waits `Retry-After` seconds if Meta sent that header, otherwise exponential backoff (`2^attempt` seconds), up to **3 attempts**, then gives up.
- `400`, `401`, `403` → permanent, **never retried automatically** (bad payload / revoked or invalid token / missing permission).
- The retry loop is a real loop in the graph (`Wait` node connects back into the same `HTTP Request` node), capped by the attempt counter, so it terminates.

> **n8n-version caveat**: the exact property path n8n uses to expose a failed HTTP call's status code (`error.httpCode`, `error.statusCode`, `error.cause.httpCode`, ...) has varied slightly across n8n releases. The Code nodes here check several known paths defensively, but you should confirm during testing (§12) that classification actually fires — trigger a deliberate 401 (revoke/mistype the token) and check the `Handle Error` execution's `dm_status_code` field is populated, not `null`.

If the DM succeeds but the public reply fails, the row is left as `dm_status='sent', public_reply_status='failed'` and is **never** re-entered through the DM step again. Run `workflows/retry-failed-public-replies.json` (on a schedule or manually) to retry only the public reply.

---

## 11. Meta limitations you cannot work around

- **One private reply per comment.** Meta enforces at most one private-reply message per `comment_id`; do not call `Send Private Reply` twice for the same comment (the dedup/reservation step already prevents this).
- **7-day window.** A private reply must be sent within 7 days of the comment being posted, except comments on an Instagram **Live** broadcast, which only accept private replies during the live broadcast itself.
- **Additional messages** beyond the single private reply require the recipient to message you first, which opens a normal 24-hour messaging window — this workflow does not attempt to send anything beyond the one allowed private reply.
- **Comment types**: private replies work on comments on posts, Reels, Stories, Live broadcasts, and ad posts. Public replies (`/replies`) do **not** work on Live-video comments — use the private reply only there; also, public replies cannot target a comment that is currently hidden, and replying to a reply attaches the new reply to the top-level comment thread rather than the nested one.
- **Rate limit**: private replies to comments are capped at **750 calls/hour per Instagram professional account**. General Graph API calls are also subject to the platform's standard per-app/per-user rate limiting (`X-Business-Use-Case-Usage` / `X-App-Usage` response headers, HTTP 429 when exceeded) — the retry logic in §10 already backs off on 429.
- **Development vs. Production mode**: while your app is in Development Mode, all of the above works only for Instagram accounts belonging to the app's registered Admins/Developers/Testers. Moving to Live/Production mode for other accounts requires **App Review** approval of every permission in §6.
- This workflow does not and cannot bypass any of the above — attempting to send a second private reply, reply outside the 7-day window, or use these permissions on a non-Development account without App Review will simply be rejected by Meta's API.

---

## 12. Testing protocol

1. **Structural check** — `npm run` a JSON validator or simply `python3 -m json.tool workflows/instagram-comment-automation.json` to confirm the file parses; then import it into n8n and confirm it opens with no red "unrecognized node" markers.
2. **Webhook verification** — with the workflow active, do:
   ```bash
   curl "https://your-n8n-host/webhook/instagram-comments?hub.mode=subscribe&hub.verify_token=YOUR_TOKEN&hub.challenge=12345"
   ```
   Expect the raw response body `12345` with HTTP 200. Try a wrong token and expect HTTP 403.
3. **Event ingestion** — POST each file in [`test/sample-payloads/`](test/sample-payloads) to the same URL:
   ```bash
   curl -X POST "https://your-n8n-host/webhook/instagram-comments" \
     -H "Content-Type: application/json" \
     --data @test/sample-payloads/01-single-comment-price-keyword.json
   ```
   - `01-single-comment-price-keyword.json` → expect a matched `prix` rule, a DM sent, a row with `status='done'`.
   - `02-batched-two-comments-reel.json` → two `entry` objects in one payload; confirm **both** produce independent rows (tests the "split a batched payload" requirement).
   - `03-own-comment-should-be-ignored.json` → `from.id` equals `INSTAGRAM_USER_ID`; confirm **no row is written** and no Meta call is made.
   - `04-malformed-missing-media.json` → confirm it's dropped by `Validate Event`, no row written.
   - `05-non-comment-field-should-be-ignored.json` → confirm `Extract Comment Events` outputs zero items (field is `mentions`, not `comments`).
   - Re-POST `01-single-comment-price-keyword.json` a second time → confirm `Reserve Comment (Atomic)` returns 0 rows and nothing else runs (dedup works).
4. **Error path** — temporarily set `INSTAGRAM_ACCESS_TOKEN` to an invalid value, re-run test 1, confirm the row ends with `dm_status='failed'`, `public_reply_status='skipped'`, `status='error'`, and a non-null `error_message`. Restore the real token.
5. **Public-reply-only failure** — with a valid token, temporarily point the `Reply to Comment` node's URL at an invalid comment ID (e.g. append `x`), confirm the row ends `dm_status='sent'`, `public_reply_status='failed'`. Fix the URL, then run `workflows/retry-failed-public-replies.json` manually and confirm the row flips to `public_reply_status='sent'` without a second DM being sent.
6. **Rate-limit / retry path** — hardest to trigger deliberately; at minimum, unit-review the `Classify DM Error` / `Classify Public Reply Error` code against a manually crafted test item (`{error: {httpCode: 429, headers: {'retry-after': '5'}}}`) using n8n's "Test step" on the Code node to confirm `dm_can_retry=true` and `dm_wait_seconds=5`.
7. **End-to-end** — once all of the above pass, post a real comment containing one of your keywords on a test post from a secondary Instagram account and confirm you receive the DM and see the public reply appear.

---

## 13. Development → Production checklist

- [ ] All 5 permissions in §6 approved via **App Review** (submit screen recordings showing the exact use case: a user comments a keyword, receives a private reply, sees a public reply).
- [ ] App switched from **Development** to **Live** mode in the App Dashboard.
- [ ] Long-lived Page access token generated and stored in `INSTAGRAM_ACCESS_TOKEN`; a plan in place to refresh it before ~60-day expiry (not automated by this workflow).
- [ ] Webhook Callback URL points at your production n8n host (not a tunnel/ngrok URL), served over HTTPS with a valid certificate.
- [ ] `INSTAGRAM_VERIFY_TOKEN` is a long random string, not the example value.
- [ ] Postgres database is the production instance, reachable from production n8n, with `sql/schema.sql` applied and backups configured.
- [ ] All `[LIEN]` placeholders replaced with real URLs in `Message Rules Configuration` and the generic fallback.
- [ ] Signature verification (`X-Hub-Signature-256`) added per the note in §5, if you need defense against spoofed webhook calls.
- [ ] `workflows/retry-failed-public-replies.json` activated on its own schedule (or documented as a manual runbook step).
- [ ] Ran the full test protocol (§12) against production credentials/URLs at least once.
- [ ] Confirmed the 750 calls/hour private-reply limit is compatible with your expected comment volume.

---

## 14. Known limitations / where you might still need App Review or manual work

- Long-lived token refresh is **not automated** — build a separate scheduled workflow if you need this, or refresh manually every ~60 days.
- `X-Hub-Signature-256` payload signing is **documented but not wired in** (§5) — add it yourself, verified against your n8n version.
- The retry loop's error-classification Code nodes read the failed-request status code defensively across a few possible n8n property paths; confirm the exact one that fires on your installed n8n version (§10, §12 step 4).
- App Review is required for all 5 permissions before this can run against any Instagram account other than your app's own Admins/Developers/Testers.
- Meta's 750-calls/hour private-reply limit and standard Graph API rate limits are hard platform ceilings this workflow cannot exceed even with retries — high-volume accounts should monitor the `X-Business-Use-Case-Usage` header and consider queuing.
