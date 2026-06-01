# Claude Account Switcher

Switch between multiple **Anthropic Claude** accounts (e.g. several Pro/Max
accounts you own) on Windows — pick one from a quick menu and the **Claude
desktop app** restarts logged into it.

The Claude desktop app has no built-in account switcher. This saves each
account's login and swaps it on demand, with a Desktop shortcut for one-click
switching and a usage readout so you can see which account has headroom.
**No npm required** (Node.js only enables the optional usage display).

---

## Quick start

```powershell
# 1. Install (run once, in PowerShell)
irm https://raw.githubusercontent.com/karthiknl0/claude-account-switcher/main/install.ps1 | iex

# 2. Open a NEW PowerShell window, then save each account (see "Add your accounts")
claude-add-account

# 3. Switch any time
claude-switch-account
```

> **Requires:** Windows and the [Claude desktop app](https://claude.ai/download).

---

## Step 1 — Install

Open **PowerShell** and run:

```powershell
irm https://raw.githubusercontent.com/karthiknl0/claude-account-switcher/main/install.ps1 | iex
```

This installs:

- `~/.claude-tools/claude-switch.ps1` and `claude-add.ps1`
- `claude-switch-account`, `claude-add-account`, `claude-switch-update` commands
  in your PowerShell profiles
- a **"Claude Switch Account"** shortcut on your Desktop

**Then open a new PowerShell window** so the commands load.

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
  [2]   work@example.com          5h  47% / 7d  31% used
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
