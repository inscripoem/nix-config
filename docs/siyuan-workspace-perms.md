# SiYuan workspace permissions

[pkgs/siyuan.nix](../pkgs/siyuan.nix) repackages the upstream Electron frontend
and builds the matching kernel from source. A patch to vendored `gulu` keeps
copied workspace files writable. [The HM module](../home/desktop/siyuan.nix)
only installs the package.

## Failure and fix

The original failure appeared after the first successful workspace launch,
and could also occur when switching themes. SiYuan exited with code 26 and
showed “已成功避免潜在的数据损坏”. That message reports a filesystem failure;
it does not establish that another application holds the workspace open.

SiYuan copies built-in appearance assets into `conf/appearance/`. The source
assets live in the read-only Nix store, and `gulu.File.Copy` preserves their
mode. A subsequent copy can then fail when opening the read-only destination.

The kernel's `modPostBuild` changes:

```go
os.Chmod(dest, sourceinfo.Mode())
```

to `os.Chmod(dest, 0644)`. `--replace-fail` stops the build if upstream changes
the patched expression. This affects file copies through that vendored helper,
so upgrades must check callers as well as whether the patch still applies.

The frontend remains the upstream `.deb`; rebuilding only the kernel limits
the packaging work. Kernel tests are disabled because their fixtures require
additional OCR dependencies and network access; a successful build therefore
needs application-level verification.

## Kernel build details

`buildGoModule` first creates a separate `goModules` derivation, runs
`go mod vendor`, and then runs `modPostBuild` before copying the vendor tree
to that derivation's output. The SiYuan patch therefore becomes part of the
dependency tree used by the kernel build. Patching a vendor directory before
it is generated, or one that the kernel build later replaces from `goModules`,
would not provide the same result.

`vendorHash` covers that patched tree, not just `go.mod` or the downloaded
modules. Recompute it when changing the dependency set or patch. A successful
text replacement only proves the expression was found; it does not prove all
appearance-copy paths still use that helper.

| Build setting | Reason |
|---|---|
| Matching `srcTag` and `.deb` version | Keep the rebuilt kernel compatible with the packaged frontend |
| `sourceRoot = "${srcTag.name}/kernel"` | Build from the Go module inside the upstream monorepo |
| `tags = [ "fts5" ]` | Include SQLite FTS5 support required for full-text search |
| `util.Mode=prod` linker setting | Match the production kernel mode |
| Rename `kernel` to `SiYuan-Kernel` | Match the executable name expected by the frontend |
| Replace the `.deb` kernel with a symlink | Make Electron launch the patched kernel instead of the bundled one |

The extra `harmony` binary is removed because this desktop package does not
use it. If upstream changes the build outputs or frontend launch path, review
the rename and replacement together. A startup permission-repair wrapper would
miss theme changes within a running session and hide patch regressions on
subsequent cold starts. Keep the cold-start and theme-switch checks below.

## Updating

Run on a Linux build machine with the updater's dependencies available:

```sh
just update siyuan --dry-run
just update siyuan
```

The direct script form is `./scripts/update-versions.sh --only=siyuan`.
It updates `pkgs/siyuan.nix`, fetching the source-tree hash and both `.deb`
hashes, then probing the Go `vendorHash`. It expects a hash-mismatch build
while discovering that last value. If interrupted, inspect the file for a
placeholder hash or partial update before continuing.

Review the patch against the new `gulu` source and run the repository's required
package checks:

```sh
nix build --no-link --dry-run .#nixosConfigurations.briefcase.config.system.build.toplevel
```

To build just the packaged application from the NixOS HM package list:

```sh
nix build --no-link --print-out-paths --impure --expr '
  let
    f = builtins.getFlake (toString ./.);
    packages = f.nixosConfigurations.briefcase.config.home-manager.users.inscripoem.home.packages;
  in builtins.head (builtins.filter (p: p.pname or "" == "siyuan") packages)
'
```

If the updater fails, distinguish the three hash inputs before repairing it:

| Input | Recovery |
|---|---|
| `srcTag.hash` | Prefetch the matching GitHub source tree; this is a recursive source hash |
| `.deb` hashes | Use the matching release asset checksums; these hash the archive bytes |
| `vendorHash` | Probe the patched Go dependency output after fixing the source version/hash |

