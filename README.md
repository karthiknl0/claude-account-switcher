# Claude Account Switcher

[![CI](https://github.com/karthiknl0/claude-account-switcher/actions/workflows/ci.yml/badge.svg)](https://github.com/karthiknl0/claude-account-switcher/actions/workflows/ci.yml)

Switch between several **Claude** accounts you own (for example two Pro/Max
accounts) and **keep working where you left off** when one hits its limit.

| | Windows | macOS | Linux |
|---|:---:|:---:|:---:|
| **Claude Code** (`claude` in the terminal) | ✅ | ✅ | ✅ |
| **Claude desktop app** | ✅ | — | — |

No npm needed. Nothing is uploaded anywhere — everything stays on your computer.

**Contents:** [Set up](#set-up-once) · [Everyday use](#everyday-use) ·
[When you hit a limit](#when-you-hit-a-limit) · [All commands](#all-commands) ·
[What carries over](#what-carries-over-between-accounts) ·
[Troubleshooting](#troubleshooting) · [Upgrading from 3.x](#upgrading-from-3x) ·
[How it works](#how-it-works) · [Uninstall](#uninstall)

---

## Set up (once)

### 1. Install

**Windows** — open **PowerShell** and paste:

```powershell
irm https://raw.githubusercontent.com/karthiknl0/claude-account-switcher/main/install.ps1 | iex
```

**macOS / Linux** — needs [PowerShell](https://aka.ms/powershell) installed:

```bash
pwsh -c "irm https://raw.githubusercontent.com/karthiknl0/claude-account-switcher/main/install.ps1 | iex"
```

Then **open a new terminal window** so the commands load.

### 2. Add your Claude Code accounts

```powershell
claude-code-add
```

- The account you are already signed in to is kept — nothing to redo.
- For every other account, type its email. A sign-in page opens in your
  browser: **approve it as that account**. If the browser is signed in to
  claude.ai as a different account, sign out there first or use a
  private/incognito window.

### 3. Add your desktop app accounts (Windows)

> ⚠️ **Never use the app's "Log out" while doing this.** Logging out ends that
> account's session on Anthropic's side and kills the saved copy.
> `claude-add-account` clears the login locally for you instead.

1. Sign in to your first account in the Claude desktop app.
2. Run `claude-add-account` and confirm the account it detected. The app
   closes briefly and reopens.
3. Answer **`y`** to "Add ANOTHER account now?" — the app reopens at a sign-in
   screen (your first account is *not* logged out).
4. Sign in as the next account and run `claude-add-account` again. Repeat.
5. Answer **`n`** after the last account.

### 4. Check it

```powershell
claude-code-doctor
```

Shows every saved account and whether it is signed in. It only reads.

### 5. Recommended: turn on the usage status line

```powershell
claude-code-statusline on
```

Claude Code then shows, at the bottom of every session:

```
you@example.com | Opus | ctx 42% | 5h 61% (resets 21:49) | 7d 30%
```

and warns you when it is time to act (see [When you hit a limit](#when-you-hit-a-limit)).

---

## Everyday use

### Claude Code

```powershell
claude-code-switch            # pick from a menu (shows usage; * = current)
claude-code-switch 2          # or by number
claude-code-switch me@x.com   # or by email
claude --resume               # continue the same conversation on the new account
```

- **New** `claude` sessions use the account you picked.
- Sessions that are **already open keep their own account** — nothing closes,
  nobody is logged out. You can run two accounts side by side.
- Applies to `claude` started from a terminal. Claude Code inside the desktop
  app or an editor extension uses its own login.

### Desktop app (Windows)

Double-click **"Claude Switch Account"** on your Desktop, or run
`claude-switch-account` in a PowerShell window:

```
=== Switch Claude account ===
  [1] * you@example.com           5h  12% / 7d   8% used
        5h resets in 4h15m (21:49)   |   7d resets Sun Jun 7, 02:29
  [2]   work@example.com          5h  47% / 7d  31% used
  (* = current   |   lower % = more headroom)
```

Type the number. Claude closes, reopens as that account, and the switcher
**confirms** the switch worked. If Claude rejected the saved sign-in, it tells
you and offers to put you back on the account you were on.

> ⚠️ Run it from its own PowerShell window or the Desktop shortcut — **not**
> from inside a Claude session. Switching has to close the app for a few
> seconds.

---

## When you hit a limit

Your work is on your computer, not inside one account, so you can carry on
with another account. One thing to know: **the new account has to read the
whole conversation once**, and on a long session that uses up a chunk of its
5-hour limit. Do this to keep that small:

**Best — before the limit runs out** (the status line tells you when):

```
>> 5h limit close: type /compact soon, then claude-code-switch to carry on cheaply | you@example.com | ...
```

1. In Claude Code, type **`/compact`**. On the account you are still on this is
   cheap, and it shrinks the conversation to a short summary.
2. Run **`claude-code-switch`** and pick another account.
3. Run **`claude --resume`** and continue.

**If you are already blocked:**

1. Run `claude-code-switch`, pick another account, then `claude --resume`.
2. If Claude Code offers **"resume from summary"**, choose it.
3. Or start a new session and ask it to continue from the previous one — it
   reads only what it needs.

**When the first account's limit resets**, switch back the same way. It sees
everything the other account did, because both wrote to the same conversation
and the same project files.

---

## All commands

| Command | What it does |
|---|---|
| `claude-code-add` | Add / re-sign-in a Claude Code account |
| `claude-code-switch` | Choose which account `claude` runs as |
| `claude-code-statusline on` / `off` | Show account + usage in Claude Code, with "compact now" advice |
| `claude-add-account` | Save the account signed in to the desktop app *(Windows)* |
| `claude-switch-account` | Switch the desktop app to another saved account *(Windows)* |
| `claude-code-doctor` | Check the setup (read-only) — run this first when something looks wrong |
| `claude-switch-cleanup` | Show disk use; remove leftovers from older versions (asks first) |
| `claude-switch-update` | Update to the latest version (then open a new terminal) |

---

## What carries over between accounts

| | Carries over? | How |
|---|:---:|---|
| **Claude Code sessions** (terminal) | ✅ | All accounts share the same transcripts. Switch, then `claude --resume`. |
| **Desktop app — Code tab sessions** | ✅ | On every `claude-switch-account`, the other accounts' sessions are added to the sidebar of the account you switch to. |
| **Your project files** | ✅ | They are ordinary files in your project folder. |
| **Desktop app — regular chats** | ❌ | These live in each account on Anthropic's servers, not on your PC. To move one, ask Claude for a summary and paste it into a new chat on the other account. |

Details of the Code-tab sharing: it only **adds** list entries — nothing an
account already has is changed, sessions you deleted stay deleted, and no
sign-in data is copied. An account that has never opened the Code tab gets the
list from its second switch onwards. To turn it off, create an empty file
`~/.claude-accounts/.no-session-share`.

---

## Storage

Disk use does not grow as you switch:

- Each desktop account has **one saved copy**, overwritten with its latest
  data on every switch.
- There is **one backup** (the profile that was live before the last switch),
  also overwritten every time.
- A saved login is protected during that overwrite: a copy is only refreshed
  from a session verified to belong to that account, and the switch is
  cancelled if the refreshed copy no longer contains the sign-in.
- Claude Code accounts keep **no copies** — each account is just its own
  signed-in folder; transcripts are shared, not duplicated.

Run `claude-switch-cleanup` to see how much space is used and to remove
leftovers from older versions.

---

## Troubleshooting

Always start with **`claude-code-doctor`** — it names the problem.

| You see | Do this |
|---|---|
| A command is "not recognized" | Open a **new** terminal window. Still missing? Run the install line again. |
| An account shows **NOT signed in** (Claude Code) | `claude-code-add`, enter that email, sign in again. |
| An account shows **NEEDS RE-ADD** (desktop) | Sign in to it in the desktop app, then `claude-add-account`. |
| Desktop app opens at a sign-in screen after a switch | Anthropic ended that saved session. Accept the offer to go back, then re-add that account as above. |
| `claude` still runs as the old account | You are in a session that was already open — start a new one. In a new terminal, `claude-code-doctor` shows the active account (`*`). |
| Sign-in page signs in the **wrong** account | Your browser is logged in to claude.ai as another account. Sign out there or use a private window, then `claude-code-add` again. |
| Status line does not appear | It shows after your first message in a **new** session. If you already had your own status line, it is left untouched. |
| Code-tab sidebar is empty after a switch | That account has not used the Code tab yet — open it once, then it fills from the next switch. |
| Disk use looks high | `claude-switch-cleanup` |

**After a Claude update breaks something:** run `claude-switch-update` first.
The switcher is tested automatically every week against the newest Claude Code,
so a fix is usually already there. If not, please
[open an issue](https://github.com/karthiknl0/claude-account-switcher/issues)
and paste the output of `claude-code-doctor` (it never prints a token).

---

## Upgrading from 3.x

Versions 3.x stopped working in 2026 ("it logs me out" / "it doesn't switch")
because Claude changed two things. Version 4 is built around both:

| What changed in Claude | What 4.x does |
|---|---|
| **Claude Code** replaces its sign-in token every time it renews it, so a saved copy of a token goes dead. | Each account signs in **once in its own folder** and stays signed in there. Switching only changes which folder `claude` uses — no token is ever copied. |
| **Claude desktop** (Windows Store build) moved its data to `%LOCALAPPDATA%\Claude-Data\`. | Finds the folder the app really uses, and never saves or restores a signed-out profile. |

Do this **once** after updating:

```powershell
claude-switch-update      # then open a NEW PowerShell window
claude-code-add           # keeps your current login; sign each other account in once
claude-add-account        # desktop app: sign in to each account and save it again
claude-code-doctor        # check
claude-switch-cleanup     # optional: remove what 3.x left behind
```

---

## How it works

**Claude Code.** Anthropic's documented way to stay signed in to several
accounts is one configuration folder per account, selected with the
`CLAUDE_CONFIG_DIR` environment variable. `claude-code-add` creates a folder
per account (`~/.claude-cc-accounts/<email>/`, sharing transcripts, settings,
plugins and skills with `~/.claude`) and signs in there. `claude-code-switch`
records the chosen folder; a small `claude` wrapper in your shell profile
starts the real `claude` with that folder. Claude Code keeps each login fresh
by itself. The switcher only *reads* a token to show usage.

**Desktop app.** The app's login is a browser-style profile (cookies, local
storage and an encrypted sign-in cache), not one token file.
`claude-add-account` saves that profile; `claude-switch-account` closes the
app, backs up the live profile, refreshes the saved copy of the account you
are leaving, loads the one you chose, restarts the app and verifies the
result. Caches and the app's bundled Claude Code are left out.

**Built to survive Claude updates.**

- It asks the running app where its data folder is and remembers the answer,
  so another folder move is followed automatically.
- If a newer Claude stores its sign-in differently, you get a confirmation
  question instead of a dead end; if the quick sign-in command changes,
  `claude-code-add` signs in inside Claude Code instead.
- Every change is tested on Windows (PowerShell 5.1 and 7), macOS and Linux,
  and once a week against the newest Claude Code release.

What no tool can do: keep an account signed in after Anthropic ends that
session, or predict a complete redesign of the apps. In those cases the
switcher says what happened and what to run — it does not fail silently.

---

## Uninstall

```powershell
irm https://raw.githubusercontent.com/karthiknl0/claude-account-switcher/main/uninstall.ps1 | iex
```

Removes the scripts, shortcuts, commands and the status line entry. `claude`
then runs as the login in your normal `~/.claude` folder again. Your saved
accounts are left alone; delete them yourself if you want:

```powershell
Remove-Item -Recurse -Force ~/.claude-accounts       # desktop copies
Remove-Item -Recurse -Force ~/.claude-cc-accounts    # Claude Code account folders
```

---

## Good to know

- **Use only accounts you own.** This is for moving between your own accounts,
  not for sharing accounts.
- **Saved desktop copies only work on the PC they were made on** (they are
  encrypted with a Windows key tied to your user). Don't copy
  `~/.claude-accounts` elsewhere and never upload it — it contains live logins.
- **Anthropic can still ask you to sign in again** (session expiry, security
  check, organisation policy). No local tool can prevent that; just re-add the
  account.
- **Many Claude Code sessions on one account at once** can, rarely, sign that
  account out (a known Claude Code issue). `claude-code-add` with that email
  signs it back in.
- This is an unofficial community tool, not made or supported by Anthropic.

## License

MIT — see [LICENSE](LICENSE).
