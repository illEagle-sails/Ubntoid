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

## app_backend_deploy.sh

A **pre-installation, device-specific dependency optimizer**. Unlike
`ius_accelerated_v2.sh`, this script does not build or compile anything — it
only profiles the current device and provisions the narrow set of C/
Objective-C toolchain, GPU/NPU header, memory-abstraction, and display-probe
packages that actually match that device's hardware, before any real
install/build step runs.

Device-profiling phase (written to `$HOME/device_profile.env`):
- **CPU**: architecture (`uname -m`) and core count (`nproc`)
- **RAM**: total memory from `/proc/meminfo`, used to scale the free-space
  safety buffer down on lower-RAM devices instead of always requiring 32GB
- **Display**: resolution via `termux-api`'s `termux-display-info` when
  installed, falling back to the framebuffer's `virtual_size`, else `unknown`
- **GPU**: vendor EGL/Vulkan driver name via `getprop ro.hardware.egl` /
  `ro.hardware.vulkan`, plus a Vulkan-availability check
- **NPU**: best-effort detection via `getprop` hints (`npu`, `hexagon`,
  `neuralnetworks`, `edgetpu`, `apu`) and vendor HAL library presence
- **Model/SoC**: `ro.product.model` / `ro.board.platform`

After profiling, the script filters the apt-derived dependency list so that,
for example, GPU/Vulkan header packages are only installed if a GPU/Vulkan
driver was actually detected, and display-probe packages are only installed
if a display was actually detected — so the exact same script installs a
different, fitted dependency set depending on which device it runs on.

**Usage:**

```bash
bash utils/app_backend_deploy.sh
```

This intentionally stops after dependency provisioning (no `make`/build
step) — its output (`$HOME/device_profile.env` and the populated
`$HOME/app_dependencies/` category files) is meant to be consumed by a
separate, later build/install step.
