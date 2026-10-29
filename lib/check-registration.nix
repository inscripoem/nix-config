# Registration-completeness and class-usage audit, evaluated from ground truth.
#
# Unlike a text-level grep over imports lists, this forces the *actual*
# `imports` field of every manifest-style default.nix (lazily — only that
# field), so comments, string blocks and interpolation tricks can neither
# fake nor hide a registration. A module whose `imports` depended on module
# arguments would fail loudly here (all arguments are passed as null)
# instead of being silently missed — that is the intended direction.
#
# It also audits the class directories under modules/nixos/: each must be
# claimed by at least one host's `classes` list (read from the real
# nixosHosts table in outputs/default.nix) or be listed in reservedClasses.
#
# Consumed via the flake output `moduleRegistration` (outputs/default.nix)
# and enforced by `just lint-modules` (scripts/check-module-registration.sh).
#
# NOTE on inputs: outputs/default.nix is called with `{ self = src; }` and
# only its lazily-evaluated `nixosHosts` field is ever forced. The host
# table is pure literals, so no flake input is touched; if a future edit
# makes it force an input, this audit fails with an attribute-missing error
# — fail-loud, never a silent miss.
{ lib, src, inputs ? { } }:
let
  # Directories whose default.nix is a manifest of local module files/dirs.
  manifestDirs = [
    "modules/nixos/base"
    "modules/nixos/capabilities"
    "modules/nixos/desktop"
    "modules/darwin/base"
    "home/packs"
    "home/core"
    "home/desktop"
    "home/tui"
  ];

  # Class directories deliberately left unclaimed by any host, with the
  # reason each stays reserved. When the first real server host lands it
  # will claim "server"; the staleReserved result then fails this audit
  # until the whitelist entry is removed.
  reservedClasses = [
    {
      name = "public";
      reason = "planned internet-facing hardening class; module is a TODO placeholder";
    }
    {
      name = "server";
      reason = "server posture (stable kernel, panic tuning) kept for the first managed server host";
    }
  ];

  # Directories under modules/nixos/ that are structure, not classes.
  structuralClasses = [ "base" "capabilities" "desktop" ];

  # The `imports` of a module at `path`. Module arguments that match a flake
  # input name get the real input (e.g. impermanence.nix imports
  # inputs.impermanence.nixosModules.*); everything else is null, and an
  # imports expression forcing such an argument fails loudly instead of
  # silently degrading the audit. Laziness keeps everything except `imports`
  # unevaluated.
  importsOf = path:
    let
      f = import path;
      mod = if builtins.isFunction f
        then f (builtins.mapAttrs (name: _:
          # `inputs` in specialArgs is the whole flake-inputs attrset.
          if name == "inputs" then inputs
          else if inputs ? ${name} then inputs.${name}
          else null)
          (builtins.functionArgs f))
        else f;
    in map (p:
      # Local registrations are paths (or path strings). Anything else — e.g.
      # a lambda module from a flake input — cannot name a local file; mark
      # it so the candidate filter drops it.
      if builtins.isPath p || builtins.isString p
      then baseNameOf (toString p)
      else "\0nonpath") (mod.imports or [ ]);

  checkDir = dir:
    let
      root = src + "/${dir}";
      entries = builtins.readDir root;
      # Local candidates: module files and module directories (with a
      # default.nix). Everything else (assets, plugin trees) is ignored.
      candidates = lib.filter (n: n != null) (lib.mapAttrsToList
        (n: t:
          if t == "regular" && lib.hasSuffix ".nix" n && n != "default.nix" then n
          else if t == "directory" && builtins.pathExists (root + "/${n}/default.nix") then n
          else null)
        entries);

      # Transitive closure of local names reachable from default.nix.
      # Cross-directory references (../foo.nix) resolve to names outside the
      # candidate list and are simply not followed; those files belong to
      # their own directory's audit.
      walk = seen: name:
        if lib.elem name seen
        then seen
        else
          let
            path = if lib.hasSuffix ".nix" name
              then root + "/${name}"
              else root + "/${name}/default.nix";
            next = builtins.filter (n: lib.elem n candidates) (importsOf path);
          in builtins.foldl' walk (seen ++ [ name ]) next;
      reachable = builtins.foldl' walk [ ]
        (builtins.filter (n: lib.elem n candidates) (importsOf (root + "/default.nix")));

      missing = lib.filter (n: !(lib.elem n reachable)) candidates;
    in {
      inherit dir candidates missing;
      ok = missing == [ ];
    };

  moduleChecks = map checkDir manifestDirs;

  # Class audit over the real host table.
  outputsFn = import (src + "/outputs/default.nix");
  hostTable = (outputsFn (builtins.mapAttrs (name: _:
    # Every named input except `self` must stay unforced while reading the
    # (pure-literal) host table; forcing one means outputs/default.nix grew
    # an input dependency into nixosHosts — fix that instead of wiring
    # inputs in here.
    if name == "self" then src
    else throw "moduleRegistration: outputs/default.nix forced flake input '${name}' while evaluating nixosHosts")
    (builtins.functionArgs outputsFn))).nixosHosts;
  allClasses = lib.unique (lib.flatten
    (lib.mapAttrsToList (_: s: s.classes or [ ]) hostTable));
  classDirs = builtins.attrNames
    (lib.filterAttrs (_: t: t == "directory") (builtins.readDir (src + "/modules/nixos")));
  nonStructural = lib.subtractLists structuralClasses classDirs;
  audit = {
    claimed = lib.filter (c: lib.elem c allClasses) nonStructural;
    # Whitelist entries no longer needed: the class got claimed — remove it.
    staleReserved = lib.filter (r: lib.elem r.name allClasses) reservedClasses;
    # Unclaimed and not whitelisted: either add a host or reserve it here.
    unused = lib.filter (d:
      !(lib.elem d allClasses)
      && !(lib.elem d (map (r: r.name) reservedClasses))) nonStructural;
    # A host references a class that has no directory at all.
    missingDirs = lib.filter (c: !(lib.elem c classDirs)) allClasses;
  };
in {
  ok = (lib.all (c: c.ok) moduleChecks)
    && audit.staleReserved == [ ]
    && audit.unused == [ ]
    && audit.missingDirs == [ ];
  modules = map (c: {
    inherit (c) dir candidates missing;
  }) moduleChecks;
  classes = {
    claimed = audit.claimed;
    reserved = map (r: { inherit (r) name reason; })
      (lib.filter (r: !(lib.elem r audit.staleReserved)) reservedClasses);
    staleReserved = map (r: r.name) audit.staleReserved;
    inherit (audit) unused missingDirs;
  };
}
