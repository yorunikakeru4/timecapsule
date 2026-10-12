# hosts/app.nix — сервер приложения в public-a (+ Elastic IP).
{ config, pkgs, ... }:
{
  networking.firewall.allowedTCPPorts = [ 80 22 ];
}
