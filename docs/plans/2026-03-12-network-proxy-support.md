# Network Proxy Support Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add a “Proxy” tab in Settings to configure HTTP(S)/SOCKS5 proxy (with optional auth + bypass list), and make all in-app networking respect the proxy configuration.

**Architecture:**
- Persist proxy preferences in UserDefaults (via `@AppStorage` for simple values), but store proxy password in Keychain.
- Centralize session construction in a single `NetworkSessionProvider` (actor) that translates `ProxySettings` into `URLSessionConfiguration.connectionProxyDictionary`.
- Replace `URLSession.shared` usage in services with injected `URLSession` from the provider, so no call site bypasses proxy by accident.

**Tech Stack:** SwiftUI, Foundation URLSession, CFNetwork proxy dictionary, Keychain Services, XCTest.

---

## Scope / Requirements

Settings UI (new tab):
- Enable/Disable proxy
- Proxy type: HTTP, HTTPS, SOCKS5
- Host + Port
- Optional username + password
- Bypass list: domains/IP/CIDR not required; keep it simple as comma/newline separated host patterns (e.g. `localhost, 127.0.0.1, *.internal`)
- Validation: host non-empty when enabled; port in 1…65535

Networking:
- Services that currently use `URLSession.shared` must be updated to use injected sessions.
- Proxy applies to: registry search/scrape, GitHub SKILL.md fetch, update check/download, ClawHub API.
- Non-network functionality must remain unchanged.

Security:
- Do NOT store the password in UserDefaults. Use Keychain.
- Username can be stored in UserDefaults.

---

### Task 1: Add proxy settings model + proxy dictionary builder (TDD)

**Files:**
- Create: `Sources/SkillDeck/Models/ProxySettings.swift`
- Create: `Sources/SkillDeck/Utilities/ProxyConfigurationBuilder.swift`
- Test: `Tests/SkillDeckTests/ProxyConfigurationBuilderTests.swift`

**Step 1: Write failing test**

Test cases (minimum):
- Disabled proxy -> empty dictionary
- HTTP proxy -> sets `kCFNetworkProxiesHTTPEnable/HTTPProxy/HTTPPort`
- HTTPS proxy -> sets `kCFNetworkProxiesHTTPSEnable/HTTPSProxy/HTTPSPort`
- SOCKS5 proxy -> sets `kCFNetworkProxiesSOCKSEnable/SOCKSProxy/SOCKSPort`
- Bypass list -> sets `kCFNetworkProxiesExceptionsList`

Run: `swift test --filter ProxyConfigurationBuilderTests`
Expected: FAIL (types not found)

**Step 2: Minimal implementation**

- `ProxySettings` as a plain struct (Codable optional).
- `ProxyConfigurationBuilder.build(from:) -> [AnyHashable: Any]` that returns a CFNetwork-compatible dictionary.

**Step 3: Run test to verify it passes**

Run: `swift test --filter ProxyConfigurationBuilderTests`
Expected: PASS

**Step 4: Commit**

```bash
git add Sources/SkillDeck/Models/ProxySettings.swift Sources/SkillDeck/Utilities/ProxyConfigurationBuilder.swift Tests/SkillDeckTests/ProxyConfigurationBuilderTests.swift
git commit -m "feat: add proxy configuration builder"
```

---

### Task 2: Add Keychain storage for proxy password (TDD)

**Files:**
- Create: `Sources/SkillDeck/Services/KeychainService.swift`
- Test: `Tests/SkillDeckTests/KeychainServiceTests.swift`

**Step 1: Write failing test**

- Save password for a fixed key (e.g. `proxy.password`), read it back, then delete.

Run: `swift test --filter KeychainServiceTests`
Expected: FAIL

**Step 2: Minimal implementation**

- Implement `KeychainService` as an `actor` with methods:
  - `setPassword(_:, forKey:)`
  - `getPassword(forKey:)`
  - `deletePassword(forKey:)`

**Step 3: Run test to verify it passes**

Run: `swift test --filter KeychainServiceTests`
Expected: PASS

**Step 4: Commit**

```bash
git add Sources/SkillDeck/Services/KeychainService.swift Tests/SkillDeckTests/KeychainServiceTests.swift
git commit -m "feat: add keychain service for proxy password"
```

---

### Task 3: Add NetworkSessionProvider and inject into services

**Files:**
- Create: `Sources/SkillDeck/Services/NetworkSessionProvider.swift`
- Modify: `Sources/SkillDeck/Services/SkillRegistryService.swift`
- Modify: `Sources/SkillDeck/Services/SkillContentFetcher.swift`
- Modify: `Sources/SkillDeck/Services/UpdateChecker.swift`
- Modify: `Sources/SkillDeck/Services/ClawHubService.swift`
- Modify: `Sources/SkillDeck/Services/SkillManager.swift`

**Steps:**
1. Provider reads current proxy preferences (UserDefaults + Keychain).
2. Provider builds `URLSessionConfiguration` and returns sessions.
3. Replace `URLSession.shared` calls with `session.data(for:)` using injected session.
4. Ensure UpdateChecker download uses a session built from provider (delegate-capable).

**Verification:**
- `swift build`
- `swift test`

**Commit:**

```bash
git add Sources/SkillDeck/Services/NetworkSessionProvider.swift Sources/SkillDeck/Services/*.swift
git commit -m "refactor: inject proxy-aware URLSession into services"
```

---

### Task 4: Add Proxy tab in Settings

**Files:**
- Modify: `Sources/SkillDeck/Views/SettingsView.swift`
- Create: `Sources/SkillDeck/Views/Settings/ProxySettingsView.swift`

**UI Fields:**
- Toggle: Enable proxy
- Picker: Type (HTTP / HTTPS / SOCKS5)
- TextField: Host
- TextField: Port (numeric)
- TextField: Username (optional)
- SecureField: Password (stored via Keychain)
- TextEditor or TextField: Bypass list (comma/newline separated)
- Helper text: explains examples and that password is stored in Keychain

**Commit:**

```bash
git add Sources/SkillDeck/Views/SettingsView.swift Sources/SkillDeck/Views/Settings/ProxySettingsView.swift
git commit -m "feat: add proxy settings tab"
```

---

### Task 5: Manual verification checklist

1. Open Settings → Proxy, enable proxy, set type/host/port.
2. Trigger network actions (registry search, open skill detail, update check, ClawHub browse).
3. Confirm with an intercepting proxy (mitmproxy) or by pointing to an invalid proxy and verifying failures are surfaced as network errors.
4. Confirm bypass list works for `localhost` and `127.0.0.1`.

---

## Notes / Edge Cases

- Proxy dictionary keys come from CFNetwork constants (bridged into Swift as `kCFNetworkProxies*`).
- Keep the initial bypass parsing simple: split by commas/newlines, trim whitespace, drop empties.
- Don’t attempt PAC files or system proxy integration in the first iteration (YAGNI).
