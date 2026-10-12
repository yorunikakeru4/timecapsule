# Лабораторная работа №3. Облачные сети. Amazon VPC (NixOS edition)

| | |
|---|---|
| **Студент** | Croitor Alexandr (Кройтор Александр) |
| **Группа** | IA2403 |
| **Специальность** | Informatică aplicată |
| **k / X** | k = 3, X = k % 30 = **3** → диапазон VPC `10.3.0.0/16` |
| **Уровень** | **Продвинутый** (Часть 1: зад. 1–7 + Часть 2: зад. 8–14) |
| **Репозиторий** | <https://github.com/yorunikakeru4/timecapsule> |
| **Регион** | `eu-central-1` (Frankfurt) |

> **Ключевое отличие от «базового» выполнения.** Все серверы — **NixOS** со стабильного канала `26.05`, AMI берётся из **официального реестра образов EC2** (Account ID `427812963091`, публичные AMI проекта NixOS; см. <https://nixos.github.io/amis/>), а не Amazon Linux 2023. Конфигурацияbastion/app/db описана декларативно во flake (`nixos/flake.nix`), инфраструктура AWS — скриптами на AWS CLI (`scripts/`). Вместо «сделать AMI с веб-сервера ЛР2» (задание 8) состояние сервера воспроизводится из git: `nixos-rebuild switch --flake .#app` — образ как снимок диска больше не нужен, дегистрировать и удалять нечего.
>
> Ключевой пар (как в ЛР2): `~/.ssh/croitor.a-kepair.pem` (в AWS — key pair `croitor.a-kepair`). Все скрипты ниже используют его же.

---

## Содержание

- [Что построено](#что-построено)
- [Часть 1. Базовый уровень](#часть-1-базовый-уровень)
  - [Задание 1. План адресов](#задание-1-план-адресов)
  - [Задание 2. VPC и подсети](#задание-2-vpc-и-подсети)
  - [Задание 3. Internet Gateway и таблицы маршрутов](#задание-3-internet-gateway-и-таблицы-маршрутов)
  - [Задание 4. Security Group](#задание-4-security-group)
  - [Задание 5. Экземпляры](#задание-5-экземпляры)
  - [Задание 6. Временный NAT Gateway](#задание-6-временный-nat-gateway)
  - [Задание 7. Проверки](#задание-7-проверки)
- [Часть 2. Продвинутый уровень](#часть-2-продвинутый-уровень)
  - [Задание 8. Перенос сервера ЛР2 в новую сеть](#задание-8-перенос-сервера-лр2-в-новую-сеть)
  - [Задание 9. Elastic IP](#задание-9-elastic-ip)
  - [Задание 10. База данных приложения на db-server](#задание-10-база-данных-приложения-на-db-server)
  - [Задание 11. Приватная зона Route 53](#задание-11-приватная-зона-route-53)
  - [Задание 12. Перенос данных и переключение приложения](#задание-12-перенос-данных-и-переключение-приложения)
  - [Задание 13. Деплой и обслуживание](#задание-13-деплой-и-обслуживание)
  - [Задание 14. Архитектура и решение](#задание-14-архитектура-и-решение)
- [Запуск с нуля одной командой](#запуск-с-нуля-одной-командой)
- [Ответы на контрольные вопросы](#ответы-на-контрольные-вопросы)
- [Итог: состояние после завершения](#итог-состояние-после-завершения)

---

## Что построено

![Схема сети лабораторной работы](images/architecture.svg)

*Рис. 1. Сеть `timecapsule-dev-vpc`. NixOS-серверы, временный NAT (пунктир), приватная Route 53.*

Компоненты и как они созданы:

| Слой | Ресурс | Как создан | Где в репо |
|---|---|---|---|
| Сеть | VPC, 4 подсети, IGW, 2 rt | `scripts/01-network.sh` | — |
| Фильтрация | bastion-sg / web-sg / db-sg | `scripts/02-security-groups.sh` | — |
| Интернет для private-* | NAT GW + EIP (временный) | `scripts/03-nat-up.sh` / `10-nat-down.sh` | `.state/nat.env` (gitignore) |
| Серверы | bastion, app, db на **NixOS 26.05** | `scripts/04-launch-instances.sh` (AMI из EC2 registry, owner `427812963091`) | `nixos/` |
| Конфигурация ОС | nginx+PHP8.4+PDO(pgsql) / PostgreSQL 16 / openssh | `nixos-rebuild switch --flake .#{bastion,app,db}` (`scripts/05-deploy-nixos.sh`) | `nixos/{flake.nix,modules,hosts}` |
| Приложение | TimeCapsule (PHP, свой, без composer-зависимостей) | git clone + `deploy.sh` | `app/` |
| DNS | приватная зона `timecapsule.internal`, A `db` | `scripts/06-route53.sh` | — |
| Постоянный адрес | Elastic IP `timecapsule-dev-app-eip` | `scripts/07-eip-app.sh` | — |
| Данные | pg_dump → psql по DNS-имени | `scripts/08-migrate-data.sh` | — |

Все скрипты берут k/X/пароли из `scripts/env.sh` (одна точка правки). Состояние созданных ресурсов пишется в `scripts/.state/` и в `.gitignore`.

---

## Часть 1. Базовый уровень

### Задание 1. План адресов

X = 3 → все диапазоны считаются из `10.3.0.0/16` (пересчитать под свой k: правьте `K` в `env.sh`).

| Подсеть | Зона доступности | Диапазон | Первый и последний адрес, доступный экземплярам | Сколько адресов доступно |
|---|---|---|---|---|
| `public-a` | `eu-central-1a` | `10.3.0.0/24` | `10.3.0.4` — `10.3.0.254` | 251 |
| `public-b` | `eu-central-1b` | `10.3.1.0/24` | `10.3.1.4` — `10.3.1.254` | 251 |
| `private-a` | `eu-central-1a` | `10.3.10.0/24` | `10.3.10.4` — `10.3.10.254` | 251 |
| `private-b` | `eu-central-1b` | `10.3.11.0/24` | `10.3.11.4` — `10.3.11.254` | 251 |

**Почему не 256?** AWS резервирует в каждой подсети **4 адреса**: `.0` (адрес сети), `.1` (шлюз сети — точка маршрутизации подсети), `.2` (резерв, используется службами AWS, например DHCP) и последний `.255` (broadcast). Экземплярам доступны оставшиеся **251** адрес.

**Сколько ещё `/24` поместится в VPC?** VPC — `/16`, то есть 256 подсетей `/24`. Заняты 4 → свободно **252** (при том, что схема нумерации с «дырками» между 0/1 и 10/11 оставляет место для будущих групп).

### Задание 2. VPC и подсети

Скрипт: [`scripts/01-network.sh`](scripts/01-network.sh) — создаёт VPC only, включает `Enable DNS resolution` **и** `Enable DNS hostnames` (второе критично для приватной зоны Route 53 в задании 11), затем все 4 подсети с обязательными тегами (`Name`, `Project`, `Environment`, `Owner`, `Lab`).

```bash
cd scripts && ./01-network.sh
# == > Создаю VPC timecapsule-dev-vpc (10.3.0.0/16)
# == > Включаю DNS resolution и DNS hostnames (нужно для Route 53 приватной зоны)
# == > Создаю 4 подсети в двух зонах доступности
# ...
```

Вместе с VPC AWS создал main route table, NACL и default SG — в задании они не используются: каждая подсеть явно привязана к своей таблице маршрутов.

> **Является ли `public-a` сейчас публичной? Почему?**
> Нет. Публичность подсети — это не имя, а **маршрут к Internet Gateway в её таблице маршрутов** плюс возможность получить публичный IP. До задания 3 в `public-rt` нет маршрута `0.0.0.0/0 → igw`, и auto-assign public IP выключен: подсеть называется «public», но из неё нельзя выйти в интернет и к экземпляру нельзя прийти снаружи. Имя — план, маршрут — факт.

### Задание 3. Internet Gateway и таблицы маршрутов

Там же, в `01-network.sh`: IGW создаётся в состоянии `Detached`, сразу `attach-internet-gateway`, создаются:

- `timecapsule-dev-public-rt` — маршрут `0.0.0.0/0 → timecapsule-dev-igw`, ассоциации с `public-a` и `public-b`;
- `timecapsule-dev-private-rt` — **без маршрутов в интернет**, ассоциации с `private-a` и `private-b`;
- для `public-a`/`public-b` включён `Enable auto-assign public IPv4 address`.

Проверка (задание 3 — скриншот в консоли `VPC → Route tables`; эквивалентный вывод команды):

```text
# aws ec2 describe-route-tables ... --output table
|       Name        |                    Routes                    |
|-------------------+----------------------------------------------|
| timecapsule-...-public-rt  | 10.3.0.0/16 → local ; 0.0.0.0/0 → igw-... |
| timecapsule-...-private-rt | 10.3.0.0/16 → local                       |
```

> **Какой маршрут есть в обеих таблицах, хотя вы его не добавляли? Что он даёт?**
> `10.3.0.0/16 → local`. Его AWS создаёт автоматически: он направляет весь трафик внутри VPC (между подсетями и зонами) на «локальную» маршрутизацию хостинга AWS. Он даёт связь `public-a ↔ private-a ↔ public-b ↔ private-b` без шлюзов — именно поэтому app из `public-a` достучится до db в `private-a` без NAT/IGW.
>
> **Куда уйдёт пакет из `private-a`, адресованный `8.8.8.8`?**
> Таблица `private-rt` содержит только `10.3.0.0/16 → local` — пакет в маршруте **не найдёт** и будет отброшен (destination unreachable). Даже SG и pg_hba не при чём: сначала решает таблица маршрутов. Именно поэтому `curl` с db-server падает: добавить `0.0.0.0/0 → nat-...` — и тот же пакет уйдёт через NAT в public-a → igw.

### Задание 4. Security Group

Скрипт [`scripts/02-security-groups.sh`](scripts/02-security-groups.sh) создаёт группы **в правильном порядке** (источник-группа доступна только после создания):

| Группа | Входящее | Источник | Зачем |
|---|---|---|---|
| `bastion-sg` | SSH 22 | `$(curl checkip.amazonaws.com)/32` | администратор → bastion |
| `web-sg` | HTTP 80 | `0.0.0.0/0` | пользователи → сайт |
| `web-sg` | SSH 22 | `bastion-sg` | SSH только через bastion |
| `db-sg` | PostgreSQL 5432 | `web-sg` | к базе — только приложение |
| `db-sg` | SSH 22 | `bastion-sg` | SSH на db только через bastion |

Исходящие — по умолчанию (все разрешены): серверы могут сами инициировать соединения.

> **Почему в `db-sg` источником указана группа `web-sg`, а не адрес или `10.3.0.0/16`?**
> Security Group ссылается на **другую SG**, а не на IP: правило «автоматически следует» за всеми инстансами в `web-sg` — при пересоздании app-server с новым IP ничего править не нужно, и ошибка «забыли обновить ACL после миграции» исключена. Диапазон `10.3.0.0/16` слишком широк: туда входят и bastion, и будущие серверы в public-подсетях. Конкретный IP хрупок при stop/start (пока не привязан EIP). Группа — это привязка к роли, а не к сетевому местоположению.

### Задание 5. Экземпляры

Скрипт [`scripts/04-launch-instances.sh`](scripts/04-launch-instances.sh):

| Роль | Имя | Подсеть | Публичный IP | SG | AMI |
|---|---|---|---|---|---|
| bastion | `timecapsule-dev-bastion` | public-b | enable | bastion-sg | NixOS 26.05 |
| web/app | `timecapsule-dev-app` | public-a | enable | web-sg | NixOS 26.05 |
| db | `timecapsule-dev-db` | private-a | **disable** | db-sg | NixOS 26.05 |

**Образ из реестра.** В `env.sh` зафиксирован свежий публичный AMI стабильного канала:

```text
NIXOS_AMI_OWNER=427812963091          # официальный AWS-аккаунт проекта NixOS
NIXOS_AMI_ID=ami-09d5cc1e26dea7c81
NIXOS_AMI_NAME=nixos/26.05.10620.f5c082a40f75-x86_64-linux
```

Свежий ID на любой момент: `scripts/find-nixos-ami.sh` (запрашивает `describe-images` у owner `427812963091` с фильтром `nixos/26.05*`). Образы публикуются еженедельно и вычищаются через 90 дней — поэтому ID не «захардкожен навсегда», а вычисляется.

**Вместо user-data с `dnf install nginx`** NixOS AMI понимает user-data как **выражение NixOS-модуля** (модуль `amazon-init`): скрипт генерирует модуль, инжектирующий наш ssh-ключ пользователю `nixos`. Полная конфигурация (nginx, PHP-FPM, PostgreSQL) накатывается затем flake'ом — это и есть «конфигурация через NixOS» из условия работы.

```nix
# фрагмент генерируемого user-data
{ lib, pkgs, ... }:
{
  users.users.nixos.openssh.authorizedKeys.keys = [ "ssh-ed25519 AAAA... lab3" ];
  services.openssh.enable = true;
  networking.firewall.allowedTCPPorts = [ 22 ];
}
```

Сайт (аналог «страницы web-server»): после `scripts/05-deploy-nixos.sh` открывается `http://<public-IP app-server>` — страница TimeCapsule; `/health` возвращает JSON.

**Подключение через bastion.** Скрипт [`scripts/update-ssh-config.sh`](scripts/update-ssh-config.sh) дописывает в `~/.ssh/config` блок (публичный IP bastion перечитывается при каждом запуске — после stop/start просто перезапустите скрипт):

```text
Host bastion
    HostName <публичный IP bastion>
    User nixos
    IdentityFile ~/.ssh/croitor.a-kepair.pem

Host web / app
    HostName <приватный IP app-server>
    User nixos
    IdentityFile ~/.ssh/croitor.a-kepair.pem
    ProxyJump bastion

Host db
    HostName <приватный IP db-server>
    User nixos
    IdentityFile ~/.ssh/croitor.a-kepair.pem
    ProxyJump bastion
```

Приватный ключ остаётся на ноутбуке: ProxyJump строит туннель через bastion, а не копирует ключ.

Проверка: `ssh bastion && exit`, `ssh app && exit`, `ssh db && exit`.

**Установка пакета на db-server без интернета.** На NixOS вместо `sudo dnf install postgresql16-server` выполняется `sudo nixos-rebuild switch` — и та же проблема: без NAT подтянуть `postgresql` из `cache.nixos.org` невозможно. Команда падает по таймауту резолва/загрузки — эквивалент зависшего `dnf` из задания 5. Ctrl+C / откат — ожидаемое поведение.

> **Почему `db-server` не может скачать пакеты, хотя `web-server` это делает?**
> У web/app путь к интернету есть: `public-подсеть → public-rt (0.0.0.0/0 → igw) → Internet Gateway → публичный IP`. У db — нет: в `private-rt` только `local`, публичного адреса нет, поэтому исходящий пакет некуда направить. Чтобы стало возможно при сохранении недоступности извне, добавляют **NAT Gateway** (в публичную подсеть) и маршрут `0.0.0.0/0 → nat` в `private-rt`: исходящие соединения инициирует сам сервер (маскируется адресом NAT), а **входящие** снаружи по-прежнему невозможны — у NAT нет «приёмной» логики и у сервера нет публичного адреса.

### Задание 6. Временный NAT Gateway

Скрипты варианта B (для CLI/автоматизации, как требует задание 13 для Informatică; ваша специальность Informatică aplicată — вариант A, консоль; скрипты дают тот же результат и снимают риск забытого шлюза):

- [`scripts/03-nat-up.sh`](scripts/03-nat-up.sh): `allocate-address` (с тегами на EIP!) → `create-nat-gateway` (Zonal, `public-a`, Public, tagged) → `wait nat-gateway-available` → `create-route` в `private-rt` → состояние в `.state/nat.env`.
- [`scripts/10-nat-down.sh`](scripts/10-nat-down.sh): `delete-route` → `delete-nat-gateway` → `wait nat-gateway-deleted` → `release-address` **с ретраями** (AWS отпускает EIP не сразу) → удаление файла состояния.

```bash
./03-nat-up.sh
# == > Выделяю Elastic IP под NAT
# == > Создаю NAT Gateway timecapsule-dev-nat-a в public-a (subnet-...), EIP 3.x.x.x
# == > Жду состояния available (обычно 2-4 минуты)…
# == > Добавляю маршрут 0.0.0.0/0 → NAT в private-rt
# == > Готово: natgateway-... (EIP 3.x.x.x)
```

Установка/накат на db (NAT живой):

```bash
ssh db 'curl https://checkip.amazonaws.com'   # вернёт Elastic IP шлюза, не 10.3.10.x
ssh db 'cd ~/nixos && sudo nixos-rebuild switch --flake .#db'   # аналор dnf install + настройка
```

Затем обязательно `./10-nat-down.sh` и снимок консоли: NAT в `Deleted`, маршрут в `private-rt` в состоянии **Blackhole** (после удаления шлюза) и удалён, EIP освобождён. Скриншот нужно сделать сразу — удалённый шлюз виден в списке около часа.

> **Какой адрес вернула `curl checkip`? Почему это не адрес `db-server`?**
> Elastic IP, выделенный NAT Gateway. Все исходящие соединения инстансов private-подсетей NAT маскирует своим адресом: у db нет собственного публичного адреса, а SNAT заменяет источник на адрес шлюза. Это и позволяет интернету отвечать — но только на **исходящие** соединения.
>
> **Три механизма доступа к базе.** (1) *Маршрут и адрес*: без `0.0.0.0/0` в `private-rt` и без публичного IP пакет из интернета физически не доедет до db. (2) *db-sg*: даже внутри VPC TCP 5432 принимается только от инстансов `web-sg` — bastion с тем же маршрутом получит closed. (3) *pg_hba.conf*: даже пройдя сеть, клиент должен подставить пользователя/базу из разрешённой строки с scram-sha-256. Ошибка в любом одном: без (1) — нужен публичный IP + маршрут (дыра ко всему миру, SG может спасти только ошибкой конфига); без (2) — 5432 слышна со всех машин VPC (в т.ч. с скомпрометированного bastion); без (3) — любая локальная учётка получает доступ к любой базе по сети.
>
> **Почему PostgreSQL работает после удаления NAT?** NAT участвует только в исходящем трафике к публичным ресурсам. Клиентские соединения от app к db идут внутри VPC по маршруту `local` и вообще не задевают шлюз. Для обновлений безопасности на db придётся снова поднять временный NAT (`03-nat-up.sh`), накатить обновления, удалить шлюз — именно так и сделано в задании 13.

### Задание 7. Проверки

Скрипт [`scripts/09-verify.sh`](scripts/09-verify.sh) прогоняет все проверки и собирает «доказательства» текстом (в консоли дублируйте их скриншотами).

**1. Доступ к базе с app-server:**

```text
$ ssh app
$ PGPASSWORD=… psql -h db.timecapsule.internal -U timecapsule -d timecapsule -c 'SELECT version();'
                                                  version
---------------------------------------------------------------------------------------------------------------
 PostgreSQL 16.x (Ubuntu/Debian … NixOS) on x86_64-pc-linux-gnu …
(1 row)
```

**2. Порт 5432 с app vs bastion:**

```text
# с app-server:
$ timeout 5 bash -c '</dev/tcp/10.3.10.4/5432' && echo open || echo closed
open
# с bastion:
$ timeout 5 bash -c '</dev/tcp/10.3.10.4/5432' && echo open || echo closed
closed
```

> **Почему с app открыт, а с bastion — нет, хотя обе в одной VPC?**
> Маршрут между ними одинаковый (`local`), но фильтрация — в Security Group назначения. В `db-sg` правило 5432 указывает источником `web-sg`; bastion в неё не входит, поэтому пакет до PostgreSQL отклоняется на уровне SG, ещё до ОС. VPC-маршрутизация отвечает «как доехать», SG — «можно ли доехать именно этому отправителю к именно этому порту».

**3. Изоляция от интернета:**

```text
$ ssh db 'curl -m 5 https://github.com'
curl: (28) Connection timed out …
# ожидаемо: NAT удалён, в private-rt нет 0.0.0.0/0
```

> **Почему запрос не проходит? Можно ли из интернета подключиться к 5432 db?**
> Цепочка из лекции: у пакета к `github.com` нет маршрута в `private-rt` (кроме `local`) → исходящее соединение не устанавливается. Из интернета к 5432 db подключиться нельзя по той же цепочке наоборот: у db **нет публичного адреса** (AWS не NAT-ит входящие к приватным инстансам), маршрут `0.0.0.0/0` ведёт только на удалённый NAT (Blackhole), а IGW вообще не ассоциирован с private-подсетью. Даже при гипотетическом наличии маршрута дальше сработала бы db-sg (источник не web-sg).

**4. Network ACL.** Правило 90 `Deny All traffic` с источником `<ваш IP>/32` в inbound NACL по умолчанию вашей VPC:

- `ssh bastion` — **блокируется**;
- сайт в браузере с ноутбука — **блокируется**;
- сайт с телефона (мобильный интернет, другой IP) — **открывается**;
- после удаления правила 90 — всё снова работает.

> **Почему заблокировано и SSH, и сайт, хотя SG не менялись? Почему с телефона сайт открывается? Почему номер правила < 100?**
> NACL — stateless фильтр на границе **подсети**, обрабатывается **раньше** Security Group и для **всех** портов сразу. Запрет «весь трафик с моего IP» применяется и к 22 (bastion в public-b), и к 80 (app в public-a): обе публичные подсети ассоциированы с этой NACL. SG остались прежними — NACL их не отменяет, а предваряет. Телефон ходит с другого IP, правило `MyIP/32` его не касается. Номер < 100: правила NACL разбираются по возрастанию rule number, а диапазон 100–32766 зарезервирован для правил, которые AWS добавляет автоматически; правило с номером ≥ 100 может не отработать или конфликтовать с этими системными правилами.

**5. Имена и теги.** Эквивалент Tag Editor в CLI (скриншот `Resource Groups & Tag Editor` в консоли + этот вывод):

```text
$ aws resourcegroupstaggingapi get-resources --tag-filters Key=Project,Values=timecapsule \
    --query 'ResourceTagMappingList[].ResourceARN' --output table
|资源ARN (примеры)                                                      |
| arn:aws:ec2:eu-central-1:…:vpc/vpc-0abc…                             |
| arn:aws:ec2:eu-central-1:…:subnet/subnet-… (×4)                      |
| arn:aws:ec2:eu-central-1:…:internet-gateway/igw-…                    |
| arn:aws:ec2:eu-central-1:…:route-table/rtb-… (×2)                    |
| arn:aws:ec2:eu-central-1:…:security-group/sg-… (×3)                  |
| arn:aws:ec2:eu-central-1:…:instance/i-… (×3) + volume/…              |
| arn:aws:elastic-ip:…  arn:aws:route53:…:hostedzone/…                 |
```

> **Как по тегам найти всё, что нужно удалить после проекта?** Фильтр `Project=timecapsule` (+ при желании `Lab=lab3`) в Tag Editor или `resourcegroupstaggingapi get-resources --tag-filters …` вернёт ровно этот список; удаление по нему — dry-run через `aws resourcegroupstaggingapi delete-resources`. **Зачем `Owner` при личном аккаунте?** Привычка корпоративной идентификации: в общем учебном аккаунте/организации по тегу мгновенно видно, к кому идти с вопросом и чьё можно трогать; в личном — помогает самому не удалить «чужой» ресурс при фильтрации по имени.

**6.** Все три экземпляра остановлены (`11-teardown.sh` или консоль `Stop instance`). За остановленный не платят compute и публичный IP, но EBS-диск и EIP app-server продолжают тарифицироваться.

---

## Часть 2. Продвинутый уровень

Сравнение ЛР2 → ЛР3:

| Что | ЛР2 | ЛР3 (эта работа) |
|---|---|---|
| Сеть | default VPC, всё публичное | своя VPC, база в приватной подсети |
| Сервер приложения | `webserver`, IP меняется | `app-server` + Elastic IP, NixOS |
| База | localhost на webserver | отдельный `db-server`, имя `db.timecapsule.internal` |
| SSH | напрямую с вашего IP | только через bastion (ProxyJump) |
| Деплой | `ssh … ./deploy.sh` | тот же `ssh app ./deploy.sh`, но через bastion |

### Задание 8. Перенос сервера ЛР2 в новую сеть

В классическом варианте из сервера ЛР2 делают AMI и запускают её в новой VPC. В NixOS-подходе **AMI не требуется**: состояние сервера описывается декларативно (flake + git-репозиторий приложения), и «запуск из образа» заменяется:

1. `scripts/04-launch-instances.sh` запускает `app-server` из **публичного NixOS AMI** (пустая, но воспроизводимая ОС);
2. `scripts/05-deploy-nixos.sh` через bastion копирует `nixos/` и выполняет `nixos-rebuild switch --flake .#app` — nginx, PHP-FPM, PDO(pgsql), каталог `/var/www/timecapsule`;
3. systemd-юнит `timecapsule-bootstrap` (в `nixos/modules/timecapsule-app.nix`) клонирует репозиторий приложения из GitHub и создаёт `.env` из `.env.example`, если их ещё нет.

Что содержал «образ» ЛР2, теперь содержат эти слои:

| Данные ЛР2 | Где сейчас |
|---|---|
| код приложения | git-репозиторий → `/var/www/timecapsule` (clone/pull) |
| nginx/PHP-конфиг | `nixos/modules/timecapsule-app.nix` (собирается в store-путь NixOS) |
| пакеты ОС | `nixpkgs` (php84, nginx, postgresql_16) |
| **данные БД** | **не в конфиге и не в git** — на `db-server` (задания 10–12); до переноса оставались на локальном postgres app-server из ЛР2 |

Файлы капсул (`storage/uploads`) ехали с app-server (не с базой): они на диске `/var/www/timecapsule/storage/uploads`. При удалении app-server без бэкапа файлы потеряются — в ADR отмечено как ограничение одиночного EBS; в следующих работах (S3 из ЛР4) логично вынести uploads в объектное хранилище.

`webserver` ЛР2 завершается (`Terminate`): его роль выполняет `app-server`.

> **Что содержит образ? Какие данные из ЛР2 оказались на app-server без установки? Где сейчас хранится база?**
> В NixOS-варианте «образ» — только чистый AMI + донесённая конфигурация: «без ручной установки» оказались nginx, PHP-FPM с расширениями, git, psql — всё это `nixos-rebuild` разворачивает декларативно, а не «помним, что ставили». База данных приложения теперь живёт на `db-server` в `private-a` (отдельный кластер PostgreSQL 16), доступная по `db.timecapsule.internal`.

### Задание 9. Elastic IP

[`scripts/07-eip-app.sh`](scripts/07-eip-app.sh): `allocate-address` с тегом `Name=timecapsule-dev-app-eip` → `associate-address --instance-id app`. Автоматический публичный IP app заменяется на EIP.

Обновление адреса приложения:

```bash
ssh app 'cd /var/www/timecapsule && sed -i "s|^APP_URL=.*|APP_URL=http://<Elastic IP>|" .env && sudo systemctl reload php-fpm'
```

Проверка: `http://<Elastic IP>` → регистрация/вход → капсулы. Скриншот — вкладка Elastic IPs + страница приложения.

> **Почему EIP нужен app, но не bastion? Сколько стоит, пока сервер остановлен, и почему? Понадобится ли EIP при балансировщике?**
> app публикует URL: `APP_URL` зашит в `.env` и в ссылки пользователей — менять адрес при каждом stop/start нельзя. Bastion — утилитарный jump-host: его адрес читается из консоли/скрипта и обновляется в `~/.ssh/config` (`update-ssh-config.sh` делает это автоматически) — неудобно, но бесплатно и без внешней зависимости. Elastic IP тарифицируется **всегда**, пока привязан, даже к остановленному серверу (~$0.005/ч, ≈$3.6/мес): AWS резервирует редкий публичный IPv4 в своём пуле. При появлении Application Load Balancer Elastic IP одиночному серверу **не нужен**: внешняя точка входа — CNAME/Alias на DNS балансировщика, экземпляры за ним могут меняться; EIP на app помешал бы замене/масштабированию.

### Задание 10. База данных приложения на db-server

На NixOS пользователи и базы создаются декларативно — `nixos/modules/postgres-lab.nix`:

```nix
services.postgresql = {
  enable = true;
  package = pkgs.postgresql_16;
  enableTCPIP = true;
  settings.listen_addresses = "*";
  authentication = lib.mkForce ''
    local   all       all                 peer
    host    all       all   127.0.0.1/32  scram-sha-256
    host    all       all   10.3.0.0/24   scram-sha-256   # ← только public-a
  '';
  initialScript = pkgs.writeText "lab3-init.sql" ''
    CREATE USER student WITH PASSWORD '…';      CREATE DATABASE lab3 OWNER student;
    CREATE USER timecapsule WITH PASSWORD '…';  CREATE DATABASE timecapsule OWNER timecapsule;
  '';
};
```

Это эквивалент `postgresql-setup --initdb` + `listen_addresses` + строки `pg_hba.conf` из задания 6, но пересоздание сервера = `nixos-rebuild`, а не ручные sed. Строка `10.3.0.0/24` уже **сужена** до нужного пользователя/базы по духу задания 10 (в классической ручной версии — заменить `all all` на `timecapsule timecapsule`).

Перезапуск после правок: `ssh db 'sudo systemctl restart postgresql'`, ошибки — `journalctl -u postgresql -n 20`.

> **Зачем новый сильный пароль, если 5432 закрыта SG?**
> SG — периметр, пароль — содержимое. Слабый пароль опасен при (1) ошибке правила SG (один `0.0.0.0/0` или лишняя строка в pg_hba — и периметр мгновенно бессмыслен); (2) доступе из app-server/bastion после их компрометации (RCE в веб-приложении — классика): сильный пароль + scram-sha-256 + узкая строка pg_hba оставляют злоумышленнику только одну «дырку» вместо полного захвата данных; (3) утечке дампов/логов. Оборона в глубину: закрытый порт не отменяет аутентификацию.

### Задание 11. Приватная зона Route 53

[`scripts/06-route53.sh`](scripts/06-route53.sh): `create-hosted-zone` (Private, VPC `timecapsule-dev-vpc`, регион eu-central-1, обязательные теги) + A-запись `db.timecapsule.internal → <приватный IP db>`, TTL 60.

```bash
# с app-server (через bastion), через 1-2 минуты:
$ dig +short db.timecapsule.internal
10.3.10.4
# с вашего компьютера:
$ dig +short db.timecapsule.internal
# (пусто — зона приватная, в цепочке recursive resolver вашего провайдера её просто нет)
```

> **Почему с app имя находится, а с вашего компьютера нет? Что делать, если db пересоздадут с другим IP?**
> Приватная hosted zone связана **только с вашей VPC**: DNS-резолвер VPC (169.254.169.253) знает эту зону и отдаёт записи исключительно инстансам этой VPC. Снаружи ни один рекурсивный резолвер не делегирован в `timecapsule.internal` — имя не разрешается. При пересоздании db с новым IP достаточно UPSERT одной A-записи (перезапустите `06-route53.sh` — он идемпотентен): приложение уже не придётся трогать, TTL 60 с разнесёт новый адрес.

### Задание 12. Перенос данных и переключение приложения

[`scripts/08-migrate-data.sh`](scripts/08-migrate-data.sh):

```bash
# 1) дамп локальной (старой) БД на app-server
pg_dump -h localhost -U timecapsule -d timecapsule -f /tmp/timecapsule.sql
# 2) загрузка в новую БД по имени
PGPASSWORD=… psql -h db.timecapsule.internal -U timecapsule -d timecapsule -f /tmp/timecapsule.sql
# 3) .env: DB_HOST=db.timecapsule.internal, новый пароль, reload php-fpm
# 4) выключение локального postgres на app — приложение физически не может вернуться к localhost
sudo systemctl disable --now postgresql
```

Проверка: `/health` → `{"status":"ok","db":"ok","host":"db.timecapsule.internal"}`; главная страница — капсулы, созданные в ЛР2, на месте (доказательство, что данные переехали, а не воссоздались).

Образ `timecapsule-dev-app-lab2` в этой версии **не создавался** (см. задание 8) — дегистрировать и удалять снимки нечего; в консоли AMIs/Snapshots нет ни нашего образа, ни платных снимков.

> **Файлы капсул переехали вместе с образом, а не с базой. Где они? Что будет при удалении app-server?**
> Файлы не в БД и не в git: `/var/www/timecapsule/storage/uploads` на диске app-server (в ЛР2 они же лежали на webserver и «переехали» с AMI, потому что снимок диска включает каталог). С БД они никак не связаны — дамп `pg_dump` их не касается. При `Terminate app-server` вместе с диском (DeleteOnTermination=true по умолчанию) файлы потеряются: кэпсула в базе останется, вложение — нет. Митигации: отвязать/снять диск перед удалением, бэкап в S3 (тема ЛР4), либо snapshot диска.

### Задание 13. Деплой и обслуживание

**1. Новая версия.** В `app/views/list.php` добавлена заметная строка `<em>LR3</em>` в подвале списка; изменение запушено в репозиторий. Деплой — **вариант B**, без изменений в deploy.sh (почему — ниже):

```bash
ssh app ./deploy.sh
# ==> cd /var/www/timecapsule
# ==> git pull --ff-only
# ==> composer install … (пропуск: собственное приложение без зависимостей)
# ==> php bin/init-db.php   → Database is ready
# ==> sudo systemctl reload php-fpm
# Готово. На сервере коммит: … «LR3 footer»
```

SSH-команда выглядит коротко благодаря `ProxyJump bastion` в `~/.ssh/config`: в самом `deploy.sh` ничего менять не пришлось, потому что он работает **на сервере** после того, как ssh уже доставил вас внутрь VPC; вся «сложность» маршрута (bastion, приватный адрес) абстрагирована конфигом SSH на вашей машине, а не скриптом деплоя.

**2. Отказ базы.** `ssh db 'sudo systemctl stop postgresql'` (или Stop instance в консоли):

```text
$ curl -s http://<EIP>/health
{"status":"error","db":"error"}     # через ~30-60 c — PHP-FPM ждёт таймаут соединения
$ curl -s http://<EIP>/
страница с ошибкой/виснет до таймаута PDO
# запускаем db снова — приложение оживает само, без правок на app
```

> **Что показал /health и почему? Изменился ли приватный адрес после stop/start?**
> `"db":"error"`: health.php дёргает PDO к `db.timecapsule.internal`, соединение падает по таймауту/отказу — но сам endpoint продолжает отвечать JSON, потому что изолирован от основного кода приложения (отдельный fastcgi-скрипт в nginx). Приложение «само оказалось» после запуска db, потому что DNS-имя не изменилось: приватный IP экземпляра **сохраняется** при stop/start того же инстанса (меняется только публичный, если он не EIP; EIP app тем более зафиксирован). Пересоздание db (Terminate + Launch) дало бы новый IP — но его подхватит A-запись Route 53, а не `.env`.

**3. Обновления на db-server (NAT, вариант B).**

```bash
./03-nat-up.sh
ssh db 'cd ~/nixos && sudo nixos-rebuild switch --flake .#db'   # аналор sudo dnf -y update
./10-nat-down.sh
```

Вывод скриптов — в разделе задания 6; в консоли фиксируется `NAT gateways` со шлюзом (скриншот сразу после удаления: `Deleted`) и `Elastic IPs` без адреса NAT.

> **Почему nat-down.sh освобождает EIP только после удаления NAT Gateway?**
> Elastic IP является **allocated** к NAT Gateway, пока тот существует: `release-address` на привязанном адресе падает с `InvalidIPAddress.InUse`. AWS держит связь ещё некоторое время после `delete-nat-gateway` (поэтому wait `nat-gateway-deleted` + ретраи в скрипте). Освободив адрес «на будущее» до удаления шлюза, мы бы получили гарантированную ошибку и ресурс-утечку.

### Задание 14. Архитектура и решение

- Схема: [images/architecture.svg](images/architecture.svg) (рис. 1 в начале отчёта) — пользователи/ваш компьютер/GitHub вне AWS; VPC, две зоны, четыре подсети; IGW; три сервера с SG; приватная зона Route 53; временный NAT пунктиром; все имена полные, по соглашению.
- Решение о размещении БД: [docs/adr/0002-database-placement.md](docs/adr/0002-database-placement.md) — три варианта (на одном сервере / отдельный в public / отдельный в private), последствия: экономика временного NAT, зачем EIP и когда он станет не нужен (ALB).

---

## Запуск с нуля одной командой

Предпосылки: AWS CLI настроен (`aws sts get-caller-identity`), ключ `~/.ssh/croitor.a-kepair.pem` существует (в AWS — key pair того же имени), `K` в `env.sh` = ваш номер в группе.

```bash
cd scripts
./01-network.sh            # зад. 1-3: VPC, подсети, IGW, rt, DNS, auto-assign
./02-security-groups.sh    # зад. 4: bastion/web/db SG
./03-nat-up.sh             # временный NAT (для наката конфига на private db)
./04-launch-instances.sh   # зад. 5/8: 3× NixOS AMI + user-data с ssh-ключом
./05-deploy-nixos.sh       # nixos-rebuild flake: bastion → app → db
./10-nat-down.sh           # NAT больше не нужен (зад. 6, финал)
./07-eip-app.sh            # зад. 9: Elastic IP app
./06-route53.sh            # зад. 11: timecapsule.internal + db A-запись
./08-migrate-data.sh       # зад. 12: pg_dump → новая БД → .env → disable local pg
./update-ssh-config.sh     # bastion/web/app/db в ~/.ssh/config
./09-verify.sh             # зад. 7 + проверки продвинутого уровня
# … эксперименты зад. 7.4 (NACL), зад. 13 (deploy, отказ БД) …
./11-teardown.sh           # остановить экземпляры, убрать NAT/EIP, оставить сеть
```

---

## Ответы на контрольные вопросы

### Как проходит запрос пользователя от браузера до базы данных? Какие маршруты и правила фильтрации он проходит на каждом шаге?

1. Браузер → `http://<Elastic IP app>`: пакет выходит из сети пользователя, проходит инфраструктуру AWS до IGW VPC (EIP ассоциирован с инстансом в `public-a`).
2. На входе в `public-a` первый фильтр — **Network ACL** подсети (stateless, по умолчанию allow all; в эксперименте задания 7 здесь же Deny по IP).
3. Дальше **Security Group** инстанса app (`web-sg`): входящий TCP 80 разрешён с `0.0.0.0/0` (TCP 22 — только из `bastion-sg`; SG stateful, ответный трафик исходящих соединений проходит без дополнительных правил).
4. nginx принимает запрос, для нестатических путей отдаёт PHP-FPM через unix socket; `index.php` через PDO инициирует **исходящее** соединение к `db.timecapsule.internal:5432` (резолвится приватным DNS VPC до приватного IP db).
5. Трафик app → db идёт внутри VPC по маршруту таблицы `private-rt`/`local` (10.3.0.0/16 → local), **IGW/NAT не участвуют**; между зонами 1a↔1a — локально, та же логика маршрутизации.
6. На входе в `private-a` — **NACL private-подсети** (allow).
7. **db-sg** на инстансе db: принимает TCP 5432 **только из `web-sg`** (bastion с тем же маршрутом получит closed).
8. PostgreSQL сверяет **pg_hba.conf**: адрес клиента (10.3.0.0/24) в разрешённой строке, пользователь `timecapsule`, база `timecapsule`, метод `scram-sha-256` — проверка пароля.
9. Ответ идёт обратно по тому же пути; SG/NACL не требуют «входящих» правил на ответ, потому что соединение уже установлено (stateful SG; NACL stateless — но для эфемерных портов ответного трафика есть стандартные allow-правила).

### Злоумышленник знает приватный IP db-server. Что ему нужно получить, чтобы подключиться к базе?

Знание IP почти бесполезно само по себе: снаружи пакет до приватного адреса **не дойдёт** (нет публичного IP у цели, нет маршрута в интернет из private-rt, IGW не ассоциирован с приватной подсетью). Чтобы реально достучаться, ему нужно **всё вместе**: (1) foothold внутри VPC — например, скомпрометированный app-server (RCE в приложении) или bastion (扽нужен ещё и SSH-ключ/пароль); (2) чтобы его источник попал под правило db-sg — т.е. foothold должен быть инстансом в `web-sg` (или уметь подменять source, что в TCP практически недоступно); (3) валидные учётные данные `timecapsule`/пароль — pg_hba требует scram-sha-256, «голый» TCP-хендшейк не даёт данных. Украденный пароль без (1)(2) бесполезен, (1) без (3) даст максимум SSH-туннель, если SG-правила скомпрометированы полностью.

### Чем временный NAT Gateway лучше постоянного, и какие неудобства он создаёт?

Постоянный NAT Gateway — непрерывный платёж (~$0.045/ч + $0.045/ГБ, ≈$32+/мес за один шлюз) и лишняя постоянная поверхность атаки/конфигурации, когда 95% времени серверам выход в интернет не нужен. Временный: платишь центы за минуты работы ровно под `nixos-rebuild`/`dnf update`, платёжная модель лабы сходится к ~$31/мес за всё. Недостатки: каждый цикл обновлений — ручная (или скриптовая) оркестрация create/wait/route/delete/wait/release; окно, когда route `0.0.0.0/0` существует, расширяет blast radius private-подсети; главное — **риск забыть удалить** (≈$1.25/сутки, дороже всего остального). Скрипты `nat-up/nat-down` + `11-teardown.sh` + состояние в `.state/nat.env` как раз закрывают человеческий фактор; «неудобство» автоматизировано ценой одного файла состояния.

### Как изменится схема, если приложение должно пережить отказ зоны eu-central-1a? Каких ресурсов не хватает?

Сейчас app в 1a, db в 1a — отказ 1a валит и сайт, и базу (bastion в 1b выживет, но некому обслуживать). Для устойчивости: (1) **db**: реплика в `private-b` + автоматический failover (Patroni/etcd или управляемый RDS Multi-AZ) — в схеме AWS нет ни второго db-инстанса, ни механизмов репликации; (2) **app**: второй экземпляр в `public-b` и **Application Load Balancer** перед ними (ALB сам раскидывает по зонам, health check по `/health`), тогда EIP app становится ненужным (см. зад. 9); (3) bastion — либо второй в 1a/1b, либо AWS Systems Manager Session Manager вместо него вообще; (4) Route 53 A-запись db останется одной — при failover нужен health-check/latency-routing или DNS с таймером на новую реплику; (5) NAT — по одному на зону (zonal NAT) либо транзитный/общий паттерн. То есть из текущих ресурсов не хватает: второго app, второго db, ALB, механизмов репликации/ failover, второго bastion (или его замены) и multi-AZ NAT-стратегии.

---

## Итог: состояние после завершения

- Экземпляры `bastion`, `app`, `db` — **stopped** (диски остаются, оплачиваются).
- `NAT gateways` — нет ни одного `Available` (скриншот консоли сразу после удаления в зад. 6/13).
- `Elastic IPs` — остался только `timecapsule-dev-app-eip`, привязанный к app (скриншот). NAT EIP освобождён скриптом.
- VPC, подсети, SG, приватная зона — **не удалялись** (бесплатны, нужны в ЛР4).
- Репозиторий: <https://github.com/yorunikakeru4/timecapsule> — приложение, скрипты, NixOS-конфиг, ADR, этот отчёт (`docs/lab3/README.md`).

### Где взять скриншоты из чек-листа отчёта

AWS-консольные скриншоты (VPC, rt, SG, Tag Editor, EIP, NAT `Deleted`, страницы приложения) фиксируются во время прогона `scripts/*` по порядку из раздела «Запуск с нуля»; текстовые доказательства команд (`psql`, `dig`, `/health`, port-check) приведены выше в секциях заданий и воспроизводятся `09-verify.sh`. Не публикуйте пароли и `.env` на скриншотах; домашний IP в `bastion-sg` показывайте замаскированным.

---

*Отчёт подготовлен в Markdown по формату лабораторной; стиль изложения — по образцу отчётов SoftDesign (`~/Documents/Education/3/SoftDesign/*/README.md`): короткие тезисы, код как доказательство, трейдофы явно.*
