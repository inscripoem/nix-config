# SiYuan on NixOS: workspace permissions & exit code 26

A downstream-adaptation log for the SiYuan note-taking app packaged in
`home/productivity/siyuan.nix`. The **configuration** lives there; this
file explains **why** the kernel binary is rebuilt from source with a
targeted `substituteInPlace` patch to vendored `gulu`, so a future
"clean up" doesn't quietly drop the patch and reintroduce the crash.

Package: **siyuan 3.7.1**, hybrid build — frontend/Electron layer
repackaged locally from the upstream `.deb` via `dpkg-deb --extract` +
`autoPatchelfHook` (same shape as `home/ai/cc-switch.nix` /
`home/ai/trae-cn.nix`); the **kernel binary** is built from source
with `buildGoModule` against the matching `v${version}` git tag and
symlinked over the one shipped in the `.deb`. See §4.

Upstream: <https://github.com/siyuan-note/siyuan>.

---

## 1. Symptom

**Every cold start after the very first one** shows this modal:

> 已成功避免潜在的数据损坏
> 工作空间下的文件正在被第三方软件（比如同步网盘、杀毒软件等）打开占用，
> 继续使用会导致数据损坏，思源内核已经安全退出。

and the kernel exits before the UI can render anything else. Very
first launch on a **freshly created workspace** succeeds; every
subsequent cold start fails; the app is effectively single-use.

A second, less obvious failure mode surfaces even *within a single UI
session*: switching appearance (theme / icon / language) or triggering
a bazaar reinstall makes the kernel `os.Exit(26)` mid-run, without any
kernel respawn line in `~/.config/siyuan/app.log`. Same root cause,
different trigger — the appearance HTTP handler re-runs the same
`filelock.Copy` code path documented below.

Two important not-facts that misled early diagnosis:

- There is **no** third-party software touching the workspace. No
  sync daemon, no antivirus, no other SiYuan process. `pgrep -a
  SiYuan-Kernel` is empty, `~/SiYuan/.lock` is a zero-byte stale
  file, no fd holds it.
- Passing `--workspace ~/SiYuan --lang zh-CN` on the command line
  does **not** help — the modal is not about argv.

## 1.1 Framing: adaptation, not upstream bug fix

