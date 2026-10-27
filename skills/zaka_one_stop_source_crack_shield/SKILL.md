# 一条龙写源破解破盾

- Use this skill when the user gives a site, app, APK or API and wants a working TVBox source, or says the data is blocked by encryption, signing, obfuscation, a paywall or a shield.

- Work only on the target the user provides in that task and stay inside the scope they set.

- Follow one pipeline from start to finish and do not skip its exit conditions: triage, feasibility gate, data extraction, obstacle restoration, shield handling, source writing, strict verification, delivery.

- Treat the three fused sources as one system, with the write source pipeline in `tools/` as the spine, the reverse engineering cards and library in `references/` as the judgement layer, and CF-Ares in `scripts/` as the shield channel.

## Triage the target

- Run `python3 tools/zaka_crack_kit.py probe <url>` first and record the obstacle kinds, the route and the paywall verdict in the work directory's notes file (摸站笔记), never in the source file: the user (2026-10-22) does not want triage/RE_ header comment blocks in delivered py sources, keep the source file clean.

- Route by what you actually see, using `references/cards/01-障碍判型与升级路由.md` as the master table.

  - Use direct HTML parsing for plain list and detail pages with page parameters.
  - Use card 10 for MacCMS (苹果CMS) sites and XBPQ declarative rules: check the public XBPQ rule collections for an existing rule for the same site before probing from zero, deliver an XBPQ JSON rule directly when the user's shell carries a `csp_XBPQ` jar, and otherwise treat the rule as a ready-made site map and translate its fields into the Python spider.
  - Use `Page.auto()` for embedded data such as `__NEXT_DATA__`, `__NUXT__`, RSC Flight and JSON-LD, and do not scrape the DOM first.
  - Use card 02 and `Cipher.auto()` or `Sign.guess()` when an API returns ciphertext or needs a sign, timestamp or nonce.
  - Use card 03 and `Obf.deobfuscate()` when JavaScript is split into `_0x` style fragments, and treat WASM as a black box to call before trying to reverse it.
  - Use card 04 for APK and mobile targets and card 05 for Frida, unpacking and memory work when the answer only exists at runtime.
  - Use the shield channel below when you see a Cloudflare challenge, Turnstile or a cookie gate, and check it with `scripts/detect_cf.py` and `Net.detect_challenge()`.
  - Use card 06 to classify a paywall or DRM case before touching it, and stop when the verdict is server side billing because a front end change cannot change that result.
  - Use `tools/flutter_triage.py <apk>` for Flutter, React Native or hybrid shells and use card 08 for private gateways.

- Leave the verdict open when the evidence does not fit a kind, advance by broad category, and converge again when new evidence arrives.

## Pass the feasibility gate

- Run `tools/gate_probe.py` and `tools/flutter_triage.py` as the gate step before heavy work and continue only when at least one gate passes.

  - Check whether trial requests give differentiated feedback, because a gateway that returns one identical message to every variant has zero oracle value and exhaustive guessing will not converge.
  - Check whether the environment has the memory, tools, time and network exit the work needs before starting disassembly or compilation.
  - Check whether a successful result would actually yield a playable source, because a technically open target with no playable stream is not a delivery.

- Go to retreat delivery when a gate fails, and deliver the archive, the pluggable skeleton, the raw route data and a concrete next step instead of an empty result.

## Extract data before restoring algorithms

- Run `python3 tools/zaka_crack_kit.py page <url>` and stop at this level when embedded data or a direct API already gives titles, IDs and play addresses.

- Reach for the eight helpers in `tools/zaka_crack_kit.py` only for the obstacle in front of you.

  - Use `Codec` for base64 variants, hex, JavaScript escapes and gzip or deflate layers.
  - Use `Cipher` for XOR, AES modes, 3DES, RC4, ChaCha20 and Fernet candidates, fed by `Cipher.key_pool()` from the page.
  - Use `Sign` to exhaust parameter ordering and digest variants, after listing every field the client sends and checking server time.
  - Use `Page` to dig nested objects, `Obf` to restore `_0x` arrays and pull keys and endpoints, `Stream` to parse m3u8 and verify segments, `Net` for user agent, cookie, referer and retry handling, and `Probe` for triage and paywall classification.

- Close the loop on every restoration by showing the plaintext explains the business data and by making one real request the server accepts.

- Score plaintext by word boundaries, letter and space density and hard symbol density, and do not trust a printable ratio alone.

## Handle the shield with CF-Ares

- Enter this channel when the other request routes fail on a Cloudflare 5 second shield, CAPTCHA, Turnstile or JavaScript challenge, or when detection confirms Cloudflare in front of the target.

