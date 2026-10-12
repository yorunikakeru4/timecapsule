# TimeCapsule — letters to the future

PHP-приложение лабораторных по cloud computing (ЛР2-ЛР3): регистрация, капсулы с датой открытия и вложениями, `/health` для мониторинга.

- **ЛР3 (продвинутый, NixOS + Amazon VPC):** [docs/lab3/README.md](docs/lab3/README.md)
- **ADR-0002 (размещение БД):** [docs/adr/0002-database-placement.md](docs/adr/0002-database-placement.md)
- **NixOS-конфигурации серверов:** [nixos/](nixos/)
- **Скрипты AWS (сеть, SG, NAT, Route 53, деплой):** [scripts/](scripts/)

## Deploy (вариант B)

```bash
ssh app ./deploy.sh
```

## Стек

nginx → PHP-FPM 8.4 (pdo_pgsql) → PostgreSQL 16. На серверах — NixOS 26.05 (официальный AMI, owner 427812963091).
