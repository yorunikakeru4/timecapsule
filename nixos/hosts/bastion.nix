# hosts/bastion.nix — единственный SSH-точка входа в VPC (задания 4-5).
{ config, pkgs, ... }:
{
  networking.firewall.allowedTCPPorts = [ 22 ];

  # Никаких лишних сервисов: bastion — jump host, не приложение
  services.openssh.openFirewall = true;

  environment.systemPackages = with pkgs; [ tcpdump ];
}