- Follow the two stage pattern in `references/cf-ares/integration.md`, with `scripts/cf_ares_bridge.py` and the self contained library in `scripts/cf_ares/`.

  - Try the curl engine first through `AresClient` or `cf_get()`, which uses `curl_cffi` TLS fingerprint impersonation such as `chrome_120` and costs no browser.
  - Initialise a browser engine lazily only when the curl stage hits a challenge, choosing `undetected` for heavy JavaScript challenges and `seleniumbase` when debugging, and set proxy, fingerprint, headless mode and chrome path on `AresClient` as the case needs.
  - Solve on the development machine with `python3 scripts/cf_ares_bridge.py solve <url> -o cf_cookies.json` and fix the resulting `cf_clearance` and related cookies to a file.
  - Inject only the fixed cookie header into the TVBox spider through `cookie_header_for()` and never run a browser engine inside the TVBox shell.
  - Re-solve and refresh the cookie when list, detail or playback requests start returning a challenge again, because fixed cookies expire in minutes to hours.
  - Save and load sessions with `save_session()` and `load_session()` to reduce how often a challenge must be solved.

- Read `references/cf-ares/api.md` for the full `AresClient` surface and `references/cf-ares/troubleshooting.md` for ChromeDriver, headless and timeout failures.

- For tool selection beyond the bundled Ares engines, read `references/cards/09-过盾工具链增补.md` (GitHub survey, 2026-10): a five tier ladder from HTTP fingerprint impersonation (curl_cffi with a current browser profile, httpcloak for full stack spoofing) through engine level stealth browsers (Camoufox as the default browser engine, patchright, invisible_playwright for behaviour scoring) to clearance solver services (FlareSolverr protocol, trawl with tiered fallback and clearance caching, full request mirroring when POST APIs must be proxied too). Its hard rules bind every tier: a fixed cf_clearance is valid only with the identical user agent and exit IP it was solved under, fingerprint profiles must roll with browser versions, and a datacenter exit IP cannot be rescued by fingerprint work on high grade managed challenges.

- Report a shield result only after list, detail and playback are all reachable with the fixed cookie, and state the cookie expiry limit in the delivery.

## Write the source

- Follow the full-contract protocol (全协议, superset of the old four-shell rule) as an iron rule for every TVBox Python source, with no exceptions. The old rule was right in its core but incomplete; the full contract below is now the standard (upgraded 2026-10-23 after auditing a bare-class 13-method script against the delivered missav/javmit/17c sources):

  - **Class**: the main class must be named `Spider` and must be written `class Spider(BaseSpider)` with the hybrid import `try: from base.spider import BaseSpider` / `except: class BaseSpider: pass`. Do not deliver a bare `class Spider:` (it only works on duck-typing loaders; on Chaquo/FongMi-style shells the shell-provided base carries the proxy/helpers, and removing the import loses them for no gain — the fallback already makes the same file run bare outside a shell), and never deliver a source whose main class is a self defined `BaseSpider`, because real shells load only the `Spider` attribute and fail with a module has no Spider class error. `Spider()` must instantiate with no arguments and must not depend on `init()` being called first.
  - **Methods, all 14, always**: `getName`, `getDependence`, `init`, `destroy`, `homeContent`, `homeVideoContent`, `categoryContent`, `detailContent`, `searchContent`, `playerContent`, `localProxy`, `isVideoFormat`, `manualVideoCheck`, `action`. A method a given site does not need still exists and returns its safe default (for example `localProxy` fetches-and-returns or a graceful 4xx tuple, `action` returns `{}`, `getDependence` returns `[]`); missing methods, not extra ones, are what break stricter shells. Verify by importing the module the way a shell does and asserting `Spider` exists and all 14 methods are callable before delivery.
  - **Tolerant signatures and arguments**: give every contract parameter a default (`filter=None`, `extend=None`, `pg=1`, `vipFlags=None`, …) so shells that call with fewer, positional or keyword arguments all work. Normalise the variants shells actually send: `detailContent` ids in four states (list / tuple / single string / comma-joined string), `extend` as dict or JSON string, `pg` as int or string, and a `playerContent` id that may still carry its `name$` prefix.
  - **Headers**: `playerContent` must return its `header` as a dict, never as a joined string, including when the returned URL is a relay/proxy URL (then an empty dict).
  - **HTTP**: zero hard third-party dependencies. Standard-library `urllib` is the guaranteed base; `requests` may be tried first only inside a guarded `try` import with automatic fallback to `urllib` when it is absent or a request fails. Never hard-depend on `urllib3` directly (that was the old avdj/avmt brittleness).
  - **`localProxy` dialects**: the default return is the 4-item form `[status:int, mime:str, body, headers:dict]`. Legacy shells also accept the 3-item prefix form, and the FongMi Chaquo bridge reads a 5-item form `[code, contentType, body, headers, base64_flag]` — use that 5-item variant, with flag `1`, only when the body is a base64 string on the FongMi `proxy://…siteKey=…` image chain (the verified 17c/91n mechanism); do not present any one length as the only standard.
  - **Playback layering**: return the direct URL with its headers first. A self-built `127.0.0.1` relay (rewriting m3u8 relative URLs, fixing segment MIME, injecting UA/Referer) or the shell's own `/proxy` is an optional fallback layer for sites whose streams actually need rewriting or header injection, never the default for every site, and a relay failure must fall back to the shell proxy and then to the direct URL. A constructed relay address is intentional code, not a hardcoded placeholder address.

