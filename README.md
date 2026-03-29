# GitHub Actions Self-Hosted Runner

Docker Compose сетап для self-hosted GitHub Actions runner на базе [myoung34/github-runner](https://github.com/myoung34/docker-github-actions-runner).

## Первый запуск — настройка

```bash
docker compose run --rm runner
```

Запустится интерактивный wizard, который спросит:
- Scope (user / org / repo)
- Registration token (не сохраняется нигде — только в памяти контейнера на время регистрации)
- Имя runner'а
- Лейблы

После успешной регистрации wizard сам скажет что делать дальше.

## Обычный запуск (после настройки)

```bash
docker compose up -d
```

Runner стартует с уже сохранённым конфигом — никаких вопросов.

---

## Получение registration token

Токен нужен **только один раз** при регистрации. Wizard покажет точную команду под выбранный scope, но вот краткая шпаргалка:

### user scope
Регистрирует runner для всех личных репозиториев. Использует недокументированный GitHub API.

Нужен **Classic PAT** со скоупами `repo`, `workflow`:
```bash
curl -s -X POST \
  -H "Authorization: Bearer YOUR_CLASSIC_PAT" \
  -H "Accept: application/vnd.github+json" \
  https://api.github.com/user/actions/runners/registration-token \
  | jq -r .token
```

Создать токен: https://github.com/settings/tokens

### org scope
Регистрирует runner для всей организации. Официальный API.

Нужен **Classic PAT** со скоупом `admin:org`:
```bash
curl -s -X POST \
  -H "Authorization: Bearer YOUR_CLASSIC_PAT" \
  -H "Accept: application/vnd.github+json" \
  https://api.github.com/orgs/YOUR_ORG/actions/runners/registration-token \
  | jq -r .token
```

Или через браузер: `https://github.com/organizations/YOUR_ORG/settings/actions/runners/new`

### repo scope
Регистрирует runner для одного репозитория.

Нужен **Classic PAT** со скоупом `repo`:
```bash
curl -s -X POST \
  -H "Authorization: Bearer YOUR_CLASSIC_PAT" \
  -H "Accept: application/vnd.github+json" \
  https://api.github.com/repos/OWNER/REPO/actions/runners/registration-token \
  | jq -r .token
```

Или через браузер: `https://github.com/OWNER/REPO/settings/actions/runners/new`

> Registration token действителен 1 час. После регистрации он больше не нужен — runner хранит свой конфиг в volume и переподключается самостоятельно.

---

## Проверка подключения

### 1. Убедись что контейнер запущен

```bash
docker compose ps
```

Статус должен быть `running`. Если `exited` — смотри логи:

```bash
docker compose logs runner
```

В конце успешного запуска должно быть:

```
√ Connected to GitHub
```

### 2. Найди runner в GitHub UI

**user scope** — личные настройки аккаунта:

GitHub → аватар (правый верхний угол) → Settings → раздел "Code, planning, and automation" → Actions → Runners

**org scope** — настройки организации:

`github.com/YOUR-ORG` → Settings → Actions → Runners

> Вкладка Settings видна только если ты owner организации.

**repo scope** — настройки репозитория:

`github.com/OWNER/REPO` → Settings → Actions → Runners

Runner должен отображаться со статусом **Idle** (зелёная точка).

### 3. Тестовый workflow

Создай в любом репозитории `.github/workflows/test-runner.yml`:

```yaml
name: Test self-hosted runner

on:
  workflow_dispatch:

jobs:
  test:
    runs-on: [self-hosted, linux, x64]
    steps:
      - name: Check runner
        run: |
          echo "Runner works!"
          echo "Host: $(hostname)"
          echo "Date: $(date)"
      - name: Check docker
        run: docker --version
```

Запусти вручную: репозиторий → Actions → "Test self-hosted runner" → Run workflow.

Лейблы в `runs-on` должны совпадать с теми, что ты задал при настройке.

---

## Использование в workflow

```yaml
jobs:
  build:
    runs-on: [self-hosted, linux, x64]
    steps:
      - uses: actions/checkout@v4
      - run: make build
```

---

## Управление

```bash
# Первичная настройка
docker compose run --rm runner

# Перенастроить (заменить регистрацию)
docker compose run --rm runner --setup

# Запустить в фоне
docker compose up -d

# Логи
docker compose logs -f

# Перезапустить
docker compose restart

# Остановить
docker compose down
```

---

## Персистентность

Конфиг runner'а хранится в Docker volume `runner_data`. При рестарте контейнера повторная регистрация не происходит.

Чтобы полностью сбросить и зарегистрировать заново:

```bash
docker compose down
docker volume rm runners_deploy_runner_data
docker compose run --rm runner
```

---

## Устранение проблем

**`Runner is not configured. Run setup first`**

Запусти настройку:
```bash
docker compose run --rm runner
```

**Registration failed**

Токен истёк (действует 1 час) или неверные scopes. Получи новый токен и запусти настройку снова.

**Runner есть в GitHub UI, но workflow не стартует**

Лейблы в `runs-on` не совпадают с теми, что заданы при регистрации. Проверь в GitHub UI какие лейблы у runner'а.

**Docker-in-Docker не работает**

```bash
ls -la /var/run/docker.sock
```

Если файла нет — docker daemon не запущен на хосте.
