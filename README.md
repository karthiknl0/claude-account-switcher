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

For each account: log into it in the Claude app (account menu → **Log out**, then
sign in as that account), then save it:

```powershell
claude-add-account
```

Repeat for as many accounts as you want.

---

## Switching accounts

- Double-click **"Claude Switch Account"** on your Desktop, or
- run **`claude-switch-account`** in a **standalone** PowerShell window.

Pick an account → the Claude desktop app closes and reopens logged into it.

The picker also shows each account's **usage** (5-hour and 7-day % used, queried
from Anthropic's OAuth usage endpoint) so you can see which account has headroom
before switching. Tokens expire ~hourly; an account whose cached token has
expired shows `usage n/a` until you next switch to it.

> ⚠️ **Run it from a standalone PowerShell window**, not from inside a Claude
> session — switching closes the Claude desktop app to reload the login. The
> displayed email can take a few seconds to refresh after a switch; usage always
> counts against the swapped account.

---

## How it works

Claude stores its login token in `~/.claude/.credentials.json`, which the desktop
app reads at startup. The switcher keeps a copy of each account's token and swaps
the active one, then restarts the app (it auto-detects the Claude Store app, so
it survives updates).

It is deliberately **minimal and safe**:

- swaps **only** the `claudeAiOauth` token block (your `mcpOAuth` is preserved);
- **never edits** `~/.claude/.claude.json`, so your settings, MCP servers and
  history are untouched;
- backs up the previous credentials to `~/.claude-accounts/backup-<timestamp>.credentials.json`
  before every switch.

There is no live in-app switch — the menu is the "dropdown", and the app reflects
whichever account is active after the restart.

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
- Saved tokens are stored in plaintext locally (same as how the app already
  stores `~/.claude/.credentials.json`). Keep your machine secured; never commit
  `~/.claude-accounts` anywhere.

## License

MIT — see [LICENSE](LICENSE).
