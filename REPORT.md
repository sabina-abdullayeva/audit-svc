# Отчёт по итоговой работе

> Здесь пока находится план проверок. После запуска на Ubuntu VM под каждой
> командой нужно вставить настоящий вывод и добавить скриншоты. Выдуманные
> логи в отчёт не добавляются.

## 1. Подготовка Ubuntu 22.04 ARM64

```bash
uname -m
lsb_release -a
docker version
ansible --version
```

Ожидаемая архитектура — `aarch64`.

Установка основных пакетов:

```bash
sudo apt update
sudo apt install -y docker.io python3-pip python3-venv
sudo usermod -aG docker "$USER"
```

После добавления в группу нужно выйти из SSH-сессии и войти снова.

Ansible удобнее поставить отдельно от системного Python:

```bash
python3 -m pip install --user "ansible-core>=2.15,<2.18"
ansible-galaxy collection install -r deploy/requirements.yml
```

## 2. Ansible Vault

Сначала придумать отдельный пароль от Vault и сохранить его только локально:

```bash
printf '%s' 'СЮДА_ПАРОЛЬ_VAULT' > deploy/vault-pass
chmod 600 deploy/vault-pass
```

Создать зашифрованный файл:

```bash
ansible-vault create \
  --vault-password-file deploy/vault-pass \
  deploy/inventories/prod/group_vars/all/vault.yml
```

Содержимое до сохранения:

```yaml
vault_postgres_password: СЛУЧАЙНЫЙ_ПАРОЛЬ_1
vault_audit_password: СЛУЧАЙНЫЙ_ПАРОЛЬ_2
```

Проверить, что файл действительно зашифрован:

```bash
head -n 1 deploy/inventories/prod/group_vars/all/vault.yml
# $ANSIBLE_VAULT;1.1;AES256
```

Тот же пароль записать в GitHub Environment `production` как секрет
`ANSIBLE_VAULT_PASSWORD`. Сам файл `deploy/vault-pass` игнорируется Git.

## 3. GitHub runner

В настройках репозитория открыть `Actions → Runners → New self-hosted runner`,
выбрать Linux и ARM64 и выполнить предложенные GitHub команды.

Добавить runner дополнительную метку `deploy`. Сервис runner должен работать
от пользователя, который входит в группу `docker` и может выполнять `sudo`
без интерактивного ввода.

Защитить теги `v*` через Rulesets. Workflow для deploy привязан к Environment
`production`.

## 4. Первый pipeline

```bash
git push origin main
```

Вставить сюда:

- скриншот графа jobs;
- лог `pytest`;
- лог публикации `main_<short-sha>`;
- скриншот пакета `audit-svc` в GHCR.

## 5. Релиз

```bash
git tag v0.1.0
git push origin v0.1.0
```

Проверки на VM:

```bash
docker ps --format 'table {{.Names}}\t{{.Image}}\t{{.Ports}}'
curl -i http://127.0.0.1:8088/healthz
curl -s http://127.0.0.1:9113/metrics | grep '^nginx_up'
```

Сюда вставить полный deploy log с `PLAY RECAP`.

## 6. Идемпотентность

Повторно запустить deploy job без изменения файлов. Ожидается:

```text
changed=0
```

Сюда вставить второй `PLAY RECAP`.

## 7. Проверка reload без перезапуска

До изменения пароля:

```bash
docker inspect -f '{{.State.StartedAt}}' audit-svc
```

Изменить `vault_audit_password`:

```bash
ansible-vault edit \
  --vault-password-file deploy/vault-pass \
  deploy/inventories/prod/group_vars/all/vault.yml
```

После commit, push и нового тега повторить:

```bash
docker inspect -f '{{.State.StartedAt}}' audit-svc
docker logs audit-svc 2>&1 | grep 'config reloaded'
curl -s http://127.0.0.1:8088/healthz
curl -s http://127.0.0.1:8088/metrics | grep audit_config_reloads_total
```

`StartedAt` до и после должен совпасть.

## 8. Проверка Nginx

```bash
curl -s -o /dev/null -w '%{http_code}\n' http://127.0.0.1:8088/healthz
curl -s -o /dev/null -w '%{http_code}\n' -X POST http://127.0.0.1:8088/reload
curl -s -o /dev/null -w '%{http_code}\n' -X POST 'http://127.0.0.1:8088/reload?x=1'
curl -s -o /dev/null -w '%{http_code}\n' -X POST http://127.0.0.1:8088//reload
curl -s -o /dev/null -w '%{http_code}\n' -X POST http://127.0.0.1:8088/%72eload
docker ps --format '{{.Names}}\t{{.Ports}}'
curl -s http://127.0.0.1:9113/metrics | grep '^nginx_up'
```

Ожидаемые коды: `200`, затем четыре раза `404`. Портов у `audit-svc` и
`postgres` быть не должно.

## 9. Мониторинг

```bash
export GRAFANA_ADMIN_PASSWORD='СЛУЧАЙНЫЙ_ПАРОЛЬ'
docker compose -f monitoring/compose.yaml up -d
```

Генератор нагрузки:

```bash
docker run --rm --network audit \
  --entrypoint generate \
  ghcr.io/sabina-abdullayeva/audit-svc:v0.1.0 \
  --url http://nginx:8080 --duration 600
```

В отчёт добавить:

- скриншот Prometheus `/targets`, где обе цели `UP`;
- дашборд `audit-svc`;
- импортированный дашборд Nginx;
- Stat-панель приложения в состояниях `UP` и `DOWN`.
