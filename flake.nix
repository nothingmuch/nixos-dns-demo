{
  description = "vm with unbound configured to use blocklists and stuff";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-23.05";

    flake-utils.url = "github:numtide/flake-utils";

    # duplicate this as a separate input, so it's updated
    adblockStevenBlack = {
      url = "github:StevenBlack/hosts";
      flake = false;
    };

    # a flake which compiles adlists to unbound configs
    adblock-unbound = {
      url = "github:MayNiklas/nixos-adblock-unbound";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        adblockStevenBlack.follows = "adblockStevenBlack";
      };
    };
  };

  outputs = {
    self,
    nixpkgs,
    flake-utils,
    adblock-unbound,
    ...
  }:
    flake-utils.lib.eachDefaultSystem (
      system: let
        pkgs = nixpkgs.legacyPackages.${system};
      in {
        packages = {
          # cribbed from nix-bitcoin examples, MIT license
          default =
            rec {
              mkVMScript = vm:
                pkgs.writers.writeBash "run-vm" ''
                  set -euo pipefail
                  export TMPDIR=$(mktemp -d /tmp/demo-vm.XXX)
                  trap 'rm -rf $TMPDIR' EXIT
                  export NIX_DISK_IMAGE=$TMPDIR/nixos.qcow2

                  # shellcheck disable=SC2211
                  QEMU_OPTS="-smp $(nproc) -m 1500" ${vm}/bin/run-*-vm
                '';

              vm =
                (import (nixpkgs + "/nixos") {
                  inherit system;
                  configuration = {
                    config,
                    lib,
                    modulesPath,
                    ...
                  }: {
                    imports = [
                      (modulesPath + "/virtualisation/qemu-vm.nix")

                      ({pkgs, ...}: let
                        adlist = adblock-unbound.packages.${pkgs.system};
                      in {
                        services.unbound = {
                          enable = true;
                          settings = {
                            server = {
                              include = [''"${adlist.unbound-adblockStevenBlack}"''];
                            };
                            remote-control.control-enable = true;
                          };
                        };
                      })
                    ];

                    virtualisation.graphics = false;

                    # Avoid lengthy build of the nixos manual
                    documentation.nixos.enable = false;

                    nixpkgs.pkgs = pkgs;
                    services.getty.autologinUser = "root";
                    nix.nixPath = ["nixpkgs=${nixpkgs}"];

                    services.getty.helpLine = lib.mkAfter ''
                      OH HAI!

                      Unbound is enabled and configured as the local resolver.

                      Use the host command to make queries. Try comparing some
                      queries using the local resolver vs. say quad 1:

                          > host ads.google.com
                          > host ads.google.com 1.1.1.1

                      The blocklist is included from:

                          ${adblock-unbound.packages.${pkgs.system}.unbound-adblockStevenBlack}
                    '';

                    # Power off VM when the user exits the shell
                    systemd.services."serial-getty@".preStop = ''
                      echo o >/proc/sysrq-trigger
                    '';

                    system.stateVersion = lib.mkDefault config.system.nixos.release;
                  };
                })
                .config
                .system
                .build
                .vm;

              runVM = mkVMScript vm;
            }
            .runVM;
        };

        apps.default = {
          type = "app";
          program = "${self.packages.${system}.default}";
        };

        formatter = pkgs.alejandra;
      }
    );
}