For example, set `siyuan_version` to the version being packaged and prefetch
its source with:

```sh
nix flake prefetch --json "github:siyuan-note/siyuan/v${siyuan_version}" | jq -r '.hash'
```

For a manual `vendorHash` repair, temporarily set it to `lib.fakeHash`'s value,
`"sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="`, in `pkgs/siyuan.nix`.
Run the application build above and use the `got:` value only if the failed
derivation is the expected Go modules hash mismatch. Do not copy a source or
`.deb` mismatch into `vendorHash`.

If `--replace-fail` cannot find `os.Chmod(dest, sourceinfo.Mode())`, inspect the
`gulu` revision selected by the new `kernel/go.mod` and follow its file-copy
implementation. Update the patch to the equivalent operation, or test whether
upstream now handles the permissions correctly without it. Rebuild after the
repair; removing the failed substitution alone does not establish a fix.

After installing the new version, close existing SiYuan instances and create a
disposable workspace directory:

```sh
siyuan_test_workspace=$(mktemp -d "$HOME/SiYuan-test.XXXXXX")
printf '%s\n' "$siyuan_test_workspace"
```

Select that directory through SiYuan's workspace picker. The package wrapper
does not implement a `SIYUAN_WORKSPACE` environment variable.
Close and reopen that same workspace, then switch themes. Check for unwritable
files with `find "$siyuan_test_workspace" -type f ! -perm -u+w`. Investigate
unexpected results before using the new package with the main workspace.

## If exit 26 returns

Close other SiYuan instances. Use the disposable workspace created above, or a
backed-up copy that reproduces the failure. On Linux, launch the installed
kernel directly and capture its output:

```bash
(
  set -euo pipefail
  siyuan_package=$(dirname "$(dirname "$(readlink -f "$(command -v siyuan)")")")
  siyuan_resources="$siyuan_package/opt/SiYuan/resources"
  test -d "$siyuan_resources/appearance"
  test -d "$siyuan_test_workspace"
  siyuan_kernel_log=$(mktemp "$HOME/siyuan-kernel-log.XXXXXX")
  printf 'Kernel log: %s\n' "$siyuan_kernel_log"
  "$siyuan_resources/kernel/SiYuan-Kernel" serve \
    --port 45999 --workspace "$siyuan_test_workspace" \
    --lang en --wd "$siyuan_resources" 2>&1 | tee "$siyuan_kernel_log"
)
```

Choose an unused port; if the kernel starts successfully, stop it with Ctrl-C
before reopening the desktop app. `--wd` explicitly supplies the packaged
resources because the kernel executable itself is a symlink to a separate
store output. The command uses the CLI in SiYuan 3.8.2; check `serve --help`
when upgrading it.

Read the final filesystem error and its destination path:

- A permission error under `conf/appearance/`: check ownership, file modes,
  whether the frontend uses the patched kernel, and whether the copy still
  reaches the patched helper.
- A permission error elsewhere: inspect that copy path before extending the
  patch. Do not recursively change the whole workspace's permissions as a
  substitute for finding the failing operation.
- A non-permission error: follow that error's path and cause. Code 24 reports
  a workspace lock and is distinct from the generic filesystem failure at 26.

## Removing the patch

Revisit the patch when the packaged `gulu` stops copying read-only source modes,
or SiYuan changes its appearance-copy path so the failure no longer occurs.
Test the candidate version without the patch on a fresh workspace: first start,
subsequent cold starts, and a theme switch must all work with writable assets.

If the upstream `.deb` kernel also passes those checks and no other local kernel
changes remain, remove `modPostBuild`, `srcTag`, `siyuan-kernel`, and the
`postFixup` kernel replacement together. Removing only the source build while
leaving its replacement symlink would break packaging.

References: [SiYuan](https://github.com/siyuan-note/siyuan),
[gulu file operations](https://github.com/88250/gulu/blob/master/file.go),
[SiYuan 3.8.2 serve command](https://github.com/siyuan-note/siyuan/blob/v3.8.2/kernel/cli/cmd/serve.go).
