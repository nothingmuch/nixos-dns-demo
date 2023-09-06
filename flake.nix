{
  description = "vm with unbound configured to use blocklists and stuff";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-23.05";

    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = {
    self,
    nixpkgs,
    flake-utils,
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
                    ];

                    virtualisation.graphics = false;

                    # Avoid lengthy build of the nixos manual
                    documentation.nixos.enable = false;

                    nixpkgs.pkgs = pkgs;
                    services.getty.autologinUser = "root";
                    nix.nixPath = ["nixpkgs=${nixpkgs}"];

                    services.getty.helpLine = lib.mkAfter ''
                      OH HAI!
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
