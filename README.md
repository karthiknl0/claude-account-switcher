# Claude Account Switcher

Switch between multiple **Anthropic Claude** accounts (e.g. several Pro/Max
accounts you own). One install gives you **two switchers**:

- **Desktop app** *(Windows only)* — flip the **Claude desktop app** (claude.ai
  chats) between accounts, with a Desktop shortcut and a usage readout.
- **Claude Code CLI** *(Windows · macOS · Linux)* — flip **Claude Code**
  (`claude`) between accounts; since your project transcripts are shared across
  accounts, you can hit a limit, switch, and `claude --resume` to continue the
  *same work* on another account. Shows 5h/7d usage **and reset times**.

Neither app has a built-in account switcher — this adds both. **No npm required.**

| Switcher | Windows | macOS | Linux |
|---|:---:|:---:|:---:|
| Claude Code CLI | ✅ | ✅ | ✅ |
| Desktop app | ✅ | — | — |

---

## Quick start

**Windows** (PowerShell):

```powershell
# 1. Install (run once)
irm https://raw.githubusercontent.com/karthiknl0/claude-account-switcher/main/install.ps1 | iex
# 2. Open a NEW PowerShell window, then save each account (see "Add your accounts")
claude-add-account
# 3. Switch any time
claude-switch-account
```

