# SketchLift free-tier proxy (Vercel Edge Function)

Lets friends use the SketchLift APK **without their own Gemini key**. The key
lives only on the server as an environment variable — it is never inside the APK.

## Contract (what the app sends)

```
POST https://<your-project>.vercel.app/api/generate
Content-Type: application/json
X-App: sketchlift
X-Device-Id: <random 16–64 chars [A-Za-z0-9_-], generated once per install>

{ "model": "gemini-3.8-flash", "body": <exact Gemini generateContent request body> }
```

Response: Gemini's raw `generateContent` JSON with the same status code, plus an
`X-Remaining` header. `429 {"error":"daily_limit"}` when the device used its free
calls for the day (the app shows a friendly Hindi/English message).

## Protection
- Only `X-App: sketchlift` requests, only "flash" model names (regex allow-list).
- Per-device daily limit (`DAILY_LIMIT`, default 5 successful calls).
- 6 MB request cap (the app sends ~1600 px JPEGs, q80–85).
- Automatic fallback to `gemini-flash-latest` / `gemini-3.5-flash` on 404/503.

**Honest limits:** the counter is in-memory per edge instance, so it resets when
Vercel starts a new instance and is not shared across regions. For real
enforcement move it to Vercel KV / Upstash Redis (`INCR device:day`, `EXPIRE 86400`).
The device id is self-reported, so a determined user can rotate it — fine for a
free student project, not for a paid product. The app also keeps its own daily
counter.

## Deploy
```bash
cd proxy
npx vercel                        # first time: link/create the project
npx vercel env add GEMINI_API_KEY # paste the key from aistudio.google.com
npx vercel env add DAILY_LIMIT    # optional, default 5
npx vercel --prod
```
Then build the app with
`--dart-define=PROXY_URL=https://<project>.vercel.app/api/generate`
(or change the default in `lib/app_config.dart`).

## Test
```bash
curl -s -X POST https://<project>.vercel.app/api/generate \
  -H 'Content-Type: application/json' -H 'X-App: sketchlift' -H 'X-Device-Id: devtest_0001' \
  -d '{"model":"gemini-3.8-flash","body":{"contents":[{"role":"user","parts":[{"text":"Say hi"}]}]}}'
```
