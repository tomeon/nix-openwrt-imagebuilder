{ pkgs ? import <nixpkgs> {}
, lib ? pkgs.lib
, openwrtLib ? import ./openwrt-lib.nix { inherit lib; }
# OpenWRT release
, release ? openwrtLib.latestRelease
# Manually specify packages' arch for OpenWRT<19 releases without profiles.json
, packagesArch ? throw "packagesArch must be given for OpenWRT<19 releases"
# Users may supply their own fresh hashes
, cachePath ? openwrtLib.getCachePath release
}:

let
  # Workaround for direct calls without the pkgs overlay from flake.nix.
  pkgs' =
    if pkgs ? packages2nix && pkgs ? callPackages2nix
    then pkgs
    else pkgs.extend (final: prev: {
      packages2nix = final.callPackage ./packages2nix.nix { };
      callPackages2nix = final.callPackage ./call-packages2nix.nix { };
    });

  hashes = openwrtLib.getCachedRelease release cachePath;

in rec {
  allProfiles =
    builtins.mapAttrs (target: variants:
      lib.filterAttrs (_: profiles:
        profiles != null
      ) (
        builtins.mapAttrs (variant: h:
          (import ./cached-packages.nix {
            inherit openwrtLib release target variant packagesArch cachePath;
          }).profiles
        ) variants
      )
    ) hashes.targets;

  # filters hardware profiles from all boards.json files
  identifyProfilesWith =
    {
      target ? null,
      variant ? null,
      profile,
    }:
    let
      targets =
        if target == null then
          builtins.attrNames allProfiles
        else
          lib.filter (lib.flip lib.hasAttr allProfiles) (lib.toList target);
    in
    builtins.concatMap (
      target:
      let
        allVariants = allProfiles.${target};
        variants =
          if variant == null then
            builtins.attrNames allVariants
          else
            lib.filter (lib.flip lib.hasAttr allVariants) (lib.toList variant);
      in
      map (variant: {
        # match return value
        inherit lib openwrtLib release target variant profile cachePath;
        pkgs = pkgs';
      }) (builtins.filter (variant: allProfiles.${target}.${variant}.profiles ? ${profile}) variants)
    ) targets;

  identifyProfileWith =
    {
      target ? null,
      variant ? null,
      profile,
    }:
    let
      matches = identifyProfilesWith { inherit target variant profile; };
    in
      if builtins.length matches == 1
      then builtins.head matches
      else if matches == []
      then throw "No match for OpenWRT profile ${profile}"
      else builtins.trace ''
        ${builtins.length matches} matches for OpenWRT profile ${profile}
        ${lib.concatMapStrings ({ target, variant }: ''
        - ${target}/${variant}
        '') matches}
        Using first.
      '' (builtins.head matches);

  identifyProfiles = profile: identifyProfilesWith { inherit profile; };

  identifyProfile = profile: identifyProfileWith { inherit profile; };
}
