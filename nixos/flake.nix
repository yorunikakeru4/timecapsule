{
  description = "ЛР3: NixOS-хосты timecapsule-dev (bastion / app / db) для AWS VPC";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";

  outputs = { self, nixpkgs }: {
    nixosConfigurations = {
      bastion = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          ./modules/common.nix
          ./hosts/bastion.nix
        ];
      };

      app = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          ./modules/common.nix
          ./modules/timecapsule-app.nix
          ./hosts/app.nix
        ];
      };

      db = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          ./modules/common.nix
          ./modules/postgres-lab.nix
          ./hosts/db.nix
        ];
      };
    };
  };
}
