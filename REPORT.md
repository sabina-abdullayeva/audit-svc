# Отчёт

## 1. Pipeline main

Pipeline ветки `main`: тесты и сборка прошли успешно, deploy для ветки не
запускается:

![Pipeline ветки main](screenshots/Screenshot%202026-10-25%20at%2004.01.44.png)

Образ публикуется с тегом `main_<sha>` для платформы `linux/arm64`:

![Публикация main образа](screenshots/Screenshot%202026-10-25%20at%2004.03.28.png)

Образ опубликован в GitHub Packages:

![Образ audit-svc в GHCR](screenshots/Screenshot%202026-10-25%20at%2002.53.18.png)

## 2. Релиз и деплой

```bash
git tag v0.1.0
git push origin v0.1.0
```

![Pipeline тега](screenshots/Screenshot%202026-10-25%20at%2002.56.09.png)

Деплой из pipeline тега:

![Лог deploy](screenshots/Screenshot%202026-10-25%20at%2002.52.09.png)

Полный успешный лог деплой с `PLAY RECAP`:
[logs/password-rotation.txt](logs/password-rotation.txt).

### Проверка идемпотентности

Повторный деплой:

```text
TASK [Gathering Facts]                              ok
TASK [Install Python modules for Ansible]           ok
TASK [Create project directories]                   ok
TASK [Create application network]                   ok
TASK [Create PostgreSQL volume]                     ok
TASK [Create PostgreSQL environment file]           ok
TASK [Start PostgreSQL]                             ok
TASK [Read PostgreSQL container information]        ok
TASK [Remember PostgreSQL address]                  ok
TASK [Wait until PostgreSQL accepts connections]    ok
TASK [Create application database user]             ok
TASK [Create application database]                  ok
TASK [Create audit-svc config]                      ok
TASK [Run database migrations]                      ok
TASK [Start audit-svc]                              ok
TASK [Create Nginx config]                          ok
TASK [Start Nginx]                                  ok
TASK [Start nginx-exporter]                         ok
TASK [Check service through Nginx]                  ok

PLAY RECAP
deploy : ok=19 changed=0 unreachable=0 failed=0 skipped=0 rescued=0 ignored=0
```

Полный лог: [logs/deploy-idempotency.txt](logs/deploy-idempotency.txt).

![Повторный  деплой без изменений](screenshots/Screenshot%202026-10-25%20at%2002.59.16.png)

## 3. Смена пароля без перезапуска

Pipeline тега `v0.1.6`, в котором менялся пароль:

![Pipeline смены пароля](screenshots/Screenshot%202026-10-25%20at%2003.53.15.png)

Во время deploy изменились пароль пользователя и конфиг. После этого
сработал handler перечитывания:

```text
TASK [Create application database user]
changed: [deploy]

TASK [Create audit-svc config]
changed: [deploy]

TASK [Start audit-svc]
ok: [deploy]

RUNNING HANDLER [Reload audit config]
changed: [deploy]

PLAY RECAP
deploy : ok=20 changed=3 unreachable=0 failed=0
```

Полный лог: [logs/password-rotation.txt](logs/password-rotation.txt).

```bash
docker inspect -f '{{.State.StartedAt}}' audit-svc

ansible-vault edit \
  --vault-password-file deploy/vault-pass \
  deploy/inventories/prod/group_vars/all/vault.yml

docker inspect -f '{{.State.StartedAt}}' audit-svc
docker logs audit-svc 2>&1 | grep 'config reloaded'
curl -s http://127.0.0.1:8088/healthz
curl -s http://127.0.0.1:8088/metrics | grep audit_config_reloads_total
```

Результат:

```text
Before: 2026-10-25T00:04:02.999441832Z
After:  2026-10-25T00:04:02.999441832Z
StartedAt unchanged
2026-10-24 23:42:41,137 [INFO] audit_svc.main: config reloaded, database settings are unchanged
2026-10-25 00:14:35,822 [INFO] audit_svc.main: config reloaded, reconnected to the database
200
audit_config_reloads_total{result="success"} 1.0
```

## 4. Nginx

```bash
curl -s -o /dev/null -w '%{http_code}\n' http://127.0.0.1:8088/healthz
curl -s -o /dev/null -w '%{http_code}\n' -X POST http://127.0.0.1:8088/reload
curl -s -o /dev/null -w '%{http_code}\n' -X POST 'http://127.0.0.1:8088/reload?x=1'
curl -s -o /dev/null -w '%{http_code}\n' -X POST http://127.0.0.1:8088//reload
curl -s -o /dev/null -w '%{http_code}\n' -X POST http://127.0.0.1:8088/%72eload
docker ps --format '{{.Names}}\t{{.Ports}}'
curl -s http://127.0.0.1:9113/metrics | grep '^nginx_up'
```
Результат:

```text
healthz: 200
/reload: 404
/reload?x=1: 404
//reload: 404
/%72eload: 404
nginx_up 1
```

Количество записей о reload до и после проверочных запросов:

```text
before: 2
after: 2
```

Порты контейнеров:

```text
nginx-exporter  127.0.0.1:9113->9113/tcp
nginx           80/tcp, 127.0.0.1:8088->8080/tcp
audit-svc       8080/tcp
postgres        5432/tcp
```
## 5. Мониторинг

```bash
docker run --rm --network audit \
  --entrypoint generate \
  ghcr.io/sabina-abdullayeva/audit-svc:v0.1.0 \
  --url http://nginx:8080 --duration 600
```

### Prometheus targets


![Prometheus targets UP](screenshots/Screenshot%202026-10-25%20at%2002.49.27.png)


![Prometheus audit-svc DOWN](screenshots/Screenshot%202026-10-25%20at%2003.03.16.png)

### Дашборд audit-svc


![Графики audit-svc](screenshots/Screenshot%202026-10-25%20at%2002.50.31.png)

После генерации нагрузки появились данные, сервис находится в состоянии up:

![Дашборд audit-svc UP](screenshots/Screenshot%202026-10-25%20at%2002.55.01.png)

После остановки приложения панель показывает DOWN:

![Дашборд audit-svc DOWN](screenshots/Screenshot%202026-10-25%20at%2003.03.03.png)

### Дашборд Nginx

![Дашборд Nginx](screenshots/Screenshot%202026-10-25%20at%2002.54.52.png)