**macOS / Linux** (Claude Code CLI only — requires [PowerShell](https://aka.ms/powershell)):

```bash
# 1. Install (run once)
pwsh -c "irm https://raw.githubusercontent.com/karthiknl0/claude-account-switcher/main/install.ps1 | iex"
# 2. Reload your shell (or open a new terminal), then save each account
source ~/.zshrc   # or ~/.bashrc on Linux
claude-code-add
# 3. Switch any time
claude-code-switch
```

> **Requires:** Windows for the desktop-app switcher. The Claude Code CLI
> switcher also runs on macOS/Linux with [PowerShell](https://aka.ms/powershell)
> installed. On macOS the Claude Code login lives in the **Keychain**, so the
> first read/write may prompt you to *Allow* access.
>
> Run **`claude-code-doctor`** any time to verify your setup — it prints the
> detected platform, credential backend, live-login status, and saved accounts.

---

## Step 1 — Install

Open **PowerShell** and run:

```powershell
irm https://raw.githubusercontent.com/karthiknl0/claude-account-switcher/main/install.ps1 | iex
```

This installs:

- Scripts in `~/.claude-tools/`
- PowerShell commands: `claude-add-account`, `claude-switch-account` (desktop app);
  `claude-code-add`, `claude-code-switch`, `claude-code-doctor` (Claude Code CLI);
  `claude-switch-update`
- a **"Claude Switch Account"** shortcut on your Desktop (for the desktop app)

**Then open a new PowerShell window** so the commands load.

> Which one do you want? Use the **desktop-app** commands to switch the Claude
> app's chats. Use the **Claude Code** commands to switch which account your
> `claude` coding sessions run under (see the Claude Code section below).

---

## Step 2 — Add your accounts

> ⚠️ **Do NOT use the Claude app's "Log out" while adding accounts.** Logging out
> revokes that account's session on Anthropic's servers, which kills the saved
> snapshot. `claude-add-account` clears the *local* login for you instead — so
> every saved account stays valid.

1. **Log into your first account** in the Claude desktop app.
2. Run:

   ```powershell
   claude-add-account
   ```

   - Enter that account's **email** when asked.
   - Claude briefly closes (to copy its session) and reopens.
3. When it asks **"Add ANOTHER account now?"** → type **`y`**. Claude reopens at a
   **fresh sign-in screen** (your first account is *not* logged out).
4. **Sign in as your next account**, run `claude-add-account` again, enter its
   email. Repeat for as many accounts as you like.
5. On the **last** account, answer **`n`** to "Add ANOTHER account?".

---

## Step 3 — Switch accounts

- **Double-click** the **"Claude Switch Account"** icon on your Desktop, **or**
- run **`claude-switch-account`** in a standalone PowerShell window.

You'll see a menu like:

```
=== Switch Claude account ===
  [1] * you@example.com           5h  12% / 7d   8% used
        5h resets in 4h15m (21:49)   |   7d resets Sun Jun 7, 02:29
  [2]   work@example.com          5h  47% / 7d  31% used
        5h resets in 1h02m (18:36)   |   7d resets Fri Jun 5, 09:00
  (* = current   |   lower % = more headroom)
```

Type the **number** and press Enter. Claude closes and reopens logged into that
account.

> ⚠️ Run it from a **standalone** PowerShell window (or the Desktop shortcut),
> **not** from inside a Claude session — switching force-closes the desktop app.
>
> The **usage readout** (5-hour / 7-day % used) needs [Node.js](https://nodejs.org)
> installed; without it the menu just lists emails. An account whose saved token
> has expired shows `usage n/a` until you next switch to it.

---

## Switching Claude Code (CLI) accounts

The steps above switch the **desktop app**. To switch which account your
**Claude Code** (`claude`) sessions run under — handy when you hit a usage limit
mid-task — use the `claude-code-*` commands. Claude Code stores its login in a
simple credentials file, so this is a fast, safe swap.

**Save each account** (one-time):

1. In Claude Code, `/login` as your first account.
2. Run `claude-code-add` → enter its email.
3. Answer **y** to "Add ANOTHER account?" — your login is cleared locally (not
   logged out), so the saved one stays valid.
4. `/login` as the next account, run `claude-code-add` again. Repeat; answer
   **n** on the last.

**Switch + continue your work:**

```powershell
claude-code-switch     # pick the account (shows usage; * = current)
claude --resume        # continue the same conversation under the new account
```

Because your project transcripts live in `~/.claude/projects/` (shared across
accounts), `claude --resume` picks up exactly where you left off — now billed to
the account you switched to.

> Close any open Claude Code session before switching so it re-reads the new
> login. Usage shows here **without** Node (the CLI token is read directly).

---

## Updating

```powershell
claude-switch-update
```

Pulls the latest version. (You can also just re-run the install one-line.) When a
newer version is available, `claude-switch-account` shows a one-line notice.

---

## How it works

The Claude desktop app is an Electron app — your login is a **browser session**
(cookies + Local Storage + IndexedDB), just like being signed into claude.ai in a
browser. There is no single token file to swap, so the switcher works at the
session level:

- `claude-add-account` closes Claude and snapshots the live session
  (`Network`, `Local Storage`, `IndexedDB`, `Session Storage`) into
  `~/.claude-accounts/<email>/session/`.
- `claude-switch-account` closes Claude, **backs up** the current session to
  `~/.claude-accounts/.backup-<timestamp>/` (keeps the last 3), copies in the
  chosen account's session, and restarts the app.

It auto-detects the Store/MSIX app location, so it survives Claude updates.

There is no live in-app switch — the menu is the "dropdown", and the app reflects
whichever account's session is active after the restart.

---

## Uninstall

```powershell
irm https://raw.githubusercontent.com/karthiknl0/claude-account-switcher/main/uninstall.ps1 | iex
```

Removes the scripts, shortcut, and functions. Leaves your saved accounts alone;
remove them yourself if you want:

```powershell
Remove-Item -Recurse -Force ~/.claude-accounts
```

---

## Notes & caveats

- **Use only accounts you own.** This is for moving between your own accounts,
  not sharing accounts or evading limits.
- **Switching closes Claude.** The app must fully quit so its session files
  unlock; the switcher waits for that, then reopens it. Don't run it from inside
  a Claude session you care about.
- **Saved sessions are machine-bound.** Cookies are encrypted with a Windows
  (DPAPI) key tied to your user account, so a snapshot only works on the same
  Windows user/machine it was taken on. Don't copy `~/.claude-accounts` to
  another PC, and never commit it anywhere — it contains live login sessions.
- If a switch ever leaves Claude in a weird state, your previous session is in
  `~/.claude-accounts/.backup-<timestamp>/`.

## License

MIT — see [LICENSE](LICENSE).