- Generate the skeleton with `python3 tools/new_source.py <name> --url <url> --domain <categories> --domains <main,backup> --type <html|api|spa> --out <spider.py>` and then edit only the SITE profile section.

- Keep the domain candidate table with liveness probing, cookie gate handling, timeout and retry, and play URL assembly that the generator emits. Do not add a triage header comment block to the source file.

- Implement the TVBox spider surface completely, covering `homeContent`, `categoryContent`, `detailContent`, `searchContent` and `playerContent`, with play sources joined as line name, dollar sign and address entries.

- Pass referer and user agent through the `header` returned by `playerContent` instead of proxying the stream through your own server.

- Keep magnet sections off by default through an `ext` switch, because TVBox cannot play them and an open empty section reads as a broken source.

## Verify strictly and deliver

- Run `python3 tools/shellsim.py <spider.py> --run --strict` and do not call the source done until it returns AUDIT_OK.

  - Pass L1 static checks for missing functions, placeholder domains, private addresses, heavy dependencies, empty exception handlers and debug prints.
  - Pass L2 live checks that call the five spider methods and validate the JSON shape, pagination and play URL format.
  - Pass L3 playback checks that fetch the real play address, see `#EXTM3U`, download the first segment and confirm the duration is not only a trial window.

- **Full-coverage self-check before any push (user rule, 2026-10-23: 写的源要自检每一处没问题才能推送).** AUDIT_OK alone is not enough, because shellsim samples: before pushing a finished source anywhere (TG group/channel or handover), run a full sweep through the spider itself and require every item below to pass.

  - Every first-level class returns a non-empty first page of cards with real cover images; an empty class is a failure unless the site itself proves the section is empty, login-gated or non-video, with that reason recorded in the notes file.
  - Pagination works past page 1 in at least the main list and one content category, and index folders (actresses, tags, playlists, series) drill down into video cards, not text or episode lists.
  - `detailContent` on a real item returns complete fields and a play entry; `searchContent` with a lawful keyword returns real results; `playerContent` resolves a fresh real play address at play time.
  - Playback is proven with the spider's own returned headers: fetch the real address, confirm the format (`#EXTM3U` plus a downloaded first segment for HLS, or a Range 206 with the right magic bytes for direct files) and a full-length duration, never only a trailer or trial window.
  - The delivery report enumerates what was actually checked (which classes, which item, which play hop), so a spot check is never reported as a full check.

- **No push until every part is verified.** When part of a source cannot be verified from the current exit, do not push it as a "pending user final check" delivery: first exhaust other verification routes (the browser exit, archived real markup, an alternate domain or line, a protocol-level replay). If a part still cannot be verified after that, stop before pushing, keep the files in the work directory, and report the exact unverified part and the blocking reason to the user; push only after the missing verification passes by some route.

- Deliver the source file, the configuration snippet for the sites array, and a short usage note that names which sections are off and why.

- **Dual delivery as a pair (user rule, 2026-10-23): the Python source and an XBPQ rule file land and are pushed together.** Every finished source ships both files: the py spider and a `<name>_xbpq.json` rule written per card 10 from the same recon (categories, category URL template, filters, list/detail/play anchors), and both are pushed and registered together wherever the py is pushed. The XBPQ file goes through the same full-coverage verification mindset as the py: never ship a placeholder rule. Where a site is fundamentally beyond declarative truncation (encrypted or signed API, shield, multi-step play resolution), still land the rule for the parts it can honestly carry and state its limits in the usage note instead of faking fields that cannot work.

- Apply static L1 review only to third party scripts the user brings in, and do not run external scripts on their behalf.

## Use the reverse library on demand

- Read in this order and stop as soon as the current level answers the question: this file, then the matching card in `references/cards/`, then `references/pitfalls.md` for that domain, then the single relevant entry in `references/rev-library/`.

- Find library entries through `references/index/rev-index.csv` and their grading in `references/index/REV-相关度分级.md`, where A grade entries map directly to source writing and B and C grade entries stay as background reference.

- Open `references/rev-full-collection.md` only when you need the merged original text of all 286 source documents, and search inside it instead of reading it through.

- Keep an evidence chain for each stage in the work directory's notes file, naming the artefact produced and the conclusion drawn from it, not in the source file.

- Re-enter a stage at most once and only with new evidence, and change route, step back or deliver a partial result when no new evidence exists.

- Classify failures before retrying, separating network jitter, a real shield, upstream missing content, a zero oracle gateway, an insufficient environment, a wrong triage and a missing capability, and handle each class by its own rule in card 01.

## Available connectors

- Use `muse.connector_search` to find other connectors and `muse.skill_search` to find related skills.

- If nothing here fits, look on the web for a maintained API or MCP server and set it up with [Custom Connectors and MCPs](/opt/muse/skills/custom-connector-setup/SKILL.md), or build a custom connector.

## Websites

- Operate target sites the user provides through `browser.browse` when a live page must be visited, carrying the exact URL, the account context the task needs and the obstacle you expect to verify.
