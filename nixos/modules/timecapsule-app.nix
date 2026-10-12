# modules/timecapsule-app.nix — nginx + PHP-FPM 8.4 + PDO(pgsql) для приложения TimeCapsule.
# Приложение клонируется из git в /var/www/timecapsule (deploy.sh — git pull + init-db + reload).
{ config, lib, pkgs, ... }:
let
  appRoot = "/var/www/timecapsule";
  php = pkgs.php84.buildEnv {
    extensions = { enabled, all }: enabled ++ (with all; [ pdo_pgsql mbstring ]);
    extraConfig = ''
      upload_max_filesize = 6M
      post_max_size = 8M
    '';
  };
  nginxUser = config.services.nginx.user;
in
{
  services.phpfpm.pools.www = {
    user = nginxUser;
    phpPackage = php;
    settings = {
      "listen.owner" = nginxUser;
      "listen.group" = config.services.nginx.group;
      "listen.mode" = "0660";
      "pm" = "dynamic";
      "pm.max_children" = 5;
      "pm.start_servers" = 2;
      "pm.min_spare_servers" = 1;
      "pm.max_spare_servers" = 3;
      "catch_workers_output" = true;
    };
  };

  services.nginx = {
    enable = true;
    virtualHosts.timecapsule = {
      serverName = "_";
      root = "${appRoot}/public";
      extraConfig = ''
        index index.php;
        client_max_body_size 8M;
      '';

      locations."/" = {
        tryFiles = "$uri /index.php?$query_string";
      };

      # /health изолирован от основного приложения (задание 12, п.5):
      # отдельный fastcgi-скрипт отвечает, даже если index.php сломан.
      locations."= /health" = {
        extraConfig = ''
          include ${config.services.nginx.package}/conf/fastcgi_params;
          fastcgi_pass unix:${config.services.phpfpm.pools.www.socket};
          fastcgi_param SCRIPT_FILENAME ${appRoot}/public/health.php;
        '';
      };

      locations."~ \\.php$" = {
        extraConfig = ''
          try_files $uri =404;
          include ${config.services.nginx.package}/conf/fastcgi_params;
          fastcgi_pass unix:${config.services.phpfpm.pools.www.socket};
          fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
        '';
      };

      locations."~ /\\." = {
        extraConfig = "deny all;";
      };
    };
  };

  # Первичная раскладка: git clone (если нет) + .env (если нет) + права для nginx
  systemd.services.timecapsule-bootstrap = {
    description = "Bootstrap TimeCapsule app tree";
    wantedBy = [ "multi-user.target" ];
    after = [ "network-online.target" "postgresql.service" ];
    wants = [ "network-online.target" ];
    path = [ pkgs.git pkgs.coreutils pkgs.gnused ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      set -euo pipefail
      mkdir -p /var/www
      if [ ! -d ${appRoot}/.git ]; then
        git clone https://github.com/yorunikakeru4/timecapsule.git ${appRoot}
      fi
      mkdir -p ${appRoot}/storage/uploads
      if [ ! -f ${appRoot}/.env ]; then
        cp ${appRoot}/.env.example ${appRoot}/.env
        sed -i 's|^DB_HOST=.*|DB_HOST=db.timecapsule.internal|' ${appRoot}/.env
        sed -i 's|^DB_PASSWORD=.*|DB_PASSWORD=tc-app-pass-2026|' ${appRoot}/.env
        sed -i 's|^APP_URL=.*|APP_URL=http://localhost|' ${appRoot}/.env
      fi
      chown -R ${nginxUser}:${nginxUser} ${appRoot}
      chmod 640 ${appRoot}/.env || true
    '';
  };

  environment.systemPackages = with pkgs; [
    php
    postgresql_16  # psql/pg_dump на время миграции задания 12
  ];
}
