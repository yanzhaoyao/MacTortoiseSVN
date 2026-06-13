# MacSVNQuickActions

Quick Actions fallback for Finder integration.

Current bridge:

- `MacSVNQuickActions` is a small executable packaged under `MacTortoiseSVN.app/Contents/Resources/bin/`.
- It accepts a command name followed by file paths, writes a `MacSVNWorkbenchCommand`, and launches the main app.
- Supported command names: `open`, `commit`, `diff`, and `refresh`.

Expected responsibilities:

- expose critical commands when Finder Sync menu integration is unreliable
- forward actions to the main app or the background service

This target exists to keep core SVN actions reachable on newer macOS releases where Finder behavior changes.
