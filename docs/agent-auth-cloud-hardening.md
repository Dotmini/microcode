# Agent, account and Cloud hardening

This change addresses the client/backend findings from the 2026-09-22 audit. It preserves the existing working-tree work. The Cloud gateway, billing ledger, Supabase RLS and payment webhook implementations are outside this repository.

## Implemented

- Supabase uses authorization-code PKCE (S256), a correlated, expiring, single-use callback, strict callback origin/path, server-issued session payloads and Keychain-only persistence. Implicit token deep links and email-only sign-in links are rejected. Refresh is single-flight; logout cancels refresh and prevents late responses restoring a session. Identity refresh does not select an AI mode.
- Subscription metadata no longer serializes bearer/session tokens into preferences. Existing copies are migrated to Keychain. Copilot device authorization verifies access with token exchange before reporting success; its token cache is keyed by the source credential and cleared on disconnect.
- Native subscription inference supports the Copilot transport. Other web/CLI subscription tokens are explicitly rejected by the native API transport with instructions to use the provider's CLI agent. They are no longer guessed from a source label or forwarded to Dotmini. This deliberately stops unsupported cookie-as-API-key paths; it does not implement those providers' proprietary web protocols.
- The native toolbox checks component-aware, symlink-resolved paths, including missing leaves, multi-file lists and rename destinations. A workspace is required. Approval is queued and cancellation-aware; rejected tools throw instead of becoming successful evidence. Subagents enforce their tool schemas at execution and apply model/tool-call ceilings. A requested hard token budget is rejected until authoritative usage accounting is available.
- The Rust executor enforces policy for every call, including direct API calls and auto-execute callers. Command aliases are covered. Path rules reject traversal and symlink escapes. Tool hooks run at the executor and audit logs do not record arguments.
- AGY permission flags now respect the configured permission mode.
- The local HTTP/WebSocket backend requires a per-launch capability from the app. Native adapters attach it only to the loopback backend, and wildcard CORS is removed. Terminal WebSocket uses the capability in its URL because the browser WebSocket API cannot set headers; query authentication is accepted only on that endpoint.
- Backend Agent inference uses request-level Cloud configuration, refreshed account/Platform credentials and an OpenAI-compatible endpoint instead of launch-time credential environment snapshots.
- Managed GPU provisioning is single-flight. The active session is recoverable from Keychain. Polling refreshes identity and retains the session on errors. Stop clears local state only after a confirming 200 payload or 204; 202, network errors, malformed/unconfirmed responses and authorization failures preserve the handle for retry. Jupyter runtime tokens use Keychain.
- MCP fallback returns an explicit unsupported error instead of executing unauthenticated host code or reporting fabricated compiler/GPU results. Tunnel logs no longer expose tokens, and pending replies are associated with their tunnel owner.
- Tool output and saved transcript JSON pass through the privacy redactor, including JWT and Platform-key patterns. This is defense in depth, not a complete secret classifier.

PKCE contract reference: [Supabase Auth PKCE flow](https://supabase.com/docs/guides/auth/sessions/pkce-flow).

## Local backend development

A manually started backend must receive `MICROCODE_LOCAL_API_TOKEN` containing at least 32 random characters. Launch the desktop client with the same environment variable, or let the app generate a fresh token and start its child backend. Do not commit, print or persist the token. Requests need `X-MicroCode-Token`; `/health` is authenticated too. The generated notebook bridge reads the capability from the local kernel environment, never serializes it into notebook content, and sends it only to the loopback backend without following redirects. Standalone integrations must supply the matching capability; unauthenticated calls are rejected.

## Verification

Run `Scripts/tests/run-auth-agent-hardening.sh` on macOS. It compiles the actual Swift services against in-memory Keychain stubs and a URLProtocol mock; it does not use real accounts, provision paid compute or send requests to production. Preferences and filesystem fixtures are isolated. The Rust test package compiles the production policy and local auth modules and exercises an Axum route through the actual auth middleware. It also compiles the production MCP gateway and checks disconnected/error relay behavior. A Python regression exercises the generated notebook bridge with mocked requests.

Verified on 2026-09-23: the complete regression script passed all seven Swift/Python check groups and 12 Rust tests. Full Rust `cargo check --bin microcode-backend` passed both with default features and with `--no-default-features` after adding the missing `glob` dependency and correcting shadow execution error variant references. The full Swift target compiled and linked successfully in debug mode. App packaging then stopped because no `microcode-backend` executable was available to bundle. The existing embedded Rust archive contains a `stub.o`, so this frontend result does not verify live Rust FFI integration.

Full application verification additionally requires `./build.sh --frontend-only --debug` and `cargo check --bin microcode-backend`. Use an external build/cache root when internal storage is low.

## Remaining production verification and limitations

- Login must be tested against the deployed GoTrue version and its redirect allowlist, which must permit `microcode://auth/callback` with the correlation query. Previously issued implicit callback links are no longer accepted.
- Native shell and external CLI agents still run host processes under the user's OS permissions. File path checks and approval do not constitute an OS sandbox. Rust command timeout kills the direct child, but complete descendant/process-group isolation and bounded streaming output require further work.
- There is still a path-check/use race if another process swaps a symlink between validation and I/O; descriptor-relative, no-follow filesystem access is needed for hostile concurrent workspaces.
- Provider hard total-token budgets need authoritative usage data and reservation/accounting; they are not approximated as a hard billing guarantee.
- GPU lost-response provisioning recovery, account-bound reconciliation, server idempotency, idle termination and billing enforcement need gateway support and staging tests. A retained client session does not by itself prove whether remote billing has stopped.
- Public model discovery is not credential validation. Model/plan availability, gateway authorization, RLS and payment webhooks still require production/staging verification.
- Old transcripts are not rewritten, and a regex redactor cannot guarantee removal of every secret format. Treat previously saved transcripts and preferences backups accordingly.
