# Общая конфигурация для всех трёх хостов lab3 (официальный NixOS AMI, amazon-init).
{ config, lib, pkgs, modulesPath, ... }:
{
  imports = [
    # Совместимость с официальным NixOS AMI (EC2: nitro, ENA, grub)
    (modulesPath + "/virtualisation/amazon-image.nix")
  ];

  ec2.hvm = true;

  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  time.timeZone = "Europe/Chisinau";
  i18n.defaultLocale = "en_US.UTF-8";

  users.users.nixos = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
    openssh.authorizedKeys.keys = [
      (lib.removeSuffix "\n" (builtins.readFile ../ssh_key.pub))
    ];
  };

  security.sudo.wheelNeedsPassword = false;

  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
      PermitRootLogin = lib.mkForce "no";
    };
  };

  networking.firewall.enable = lib.mkDefault true;
  # SSH открыт через user-data/SG; остальное по умолчанию закрыто

  environment.systemPackages = with pkgs; [
    vim
    curl
    dnsutils
    git
    htop
    jq
  ];

  system.stateVersion = "26.05";
}
