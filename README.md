# Финальный проект
_Заметки во время работы велись на [странице](https://winand.notion.site/3c7bbac3a4e0443fb3fc49b85f0f45c9?pvs=4) в Notion_.
_Данный README.md создан на их основе после завершения мероприятия._

## Определение расположения конфигурации
_Изучение исполняемого файла проводилось Docker-контейнере Debian_
_с опцией `--privileged`._

Приложение bingo не запускается из-за отсутствия файла с конфигурацией
(`bingo print_current_config` и `bingo run_server`). Определить, к каким
файлам обращается приложение можно [с помощью `strace`](https://stackoverflow.com/questions/56507809/how-to-determine-what-files-a-program-is-trying-to-open):
```bash
apt update
apt install strace sudo 
strace -fe openat sudo -u app ./bingo print_current_config
```
Так как приложение не запускается под `root` используем `sudo -u app`.
В выводе видно, что происходило обращение к `/opt/bingo/config.yaml`:
```
[pid   421] openat(AT_FDCWD, "/opt/bingo/config.yaml", O_RDONLY|O_CLOEXEC) = -1 ENOENT (No such file or directory)
```

## Создание конфигурации
Сохраняем конфигурацию по умолчанию в нужное расположение:
`./bingo print_default_config > /opt/bingo/config.yaml`.
Вносим туда свой почтовый адрес при регистрации.

## Расположение файла с логом
Теперь при запуске возникает ошибка `panic: failed to build logger`.
Повторно запускаем `strace`. Программа пытается открыть файл
`/opt/bongo/logs/cad7532b03/main.log`. Экспериментально выясняем, что
путь зависит от указанного в конфигурации адреса почты, создаём
соответствующую директорию.

В дальнейшем было определено, что в лог выводится большое количество
дебаг-сообщений, поэтому лог был выведен в _/dev/null_:
`ln -s /dev/null /opt/bongo/logs/${LOGDIR?}/main.log`

## Установка PostgreSQL
Если запустить приложение без доступной СУБД возникает ошибка
`Error: failed Init Core: failed NewDatabase: could not connect to any host from the list`.

Сначала для локального тестирования был установлен PostgreSQL 16
в том же контейнере, в котором тестировалось приложение. Затем в
отдельном контейнере был поднят _postgres:16-alpine_ с заданными переменными
`POSTGRES_USER`, `POSTGRES_PASSWORD`, `POSTGRES_DB`. В файле _pg_hba.conf_
в этом контейнере прописана строка `host all all all scram-sha-256`,
поэтому дополнительная настройка не требуется.

Установка PostgreSQL 16 локально:
```bash
apt update
apt install lsb-release wget  # если не установлены
sh -c 'echo "deb https://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list'
apt -y install gnupg
wget --quiet -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc | sudo apt-key add -
apt update
apt install postgresql

pg_lsclusters  # посмотреть версию и имя кластера
pg_ctlcluster 16 main start

apt install lsof
lsof -Pi | grep postgres  # проверить, что Postgres слушает 5432
```

### Настройка СУБД
Создадим нового пользователя _bingo_ и БД для работы приложения, также нужно
внести соответствующие правки в файл конфигурации приложения:
```
create role bingo with login;  # разрешить подключение
alter role bingo with password 'str0ng_passw0rd';  # задать пароль

create database bingo owner bingo;
```
Проверяем работоспособность, подключившись _psql_: `psql -U bingo -h localhost -d bingo`.

Для наполнения БД необходимо выполнить `./bingo prepare_db`.

## Запуск приложения и поиск секретных кодов
При запуске выдаётся сообщение с первым кодом:
```
My congratulations.
You were able to start the server.
Here's a secret code that confirms that you did it.
--------------------------------------------------
code:         yoohoo_server_launched
--------------------------------------------------
```
Приложение работает на порте `16482` (что видно через `lsof -i`), который
зависит от адреса почты. На главной странице расположен второй код:
`index_page_is_awesome`.

С помощью `strings bingo | grep "code: "` был найден третий код:
`google_dns_is_not_http`.

## Контейнеризация и автоматизация
Приложение упаковывается в контейнер distroless и загружается с помощью GitHub Actions
в заранее созданный реестр на Яндексе. При сборке используются `docker/login-action`
и `docker/build-push-action`. Авторизация в реестре осуществляется с помощью
OAuth токена. Токен, почтовый адрес и пароль БД заданы в secrets в репозитории.

_Dockerfile_ является multi-stage. На первой стадии в шаблон конфигурации
подставляются необходимые переменные и создаются файлы и каталоги в `/opt`.
Также загружаются утилиты `wget`, `kill`, `sh` с _busybox.net_ для реализации
логики healthcheck (см. ниже). На втором этапе создаётся образ на основе
_distroless/static-debian12_, куда копируется папка `/opt` и утилиты, а также
загружается исполняемый файл приложения. Здесь же указывается внутренний порт приложения.

### Healthcheck
Поскольку приложение может упасть, перезапуск контейнера обеспечивается опцией
`restart: always` в файле Docker Compose (см. _terraform/docker-compose.yaml_).
Однако приложение может перестать правильно функционировать без падения,
в этом случае контейнер продолжит работать и перезапуск не произойдёт.

Для решения этой проблемы в _Dockerfile_ добавлен специальный _healthcheck_,
который вместо простого определения статуса приложения завершает его выполнение
при обнаружении проблемы, что вызывает остановку контейнера и его перезапуск.

Проверка статуса осуществляется обращением к эндпоинту `/ping`, если он не
возвращает статус `200`, то команда `kill 1` завершает работу приложения.
Проверка происходит каждые 40 секунд (`--interval=40s`).

Поскольку используется контейнер distroless для реализации логики healthcheck
были добавлены утилиты `wget` и `kill`, а также `sh` для их запуска.

## Облако
Для развёртывания приложения используется Яндекс.Облако и Terraform.

### Terraform
Для создания ресурсов в облаке выполняем команду `terraform apply` в папке _terraform_.

Реестр образов создан заранее, образ приложения загружается туда из GitHub Actions
(см. **Контейнеризация и автоматизация**).
ID реестра Terraform получает из переменной `vars.registry_id` в файле
`yc.auto.tfvars` (не добавлен в репозиторий). Также в этом файле указан ID облака
и внутренний порт приложения для балансировщика.

Приложение поднимается на двух инстансах COI с помощью `yandex_compute_instance_group`.
На инстансах запускается `terraform/docker-compose.yaml`, где настроен автоматический
перезапуск при падении контейнера (`restart: always`).

Поверх инстансов работает балансировщик `yandex_lb_network_load_balancer`,
который проверяет доступность инстанса по эндпоинту `/ping`.

### Настройка БД
СУБД вручную развёрнута на инстансе `yandex_compute_instance.db-inst-1`
(с образом _debian-10_) как в разделе выше **Установка PostgreSQL**.
Cоздана БД _bingo_ и соответствующий пользователь _bingo_.

Помимо самой СУБД установлен PgBouncer:
```bash
apt install pgbouncer lsof
lsof -Pi | grep postgres  # проверка
```
В файл `vim /etc/pgbouncer/pgbouncer.ini` добавлена БД и разрешение слушать
подключения со всех интерфейсов:
```
[databases]
bingo = host=localhost dbname=bingo
[pgbouncer]
;; Слушать все интерфейсы
listen_addr = *
```
В файл `vim /etc/pgbouncer/userlist.txt` добавлен пользователь в формате
`"bingo" "hash-value"`. Хеш пароля для этого получен через _psql_ запросом
`select passwd from pg_shadow where usename='bingo';`.

Для применения настроек перезапускаем PgBouncer `service pgbouncer restart`.

### Наполнение БД
Для наполнения БД необходимо выполнить `./bingo prepare_db`.
Для этого используется специальный инстанс `yandex_compute_instance.bingo-db-init`.
В нём запускается Docker Compose `terraform/docker-compose-db-init.yaml`, где
указан аргумент `command: prepare_db`. Поднять конкретный инстанс можно командой
`terraform apply -target yandex_compute_instance.bingo-db-init`.

Процесс наполнения отслеживался в логах контейнера на этом инстансе через SSH.
После завершения процесса этому ресурсу присвоено `count=0` в файле `main.tf`,
поскольку он не нужен для работы сервиса.

### Оптимизация БД
Во время запроса `/api/session` выполнил в _psql_ `SELECT * FROM pg_stat_activity WHERE wait_event IS NOT NULL AND backend_type = 'client backend';`.

СУБД выполняла медленный запрос `SELECT sessions.id, sessions.start_time, customers.id, customers.name, customers.surname, customers.birthday, customers.email, movies.id, movies.name, movies.year, movies.duration FROM sessions INNER JOIN customers ON sessions.customer_id = customers.id INNER JOIN movies ON sessions.movie_id = movies.id ORDER BY movies.year DESC, movies.name ASC, customers.id, sessions.id DESC LIMIT 100000;`

Посмотрел план выполнения с помощью `EXPLAIN` и создал индексы:
```sql
create index idx_customer on sessions(customer_id);
create index idx_id on customers(id);
create index idx_movie_id on movies(id);
CREATE INDEX idx_movies_year_desc ON movies (year DESC);
CREATE INDEX idx_movies_name_asc ON movies (name ASC);
create index idx_movie on sessions(movie_id);
create index idx_session_is on sessions(id);
```

Увеличил объём используемой памяти для внутренних операций в
`/etc/postgresql/16/main/postgresql.conf`:
```
work_mem = 64MB
```
В конце перезапускаем СУБД `service postgresql restart` и проверяем объём памяти через _psql_ `SHOW work_mem;`