Before the diagnosis: the patch documented in §4 is a **downstream
adaptation** for a specific interaction between three independently
correct designs, not a fix for an upstream bug. Upstream issue
trackers ([siyuan-note/siyuan](https://github.com/siyuan-note/siyuan/issues)
and [88250/gulu](https://github.com/88250/gulu)) carry no report of
this failure mode, and there is no reason to expect one.

- **SiYuan kernel view**: `os.Exit(26)` on detected permission
  anomalies is a deliberate data-protection shutdown, not a defect —
  it refuses to continue when the workspace looks unsafe.
- **gulu view**: `File.Copy` preserving `sourceinfo.Mode()` is
  standard POSIX copy semantics for a general-purpose file utility;
  hard-coding `0644` would break unrelated callers.
- **NixOS view**: `/nix/store` entries are mode `0444`/`0555` by
  design — the read-only, content-addressed store is the core
  guarantee of the platform.

All three are individually correct. The failure exists **only** at
their intersection (source of copy = a read-only store path), which
makes it the **packager's** responsibility to bridge, not any
upstream's to change. That is what §4 does.

## 2. Why it happens on NixOS — three interacting designs

### 2.1 App layer: `InitAppearance` runs on every boot

In `kernel/model/appearance.go` the kernel unconditionally copies its
built-in appearance assets from the install directory into the
workspace on every start:

```go
func InitAppearance() {
    ...
    from := filepath.Join(util.WorkingDir, "appearance")        // install dir
    if err := filelock.Copy(from, util.AppearancePath); err != nil { // workspace/conf/appearance
        util.ReportFileSysFatalError(err)
        return
    }
    ...
}
```

`ReportFileSysFatalError` maps to `os.Exit(26)` — the same exit code
the Electron `main.js` picks up and turns into the "third-party
software" modal via `main.js` line ~767:

```js
case 26:
    errorWindowId = showErrorWindow("已成功避免潜在的数据损坏", ...);
    break;
```

So the modal text is a **generic filesystem-fatal** fallback, not a
real diagnosis. Any filesystem-level fatal from the kernel becomes
this modal.

### 2.2 Library layer: `gulu.File.Copy` preserves source mode bits

`filelock.Copy` ultimately delegates to `github.com/88250/gulu`'s
`File.Copy`, whose per-file loop finishes with:

```go
os.Chmod(dest, sourceinfo.Mode())
```

i.e. the destination inherits the source file's permission bits
verbatim. On a normal (Debian/Windows/macOS) install the source is a
regular install directory owned by the user with `0644` / `0755`
files, so this is invisible. On NixOS the source is the Nix store.

### 2.3 Platform layer: Nix store is world-read, user-read-only

`resources/appearance/**/*` inside the store path
(`/nix/store/…-siyuan-3.7.1/opt/SiYuan/resources/appearance/`) has
mode `0444` for files and `0555` for directories, because everything
under `/nix/store` is intentionally immutable at the filesystem level.

Combining the three layers:

1. First cold start: workspace has no `conf/appearance/` yet. Kernel
   copies from store → workspace. Every destination file lands with
   mode `0444` (source mode faithfully preserved).
2. Second cold start: workspace already has `conf/appearance/`.
   Kernel opens each destination file with `O_WRONLY|O_TRUNC` to
   overwrite → `EACCES` → `ReportFileSysFatalError` → `os.Exit(26)`
   → modal.

Confirmed live evidence from running the kernel directly (bypassing
the Electron parent, so stderr is visible):

```
E file.go:406: open /home/inscripoem/SiYuan/conf/appearance/boot/index.html: permission denied
F filelock.go:91: copy [src=/nix/store/…/resources/appearance,
                        dest=/home/inscripoem/SiYuan/conf/appearance] failed:
                  open /home/inscripoem/SiYuan/conf/appearance/boot/index.html: permission denied
    github.com/siyuan-note/siyuan/kernel/model.InitAppearance()
        /home/d/88250/siyuan/kernel/model/appearance.go:43 +0x2ae
```

## 3. Why only `conf/appearance/`

The Nix store → workspace copy path exists in **exactly one place** in
the kernel: `InitAppearance`. Every other workspace-populating write
originates in user-writable territory:

- `data/`: created by the UI or restored from a repo/zip.
- `conf/conf.json`: written by `Conf.Save()` via `os.WriteFile`.
- `temp/`, `repo/`, `history/`: generated inside the workspace, so
  the source mode is already `0644`.
- `emoji/`, `snippets/`: user/UI generated.
- Bazaar (community themes/icons/plugins): unzipped from downloaded
  archives into a tempdir first, then `filelock.Copy` from there —
  source is user-writable, no store contamination.

So the adaptation scope is provably narrow: **only `conf/appearance/`**
carries the read-only contagion.

## 4. Downstream adaptation — source-level `gulu.File.Copy` patch

We build the SiYuan kernel from source and neutralise the offending
`os.Chmod(dest, sourceinfo.Mode())` line inside vendored `gulu` at
Go-module fetch time. This is the **only** patch we carry. See §4.1 below for
why we intentionally do **not** carry a runtime `chmod` shim as a
second line of defence.

### 4.1 Moving parts in `home/productivity/siyuan.nix`

- `srcTag` — `pkgs.fetchFromGitHub` of the matching `v${version}` git
  tag. Kept separate from `srcDeb` so upstream binary release and
  source release stay pinnable independently.
- `siyuan-kernel` — `pkgs.buildGoModule` with:
  - `sourceRoot = "${srcTag.name}/kernel"` — the git tree is a
    monorepo, only `kernel/` has `go.mod`.
  - `ldflags = [ "-s" "-w" "-X" "github.com/siyuan-note/siyuan/kernel/util.Mode=prod" ]`
    — matches upstream release build (see
    `kernel/util/working.go`'s `var Mode = "prod"`).
  - `tags = [ "fts5" ]` — required so `mattn/go-sqlite3` links the
    FTS5 module the kernel expects for full-text search.
  - `doCheck = false` — kernel `go test ./...` pulls in gosseract
    (OCR) tests that need `libtesseract` at test time and hit network
    for fixtures; we skip them entirely. Trade-off: if upstream lands
    a Go-level regression that only their own tests catch, our build
    still passes. Acceptable because we already end-to-end verify by
    launching the app; unit-test coverage is upstream's problem.
  - `modPostBuild` — runs inside the `goModules` fixed-output
    derivation, patches `vendor/github.com/88250/gulu/file.go`:

    ```bash
    chmod +w vendor/github.com/88250/gulu
    substituteInPlace vendor/github.com/88250/gulu/file.go \
        --replace-fail "os.Chmod(dest, sourceinfo.Mode())" \
                       "os.Chmod(dest, 0644)"
    ```

    `--replace-fail` makes the build fail loudly if upstream reworks
    that line — the wrong outcome is a silent no-op patch, so we
    prefer a hard fail that a human can adjudicate.
  - `postInstall` renames `bin/kernel` → `bin/SiYuan-Kernel` (matches
    the filename the Electron parent execs) and deletes
    `bin/harmony`, an 89 MB Harmony-OS variant the kernel Makefile
    also builds and that we have no consumer for.
- Assembly: `postFixup` in the outer derivation removes the kernel
  binary shipped in the `.deb` and symlinks
  `${siyuan-kernel}/bin/SiYuan-Kernel` in its place. Everything else
  from the `.deb` (Electron app, `pandoc`, resources, `.desktop`,
  icons) is kept as-is — no need to rebuild the frontend from source
  just to carry a NixOS-specific kernel patch.

Provenance is `[ binaryNativeCode fromSource ]` — hybrid.

### 4.2 Why we deliberately do **not** carry a prelaunch shim

An earlier iteration of this derivation wrapped `siyuan` in a bash
prelaunch shim that ran `chmod -R u+w "$ws/conf/appearance"` before
`exec siyuan`. It was originally introduced as belt-and-braces on top
of the source patch. We removed it deliberately, and adding it back
would be a regression. Reasoning:

- **The shim would mask silent patch failures.** If a future upgrade
  makes `--replace-fail` still succeed but the patched line no longer
  actually feeds every `gulu.File.Copy` call (e.g. upstream adds a
  new helper `copyFileWithPerms` and routes `InitAppearance` through
  it), the kernel would once again write `0444` files into
  `conf/appearance/`. A shim would then quietly `chmod` them back
  before each cold start, so the app keeps working and we never
  learn the patch is dead. The only remaining failure signal —
  mid-session theme switch crashing (see §1) — needs a human to
  manually trigger it and is easy to miss.
- **Without the shim, exit 26 on the second cold start is a loud,
  automatic canary.** The kernel writing `0444` into the workspace
  becomes visible on the very next launch, no user action required.
  This trades a small "app broken until human diagnoses" window for
  a much sharper feedback loop — worth it, because the diagnosis
  path is already written down in §8 and §9.3.
- **The shim's other supposed benefits are cheaper without it.**
  New store-source copy paths are surfaced by the `find` command in
  §6 step 3, so widening the patch is a reactive but adequate
  response. Filesystems that ignore POSIX modes (SMB, exFAT) never
  hit EACCES in the first place, so no defence is needed there.

If you disagree with this call, reintroduce the shim as its own
commit alongside a doc update flipping this section — do not sneak
it back "just in case".

### 4.3 Why we did not go j4ger's full-source route

`j4ger/nix-packages` builds the **entire** SiYuan app (Electron
frontend included) from source, using `pnpm` + `electron-builder`
inside a Nix derivation. That would eliminate the `.deb` dependency
and give us the gulu patch for free, but the frontend build:

- pulls in `pnpm` + Node.js of a specific version + a Chromium
  toolchain via `electron-builder`,
- ships its own `pandoc` binary that needs another Nix wrapper,
- rebuilds several hundred MB of JS on every version bump.

For a kernel-only downstream patch the hybrid `.deb`-frontend + source-kernel
shape is cheaper. If we ever need to patch frontend behaviour we
revisit this trade-off.

## 5. Cost

- One extra `os.Chmod(_, 0644)` syscall per file copied by
  `gulu.File.Copy`, versus upstream's `os.Chmod(_, sourceinfo.Mode())`.
  Same number of syscalls, different constant. Not measurable.
- Every SiYuan version bump requires re-deriving `vendorHash` (see
  §9). One human-in-the-loop probe per release.
- If upstream renames the patched line, `nix build` hard-fails at
  `substituteInPlace` — the intended, loud outcome (see §9.3).

## 6. Upgrading SiYuan

The `scripts/update-versions.sh siyuan` block now iterates three
hashes — `srcTag` (Git tag tarball), `vendorHash` (Go module set),
and the two `.deb` hashes — in that order. See §9 for the exact
flow and manual fallbacks.

**On every version bump, re-verify that `conf/appearance/` is still
the only Nix-store-sourced copy target.** Practically:

1. `nhs` to the new version.
2. `rm -rf ~/SiYuan-test && SIYUAN_WORKSPACE=~/SiYuan-test siyuan`,
   let it initialise, then close.
3. `find ~/SiYuan-test -not -perm -u+w -type f | head` — this must
   come back empty. Any hit is evidence that the source patch is
   **not** covering some new store-source copy path; extend
   `modPostBuild` (or add a companion patch) to reach that call site
   before shipping.
4. Open and close the app a few times, then switch theme once. No
   "数据损坏" modal on cold start **or** during the theme switch.

## 7. When to remove the source patch

Drop `modPostBuild` and revert to a plain `.deb`-shipped kernel once
**any** of the following becomes true:

- Upstream `88250/gulu` releases a version where `File.Copy` no
  longer calls `os.Chmod(dest, sourceinfo.Mode())` (or explicitly
  masks user-write back in), **and** SiYuan bumps to it. Track:
  <https://github.com/88250/gulu/blob/master/file.go>.
- Upstream SiYuan starts skipping `InitAppearance`'s copy when the
  destination already exists and is newer than the source (a
  reasonable optimisation they may land independently). Track:
  <https://github.com/siyuan-note/siyuan/blob/master/kernel/model/appearance.go>.

If either lands, verify by:

1. Applying the version bump **without** the patch (temporarily
   comment out `modPostBuild`).
2. Running the §6 checklist.
3. If clean, drop `modPostBuild`, `srcTag`, `siyuan-kernel`, and the
   `postFixup` symlink; the frontend `.deb` will ship a fixed kernel
   directly.

Until then, keep the patch.

## 8. If exit 26 comes back

The failing copy path may no longer be `conf/appearance/`, or the
patch may have silently stopped covering it. Order of suspicion:

1. Cold-start the kernel directly, outside Electron, with stderr
   attached:
   ```
   cd /nix/store/…-siyuan-3.7.1/opt/SiYuan/resources
   ./kernel/SiYuan-Kernel serve --port 45999 --workspace ~/SiYuan \
       --lang zh-CN --wd "$PWD" 2>&1 | tee /tmp/siyuan-kernel.log
   ```
   The last `F filelock.go` / `F …` line names the exact
   `dest=/…` path that failed.
2. If the failing dest is under `conf/appearance/`, the source patch
   itself has stopped working — jump to §9.3.
3. If the failing dest is elsewhere, upstream added a new
   store-sourced copy target. Widen `modPostBuild` (or add another
   `substituteInPlace` targeting the new call site), rebuild, retry.
4. If the log shows a *non-*EACCES fatal (e.g. `no such file`,
   `invalid argument`), it's not this class of failure — go read the
   specific kernel path that `ReportFileSysFatalError`'d.

Related exit codes for reference (all from `main.js`
`kernelProcess.on("close")`):

| Code | Modal title | Real cause |
|---|---|---|
| 20 | "数据库不可用" | SQLite open failed on `temp/siyuan.db` |
| 21 | "监听端口 X 失败" | Port bind failed |
| 24 | "工作空间已被锁定" | Another SiYuan-Kernel holds the flock |
| 25 | "初始化工作空间失败" | `os.MkdirAll` in `initWorkspaceDir` failed |
| **26** | **"已成功避免潜在的数据损坏"** | **Any filesystem fatal from a running kernel — the catch-all we hit** |
| other | "内核因未知原因退出 [code=N]" | Anything else, incl. Go panics (exit 2) |

## 9. Upgrade drill — three hashes, one script

`scripts/update-versions.sh siyuan` now walks three hashes in a fixed
order. Understanding the order matters for manual fallback when the
script fails mid-way.

### 9.1 Order and rationale

1. **`srcTag` hash** (`fetchFromGitHub`, git tree hash) — done first
   because both the vendored Go modules and the kernel build depend
   on the source tree being pinnable. The script uses
   `nix flake prefetch --json github:siyuan-note/siyuan/v${version}`
   and reads `.hash` from the JSON. This is the **git-tree** hash,
   not a tarball hash — do not paste an `sha256` from
   `nix-prefetch-url` here; `fetchFromGitHub` uses a different
   algorithm.
2. **`vendorHash`** (`buildGoModule` fixed-output derivation of
   `goModules`) — depends on `srcTag`, so it can only be probed
   after step 1. The script resets it to
   `sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=`, kicks off
   `nix build ... --impure --expr` filtering the home-manager
   packages list for the `siyuan` derivation, expects the build to
   fail with a hash mismatch, then greps the stderr for the `got:`
   line and rewrites the file with the real hash.
3. **`.deb` hashes** (both amd64 and arm64) — independent of the
   above two, done last so a failure in the frontend fetch doesn't
   invalidate a successfully derived `vendorHash`.

### 9.2 Manual fallback per step

If the script exits non-zero, run these by hand:

**srcTag hash**:

```
nix flake prefetch --json github:siyuan-note/siyuan/v${VERSION} \
  | jq -r '.hash'
```

Paste into the first `hash = "..."` line under `srcTag =`.

**vendorHash** (assumes `srcTag` is already correct):

1. Set `vendorHash = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";`
   in [siyuan.nix](file:///home/inscripoem/nix-config/home/productivity/siyuan.nix)
   manually.
2. `git add home/productivity/siyuan.nix` (flakes ignore untracked).
3. Trigger a build that reaches the `goModules` FOD:

   ```
   nix build --no-link --impure --expr \
     'let f = builtins.getFlake (toString ./.);
          m = f.homeConfigurations."inscripoem@briefcase".config.home.packages;
      in builtins.head (builtins.filter (p: p.pname or "" == "siyuan") m)' 2>&1 \
     | tee /tmp/siyuan-vendor.log
   ```

4. Grab the correct hash from the `got:` line:

   ```
   awk '/got:/{print $2; exit}' /tmp/siyuan-vendor.log
   ```

5. Paste that back into `vendorHash`.

**`.deb` hashes**: same as pre-source-build era — see the tail of
`scripts/update-versions.sh` for the exact `nix-prefetch-url` +
`nix hash convert` invocation.

### 9.3 When `--replace-fail` fires

If the vendor probe fails with

```
substituteInPlace: ERROR: pattern "os.Chmod(dest, sourceinfo.Mode())"
doesn't match anything in file "vendor/github.com/88250/gulu/file.go"
```

upstream `gulu` moved the offending line. Do **not** just delete the
`substituteInPlace` — that reintroduces the exit-26 failure mode. Instead:

1. `nix flake prefetch --json github:88250/gulu/${GULU_REV}` where
   `${GULU_REV}` is what the new SiYuan `kernel/go.mod` pins.
2. Read the new `file.go`, locate the equivalent `os.Chmod` line
   (upstream may have renamed the field or split the copy into a
   helper).
3. Rewrite the `--replace-fail` pattern to match.
4. If the offending call is gone entirely, celebrate briefly, remove
   the `modPostBuild` block, and start the two-version countdown in
   §7.
