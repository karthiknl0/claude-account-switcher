# Claude Account Switcher

Switch between multiple **Anthropic Claude** accounts (e.g. several Pro/Max
accounts you own). One install gives you **two switchers**:

- **Desktop app** *(Windows only)* — flip the **Claude desktop app** (claude.ai
  chats) between accounts, with a Desktop shortcut and a usage readout.
- **Claude Code CLI** *(Windows · macOS · Linux)* — choose which account
  **Claude Code** (`claude`) runs as. Your transcripts are shared between
  accounts, so you can hit a limit, switch, and `claude --resume` to continue
  the *same work* on another account. Shows 5h/7d usage **and reset times**.

Neither app has a built-in account switcher — this adds both. **No npm required.**

| Switcher | Windows | macOS | Linux |
|---|:---:|:---:|:---:|
| Claude Code CLI | ✅ | ✅ | ✅ |
| Desktop app | ✅ | — | — |

---

## Upgrading from 3.x (read this first)

Claude changed two things in 2026 that broke versions 3.x ("it logs me out" /
"it doesn't switch"). Version 4 is built around both:

| What changed in Claude | What 3.x did | What 4.0 does |
|---|---|---|
| **Claude Code** now replaces its sign-in token every time it renews it, so a saved copy of a token goes dead. | Copied saved tokens in and out of one shared login file. | Each account signs in **once in its own folder** and stays signed in there. Switching only changes which folder `claude` uses — no token is ever copied. |
| **Claude desktop** (Windows Store build) moved its data to `%LOCALAPPDATA%\Claude-Data\claude_<id>\` and left the old folder empty. | Kept swapping the old, abandoned folder. | Finds the folder the app really uses, and never saves or restores an empty (signed-out) profile. |

After updating, do this **once**:

```powershell
claude-switch-update          # then open a NEW PowerShell window
claude-code-add               # Claude Code: keeps your current login, then signs each other account in once
claude-add-account            # Desktop app: sign in to each account and save it again
claude-code-doctor            # checks everything
```

---

## Quick start

**Windows** (PowerShell):

```powershell
# 1. Install (run once)
irm https://raw.githubusercontent.com/karthiknl0/claude-account-switcher/main/install.ps1 | iex
# 2. Open a NEW PowerShell window, then save each account
claude-add-account      # desktop app
claude-code-add         # Claude Code CLI
# 3. Switch any time
claude-switch-account   # desktop app
claude-code-switch      # Claude Code CLI
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

Run **`claude-code-doctor`** any time to verify your setup — it shows which
accounts are saved, whether each is still signed in, and which folder the
desktop app is really using. It only reads; it never changes anything.

---

## Install

Open **PowerShell** and run:

```powershell
irm https://raw.githubusercontent.com/karthiknl0/claude-account-switcher/main/install.ps1 | iex
```

This installs:

- Scripts in `~/.claude-tools/`
- Commands: `claude-add-account`, `claude-switch-account` (desktop app);
  `claude-code-add`, `claude-code-switch`, `claude-code-doctor` (Claude Code
  CLI); `claude-switch-update`
- A small **`claude` wrapper** in your shell profile, so the `claude` command
  runs as the account you picked with `claude-code-switch`
- Desktop shortcuts (Windows)

**Then open a new PowerShell window** so the commands load.

---

## Desktop app (Windows)

### Add your accounts

> ⚠️ **Do NOT use the Claude app's "Log out" while adding accounts.** Logging out
> ends that account's session on Anthropic's servers, which kills the saved
> snapshot. `claude-add-account` clears the *local* login for you instead — so
> every saved account stays valid.

1. **Log into your first account** in the Claude desktop app.
2. Run `claude-add-account`. It detects which account is signed in and asks you
   to confirm. Claude briefly closes (to copy its profile) and reopens.
3. When it asks **"Add ANOTHER account now?"** → type **`y`**. Claude reopens at a
   **fresh sign-in screen** (your first account is *not* logged out).
4. **Sign in as your next account**, run `claude-add-account` again. Repeat.
5. On the **last** account, answer **`n`**.

If the app is not signed in, `claude-add-account` refuses to save — a
signed-out snapshot could never be restored.

### Switch

- **Double-click** the **"Claude Switch Account"** icon on your Desktop, **or**
- run **`claude-switch-account`** in a standalone PowerShell window.

