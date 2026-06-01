# Claude Account Switcher

Switch between multiple **Anthropic Claude** accounts (e.g. several Pro/Max
accounts you own) on Windows — pick an account from a quick menu and the
**Claude desktop app** restarts logged into it.

The Claude desktop app has no built-in account dropdown. This swaps the active
login token and restarts the app, plus a Desktop shortcut so it's a double-click.
**No npm required.**

---

## Install (one line)

Open **PowerShell** and run:

```powershell
irm https://raw.githubusercontent.com/karthiknl0/claude-account-switcher/main/install.ps1 | iex
```

This installs:

- `~/.claude-tools/claude-switch.ps1`, `claude-add.ps1`
- `claude-switch-account` / `claude-add-account` commands in your PowerShell profiles
- a **"Claude Switch Account"** shortcut on your Desktop

> **Requires:** Windows and the [Claude desktop app](https://claude.ai/download).
> Open a new PowerShell window after installing so the commands load.

---

## Add your accounts

For each account:

1. Log into it in the Claude desktop app (account menu → **Log out**, then sign
   in as that account).
2. Save its session (this **closes** Claude, copies the session, then reopens it):

   ```powershell
   claude-add-account
   ```

   Enter that account's email when prompted.

Repeat for as many accounts as you want.

---

## Switching accounts

- Double-click **"Claude Switch Account"** on your Desktop, or
- run **`claude-switch-account`** in a **standalone** PowerShell window.

Pick an account → Claude **fully closes**, the saved session is swapped in, and
the app reopens logged into the chosen account.

> ⚠️ **Run it from a standalone PowerShell window**, not from inside a Claude
> session — switching force-closes the Claude desktop app to swap its session.

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
