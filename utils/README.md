# utils

Standalone Termux/PRoot maintenance scripts for `udroid` guest environments.

These scripts are independent of the `udroid-extra-tool-proot` submodule's own
`utils/` Python package (a separate repository providing VNC, clipboard, and
upgrade helpers used by the `udroid` CLI). This local `utils/` directory holds
ad-hoc Bash tooling that isn't wired into the `udroid` CLI and must be run
manually from inside a Termux/PRoot session.

## ius_accelerated_v2.sh

A single-pass mass package installer/categorizer for Debian/Ubuntu `apt`
package indexes. It scans `apt-cache dumpavail` once, buckets available
packages into categories (compute/drivers, compilers & runtimes, science,
security/sandboxing tools, UI/rendering, admin utilities) based on keyword
matching, then installs the matched packages in adaptive batches with
automatic conflict resolution (keeping whichever of two conflicting packages
has more reverse-dependencies) and a 32GB free-space safety buffer check
before starting.

**Usage** (run inside Termux or the PRoot Ubuntu guest, as the appropriate user):

```bash
bash utils/ius_accelerated_v2.sh
```

Logs are written to `$HOME/ius_accelerated_<timestamp>.log`, per-category
package lists to `$HOME/ius_categories/`, and packages that failed to install
to `$HOME/failed_pkgs.txt`.

**Caution:** this script installs a very large, keyword-matched surface of
packages (including networking/security tooling such as `nmap`, `hydra`,
`aircrack-ng`, `metasploit`-adjacent packages if present in configured repos).
Review the category files it generates before/while it runs if you want to
audit or prune what gets installed, and only run it in environments where
mass package installation is intended and permitted.
