# nix-openwrt-imagebuilder

Generate OpenWRT images from Nix derivations using the official
ImageBuilders that are provided upstream.

For OpenWRT releases since 19.07 there is profile helper functionality
that helps you find the proper image specification (target, variant)
according to your hardware's profile name.

## Background

In an ideal world, OpenWRT would be built from source in many
fine-grained Nix derivations. Until someone implements that (please
do!), this project exists to reuse the binary ImageBuilders that are
included in every OpenWRT release. They are only available for
x86_64-linux hosts.

The ImageBuilder can generate new *sysupgrade* images with a
customized set of packages and included files.

## Usage with vanilla Nix

```nix
let
  pkgs = import <nixpkgs> {};

  # use fetchurl, Hydra inputs, or something else to refer to this project
  openwrt-imagebuilder = ../nix-openwrt-imagebuilder;

  profiles = import (openwrt-imagebuilder + "/profiles.nix") { inherit pkgs; };

  # example: find target/variant for an old Fritzbox
  config = profiles.identifyProfile "avm_fritz7412" // {
    # add package to include in the image, ie. packages that you don't
    # want to install manually later
    packages = [ "tcpdump" ];

    disabledServices = [ "dnsmasq" ];

    # include files in the images.
    # to set UCI configuration, create a uci-defauts scripts as per
    # official OpenWRT ImageBuilder recommendation.
    files = pkgs.runCommand "image-files" {} ''
      mkdir -p $out/etc/uci-defaults
      cat > $out/etc/uci-defaults/99-custom <<EOF
      uci -q batch << EOI
      set system.@system[0].hostname='testap'
      commit
      EOI
      EOF
    '';
  };

in
  # actually build the image
  import (openwrt-imagebuilder + "/builder.nix") config
```

## Usage with Nix Flakes

```nix
{
  inputs = {
    openwrt-imagebuilder.url = "github:astro/nix-openwrt-imagebuilder";
  };
  outputs = { self, nixpkgs, openwrt-imagebuilder }: {
    packages.x86_64-linux.my-router =
      let
        pkgs = nixpkgs.legacyPackages.x86_64-linux;

        profiles = openwrt-imagebuilder.lib.profiles { inherit pkgs; };

        config = profiles.identifyProfile "avm_fritz7412" // {
          # add package to include in the image, ie. packages that you don't
          # want to install manually later
          packages = [ "tcpdump" ];

          disabledServices = [ "dnsmasq" ];

          # include files in the images.
          # to set UCI configuration, create a uci-defauts scripts as per
          # official OpenWRT ImageBuilder recommendation.
          files = pkgs.runCommand "image-files" {} ''
            mkdir -p $out/etc/uci-defaults
            cat > $out/etc/uci-defaults/99-custom <<EOF
            uci -q batch << EOI
            set system.@system[0].hostname='testap'
            commit
            EOI
            EOF
          '';
        };

      in
        openwrt-imagebuilder.lib.build config;
  };
}
```

## Identifying Profiles

The [`profiles`](/profiles.nix) interface demonstrated in the [vanilla
Nix](#usage-with-vanilla-nix) and [Nix Flakes](#usage-with-nix-flakes) examples
provides several functions for looking up OpenWrt image profiles:

### `identifyProfile`

The basic profile lookup function.  Takes a single argument, the name of the
device profile:

```nix
# OpenWrt profile for the AVM FRITZ!Box 7412
profiles.identifyProfile "avm_fritz7412"
```

If more than one profile matches the supplied name, this function returns the
first-matching profile.  If no profile matches the supplied, this function
throws an error.

### `identifyProfiles`

Like [`identifyProfile`](#identifyprofile), but returns a list of all matching
profiles.

### `identifyProfileWith`

An extended form of [`identifyProfile`](#identifyprofile) that takes three
named arguments: the required `profile`, the optional `target`, and the
optional `variant`:

```nix
# OpenWrt profile for an x86 device
profiles.identifyProfileWith {
  profile = "generic";
  target = "x86";
}
```

### `identifyProfilesWith`

Like [`identifyProfileWith`](#identifyprofilewith), but returns a list of all
matching profiles.


## Refreshing hashes

**downloads.openwrt.org** appears to be never at rest. That's why we
update the [cache subdirectory](./cache/) daily with [a Github
action.](https://github.com/astro/nix-openwrt-imagebuilder/actions/workflows/update-hashes.yml)

If you still encounter `hash mismatch in fixed-output derivation` in
between these updates, update them yourself:

```bash
nix run .#release2nix -- $(nix run .#list-versions -- -l)
```

If your `flake.nix` has this project in its `inputs`, then you can
build with your local working copy using
`nix build --override-input openwrt-imagebuilder git+file:///... .#...`
