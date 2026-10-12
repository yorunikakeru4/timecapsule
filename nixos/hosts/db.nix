# hosts/db.nix — сервер базы данных в private-a.
{ config, lib, pkgs, ... }:
{
  # 5432/22 фильтрует Security Group db-sg (AWS), не локальный firewall:
  # оставляем firewall без TCP-портов, чтобы не перекрывать логику SG.
  networking.firewall.enable = lib.mkForce false;

  environment.systemPackages = with pkgs; [
    config.services.postgresql.package  # psql, pg_dump
  ];
}
