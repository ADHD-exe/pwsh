# Progress report (checkpoint 7)

Done (static edits only; no PowerShell in this sandbox, nothing re-run - please test)
1. openclaw removed: packages.psd1 (NpmGlobals now only claude-code), `oc` alias now just runs opencode, README.
2. Git step (55-git.ps1) rewritten so each part is checked first and skipped if already done:
   - git-lfs filters, user.name, user.email: only set/asked when missing (email is now ASKED, no more noreply guess)
   - SSH: tested first (silent, any key/agent); if it already works nothing else happens
   - if not working: key created only if absent, public key SHOWN (+ clipboard, add-key page), big "DO NOT CONTINUE" notice, and the installer LOOPS until GitHub accepts the key. Typing SKIP is the only way past it.
   - https->ssh rewrite only set if not already set
   - new -GitEmail parameter (and -GitUser) are used only if git has no value yet
3. After the PATH step the installer opens a NEW terminal (wt.exe new window, plain pwsh window as fallback) that runs only verification (-ResumeAfterPath), rebuilds PATH from the registry first, then leaves you in your configured shell. -NoRelaunch / -Unattended / -WhatIf keep everything in the current window. Runs the permanent copy in ~\.pwsh, not the temp download.
4. Already idempotent (audited, unchanged): repo, packages, modules, profile, terminal, configs, path.
Earlier (checkpoint 6): keybinds guard, verify false-positive, fonts non-fatal, npm diagnostics.

Still needs you
- Commit + push everything (incl. settings/git/ignore), then run on a throwaway VM / re-run on DeathStar
- Add settings\fonts (.ttf) or install a Nerd Font manually
- Check: does the new wt window open and show "Continuing in a new terminal"?
