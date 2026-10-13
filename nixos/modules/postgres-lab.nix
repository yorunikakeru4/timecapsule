# modules/postgres-lab.nix — PostgreSQL 16 на db-server.
# Слушает все интерфейсы; pg_hba пускает только подсеть public-a (10.X.0.0/24) по scram-sha-256.
{ config, lib, pkgs, ... }:
let
  # X = k % 30 (k=11 → X=11); подставить свой X
  x = 11;
  publicASubnet = "10.${toString x}.0.0/24";
in
{
  services.postgresql = {
    enable = true;
    package = pkgs.postgresql_16;
    enableTCPIP = true;
    settings = {
      listen_addresses = "*";
      password_encryption = "scram-sha-256";
    };
    # Три механизма защиты из лабы: маршрут+адрес (нет IGW/NAT), db-sg (5432 только от web-sg),
    # и этот pg_hba. Ошибка только в одном = дыра.
    authentication = lib.mkForce ''
      # TYPE  DATABASE  USER  ADDRESS         METHOD
      local   all       all                   peer
      host    all       all   127.0.0.1/32    scram-sha-256
      host    all       all   ${publicASubnet} scram-sha-256
    '';
    # Инициализация при первом старте кластера (задания 6 и 10)
    initialScript = pkgs.writeText "lab3-init.sql" ''
      CREATE USER student WITH PASSWORD 'lab3-student-pass';
      CREATE DATABASE lab3 OWNER student;
      CREATE USER timecapsule WITH PASSWORD 'tc-app-pass-2026';
      CREATE DATABASE timecapsule OWNER timecapsule;
    '';
  };

  # Логи ошибок БД — в journalctl -u postgresql
  services.postgresql.settings.log_min_messages = "warning";
}
