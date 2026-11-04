# Experimental custom rewrite servers

See [the README](../README.md#connect-a-local-or-remote-model-experimental) for connection settings.
Server provisioning is separate: this feature only connects Dictidy to an existing inference service.
The intended first deployment is llama-server on an Apple Silicon Mac behind Tailscale Serve.

## Protocol and limits

- One saved server; HTTP or HTTPS API base URL, with optional Bearer token. Use HTTPS remotely.
  A bare origin gets `/v1`; custom prefixes such as `/llm/v1` are preserved.
- `GET models` relative to the base URL must return `{"data":[{"id":"model-alias"}]}`.
  Dictidy accepts arbitrary IDs; choose a text instruction model rather than an embedding model.
- `POST chat/completions` sends the model ID, a system message containing the existing base/style
  instructions, and one user message containing the wrapped source text. No conversation history,
  tools, or streaming are requested.
- The output budget is 2,048 tokens. A single assistant message with a string `content` and
  `finish_reason: "stop"` is required. Refusals, truncated output, and empty or malformed responses
  are errors; partial text never replaces the source. Separate `reasoning_content` is ignored.
  Use a non-thinking instruction model that returns the rewrite directly in `content`.
- Model discovery times out after 20 seconds; rewriting after 180 seconds. A cold model may need
  time to load. Server context size must accommodate the prompt, source, and generated text.
- Redirects are blocked. Enter the final API URL rather than a URL that redirects elsewhere.
  Tokens are independent of cloud credentials; requests do not use cookies or a disk cache.
- Cached model lists allow use after relaunch. They do not imply that the server is currently online.
  Save & Test Connection verifies model discovery, not rewrite quality or a model's capabilities.
- A changed server address creates a new connection identity. Saved model selections for the old
  address stay unavailable, including after removing and re-adding the server. Select the new model
  explicitly. Refreshing or replacing a token at the same address retains model identities.

## Automated verification

```sh
swift run DictidyTests
./Scripts/test-compatible-server.sh
```

The unit checks cover request shape, URL validation/persistence, optional authentication, arbitrary
catalog IDs, connection identity, cancellation, and failure responses. The native HTTP check starts a
temporary loopback server to verify the production URLSession, including blocked redirects and cookies.
Neither requires a model, remote machine, or saved credentials. CI runs both.

## Acceptance checks when the inference server is available

1. Save its URL and token; verify discovery and choose its text model. Relaunch Dictidy and confirm
   the address, token status, catalog, and selection persist. Also test a server without authentication.
2. Rewrite selected multiline text. Check that meaning, language, and paragraph breaks survive.
   Repeat through a per-instruction override, History's Rewrite again, and Dictate + Clean.
3. Stop the server or disconnect Tailscale. Confirm a clear error, preserved selected text, and no cloud
   fallback. For failed Dictate + Clean, confirm the raw transcript remains available for recovery.
4. Try a wrong token and a text long enough to exhaust context/output. Confirm errors do not paste
   partial output. Press Escape during a slow request and confirm no late result is pasted.
5. Change the URL to another server exposing the same model ID. Verify the old default and instruction
   override become unavailable until explicitly changed. A blank token must not reuse the old server's
   token. Remove the connection while discovery is running; a late response must not restore it.