```
=== Switch Claude account ===
  [1] * you@example.com           5h  12% / 7d   8% used
        5h resets in 4h15m (21:49)   |   7d resets Sun Jun 7, 02:29
  [2]   work@example.com          5h  47% / 7d  31% used
  [3]   old@example.com           NEEDS RE-ADD (sign in to it, run claude-add-account)
  (* = current   |   lower % = more headroom)
```

Type the **number** and press Enter. Claude closes and reopens as that account.

> ⚠️ Run it from a **standalone** PowerShell window (or the Desktop shortcut),
> **not** from inside a Claude session — switching closes the desktop app.

---

## Claude Code (CLI)

### Add your accounts (one-time)

```powershell
claude-code-add
```

- The account you are already signed in to is kept as the first account —
  nothing to redo.
- For each further account, enter its email. A sign-in page opens in your
  browser — **approve it as that account**. If your browser is signed in to
  claude.ai as a different account, sign out there first or use a
  private/incognito window.

Each extra account gets its own folder, `~/.claude-cc-accounts/<email>/`, which
shares your transcripts, settings, plugins and skills with your main
`~/.claude` folder.

### Switch + continue your work

```powershell
claude-code-switch          # pick from the menu (shows usage; * = current)
claude-code-switch 2        # or pick by number
claude-code-switch me@x.com # or by email
claude --resume             # continue the same conversation on the new account
```

- **New** `claude` sessions use the account you picked.
- Sessions that are **already open keep their own account** — nothing is closed
  and nobody is logged out. You can run two accounts side by side.

> The switch applies to `claude` started from a terminal (PowerShell on
> Windows; bash/zsh on macOS/Linux). Claude Code inside the desktop app or an
> editor extension uses its own login and is not affected.

---

## Updating

```powershell
claude-switch-update
```

Pulls the latest version, then open a new terminal. When a newer version is
available, the switch menus show a one-line notice.

---

## How it works

**Claude Code CLI.** Anthropic's documented way to stay signed in to several
accounts is one configuration folder per account, selected with the
`CLAUDE_CONFIG_DIR` environment variable. The switcher sets that up for you:
`claude-code-add` creates a folder per account and runs `claude auth login`
inside it; `claude-code-switch` writes the chosen folder into
`~/.claude-cc-accounts/.active`; the `claude` wrapper reads that file and
starts the real `claude` with `CLAUDE_CONFIG_DIR` pointing there. Claude Code
keeps each login fresh by itself. The switcher only *reads* a token to show
usage.

**Desktop app.** The app is an Electron app — its login is a browser profile
(cookies, Local Storage, IndexedDB and an encrypted sign-in cache), not one
token file. `claude-add-account` closes Claude and snapshots that profile into
`~/.claude-accounts/<email>/profile/`. `claude-switch-account` closes Claude,
backs up the live profile (keeps the last backup), refreshes the snapshot of
the account you are leaving, restores the one you chose, and restarts the app.
Caches and the app's bundled Claude Code are not account state and are left
out, so snapshots are small.

---

## Uninstall

```powershell
irm https://raw.githubusercontent.com/karthiknl0/claude-account-switcher/main/uninstall.ps1 | iex
```

Removes the scripts, shortcuts and commands (including the `claude` wrapper —
`claude` then runs as the login in your normal `~/.claude` folder). It leaves
your saved accounts alone; remove them yourself if you want:

```powershell
Remove-Item -Recurse -Force ~/.claude-accounts       # desktop snapshots
Remove-Item -Recurse -Force ~/.claude-cc-accounts    # Claude Code account folders
```

---

## Notes & caveats

- **Use only accounts you own.** This is for moving between your own accounts,
  not sharing accounts or evading limits.
- **Desktop switching closes Claude.** The app must fully quit so its files
  unlock; the switcher waits for that, then reopens it.
- **Saved desktop snapshots are machine-bound.** They are encrypted with a
  Windows key tied to your user account. Don't copy `~/.claude-accounts` to
  another PC, and never commit it anywhere — it contains live login sessions.
- If a desktop switch leaves Claude in a weird state, your previous profile is
  in `~/.claude-accounts/.backup-<timestamp>/`.
- **Sign-in can still be required by Claude.** A server-side session expiry,
  security check, or organization policy cannot be bypassed locally. If an
  account shows "NOT signed in", run the matching add command for it again.
- **Many Claude Code sessions on one account** can still, rarely, sign that
  account out (a known Claude Code issue when two sessions renew the login at
  the same moment). `claude-code-add` with that email signs it back in.

## License

MIT — see [LICENSE](LICENSE).
