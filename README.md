# GitHub Actions Self-Hosted Runner

Docker Compose сетап для self-hosted GitHub Actions runner на базе [myoung34/github-runner](https://github.com/myoung34/docker-github-actions-runner).

## Быстрый старт

```bash
cp .env.example .env
# отредактируй .env
docker compose up -d --build
```

---

## Получение токена

Нужен **Personal Access Token (classic)** — не fine-grained, потому что fine-grained не поддерживают Actions API для user-level runner'ов.

1. Открой: **GitHub → Settings → Developer settings → Personal access tokens → Tokens (classic)**
   Прямая ссылка: https://github.com/settings/tokens

2. Нажми **Generate new token (classic)**

3. Выбери scopes:
   - `repo` — полный доступ к репозиториям (нужен для регистрации runner'а)
   - `workflow` — доступ к GitHub Actions workflows

4. Установи срок действия (рекомендую 1 год или `No expiration` для сервера)

5. Скопируй токен — он показывается только один раз

6. Вставь в `.env`:
   ```
   ACCESS_TOKEN=ghp_xxxxxxxxxxxxxxxxxxxx
   ```

> Если токен истёк или отозван — runner перестанет регистрироваться при рестарте. Контейнер упадёт с ошибкой в логах.

---

## Конфигурация (.env)

Скопируй `.env.example` в `.env` и заполни:

| Переменная | Обязательная | Описание |
|---|---|---|
| `ACCESS_TOKEN` | да | Personal Access Token (classic) |
| `GITHUB_USERNAME` | да | Твой GitHub username |
| `RUNNER_SCOPE` | нет | `user` (по умолчанию) или `org` |
| `RUNNER_NAME` | нет | Имя runner'а в GitHub UI (по умолчанию `my-runner`) |
| `LABELS` | нет | Лейблы через запятую (по умолчанию `self-hosted,linux,x64`) |
| `ORG_NAME` | нет | Только для `RUNNER_SCOPE=org`, если org name отличается от username |

### Пример заполненного .env

```env
ACCESS_TOKEN=ghp_xxxxxxxxxxxxxxxxxxxx
GITHUB_USERNAME=your-username
RUNNER_SCOPE=user
RUNNER_NAME=home-server
LABELS=self-hosted,linux,x64
```

---

## Режимы работы

### user mode (по умолчанию)

```env
RUNNER_SCOPE=user
```

Runner регистрируется на уровне аккаунта и доступен **во всех личных репозиториях**. Использует недокументированный GitHub API (`POST /user/actions/runners/registration-token`).

Виден здесь: **GitHub → Settings → Actions → Runners**
Прямая ссылка: https://github.com/settings/actions/runners

### org mode

```env
RUNNER_SCOPE=org
ORG_NAME=your-org-name  # опционально, если отличается от GITHUB_USERNAME
```

Runner регистрируется на уровне организации. Использует официальный API myoung34/github-runner.

Виден здесь: **GitHub → [Org] → Settings → Actions → Runners**

---

## Проверка подключения

### Шаг 1 — убедись, что контейнер запустился

```bash
docker compose ps
```

Статус должен быть `running`, не `exited`. Если `exited` — смотри логи:

```bash
docker compose logs github-runner
```

В логах успешного запуска будет что-то вроде:

```
[runner-init] Starting GitHub Actions runner in scope: user
[runner-init] Mode: user-level (undocumented user scope via personal API)
[runner-init] Requesting registration token for user: your-username
[runner-init] Registration token obtained successfully.
[runner-init] Registering runner at: https://github.com/your-username
...
√ Connected to GitHub
```

### Шаг 2 — найди runner в GitHub UI

**Для user mode (`RUNNER_SCOPE=user`):**

Открой: **GitHub → (аватар) → Settings → Actions → Runners**

Путь вручную: github.com → правый верхний угол → Your profile → Settings → слева внизу раздел "Code, planning, and automation" → Actions → Runners

Должен появиться runner с именем, которое ты задал в `RUNNER_NAME`, со статусом **Idle** (зелёная точка).

**Для org mode (`RUNNER_SCOPE=org`):**

Открой: **GitHub → [название org] → Settings → Actions → Runners**

Путь: github.com/YOUR-ORG → вкладка Settings → слева "Actions" → Runners

> Вкладка Settings видна только если ты owner организации.

### Шаг 3 — запусти тестовый workflow

Создай в любом репозитории файл `.github/workflows/test-runner.yml`:

```yaml
name: Test self-hosted runner

on:
  workflow_dispatch:

jobs:
  test:
    runs-on: [self-hosted, linux, x64]
    steps:
      - run: echo "Runner работает! Hostname: $(hostname)"
      - run: docker --version
```

Затем: **репозиторий → Actions → "Test self-hosted runner" → Run workflow**

Если job завершился успешно — runner полностью работает, включая docker-in-docker.

---

## Использование runner'а в workflow

После регистрации используй лейблы в `runs-on`:

```yaml
jobs:
  build:
    runs-on: [self-hosted, linux, x64]
    steps:
      - uses: actions/checkout@v4
      - run: echo "Running on self-hosted runner"
```

Лейблы должны совпадать с тем, что указано в `LABELS` в `.env`.

---

## Управление

```bash
# Запустить
docker compose up -d --build

# Посмотреть логи
docker compose logs -f

# Остановить (runner деregistрируется)
docker compose down

# Перезапустить
docker compose restart

# Пересобрать после изменений
docker compose up -d --build
```

---

## Персистентность

Конфиг runner'а хранится в Docker volume `runner-data` (путь внутри контейнера: `/runner-data`). При рестарте контейнера повторная регистрация не происходит — runner просто переподключается к GitHub.

Чтобы **принудительно перерегистрировать** runner:

```bash
docker compose down
docker volume rm github-runner_runner-data
docker compose up -d --build
```

---

## Устранение проблем

**Контейнер падает сразу после запуска**

Смотри логи:
```bash
docker compose logs github-runner
```

Частые причины:
- `ACCESS_TOKEN not set` — не заполнен `.env`
- `Failed to get registration token` — токен невалидный или истёк, либо нет нужных scopes
- `GITHUB_USERNAME is required` — не указан username

**Runner появился в GitHub, но workflow не запускается**

Проверь, что лейблы в `runs-on` в workflow совпадают с `LABELS` в `.env`.

**Docker-in-Docker не работает**

Убедись, что сокет доступен на хосте:
```bash
ls -la /var/run/docker.sock
```

Если нет — docker daemon не запущен на хосте.
