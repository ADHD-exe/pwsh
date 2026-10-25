# Progress report (checkpoint 8)

Done (static edits only; no PowerShell in this sandbox, nothing re-run - please test)
1. ROOT CAUSE of "Could not fast-forward", missing fonts, missing settings\git\ignore and the failing new terminal:
   30-repo.ps1 updated the shallow clone with `fetch --depth 1` + `merge --ff-only`. A depth-1 fetch drops the new
   commit's parents, so git can never prove the old HEAD is an ancestor: the fast-forward fails whenever the clone is
   behind. ~\.pwsh therefore stayed on an old commit (no fonts, no settings\git\ignore) and the new-terminal handoff
   launched that OLD Install-Environment.ps1, which has no -ResumeAfterPath parameter, so it failed every time.
   Fix: fetch + `reset --hard FETCH_HEAD` (only when the tree is clean, as before). If git still cannot update, the
   freshly downloaded files are copied over the install dir so ~\.pwsh and the download never diverge.
2. New-terminal handoff hardened (Relaunch.ps1): command is passed as -EncodedCommand (no wt.exe quoting / ';' issues),
   parameters are splatted from a hashtable, and any start-up error is printed and the window waits for Enter instead of
   vanishing. Install-Environment.ps1 refuses to launch a copy that lacks -ResumeAfterPath and verifies in-place instead.
3. Notepad++ / Everything configs are no longer skipped while the app runs. Originals are backed up (NAME.bak-<timestamp>)
   and replaced on the first run. Because those apps rewrite their config on exit, the installer first closes them
   GRACEFULLY (never killed; Everything via -quit), replaces the files, then reopens them. Only done when a file would
   actually change. If an app will not close, the file is still replaced and a warning explains it may be overwritten.
4. tests\Test-Relaunch.ps1 added (parses the generated handoff command with the real PowerShell parser) and wired into CI.

Still needs you
- Commit + push (settings\git\ignore and settings\fonts are tracked in this checkout; confirm they are on GitHub main)
- Re-run: irm .../install.ps1 | iex   (first run will update ~\.pwsh, install the fonts, deploy git\ignore)
- Check: the new wt window shows "Continuing in a new terminal"; if not, the red error text now stays on screen - send it to me
- Check Notepad++ / Everything reopen with the new settings

Earlier (checkpoint 7): openclaw removed; git step rewritten (skip what is done, SSH loop); handoff terminal added.
