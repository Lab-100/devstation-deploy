# devstation-deploy

Авторазвёртывание локальной AI-инфраструктуры Windows (10/11) с характеристиками не ниже референсной машины:
**16+ ГБ ОЗУ, CPU-only (без GPU-ускорения), WSL2 для Docker**. Всё конфигурируется под свободное место и диски
определённой машины, используется только бесплатное/локальное железо и офлайн-модели.

## Что разворачивается

| Компонент | Роль |
|---|---|
| Ollama (CPU-first, контекст 16384, каталог моделей на не-системном диске) | локальные модели, MCP `local-llm` |
| Hermes 3: `3b`, `8b`, `3b-cpu` | бесплатные офлайн-модели |
| Docker Desktop + WSL2 | среда для MCP-контейнеров, Гордона, Model Runner |
| Docker Agent (Гордон) + Model Runner (`smollm2`) | ИИ Docker, бесплатный локальный агент |
| Docker MCP-профиль `dev_workflow` | github-official + memory + puppeteer |
| opencode + провайдер `ollama` + MCP `local-llm`/`firecrawl`/`MCP_DOCKER` | основной оркестратор |
| Firecrawl CLI + скиллы | веб-скрейпинг/поиск/парсинг (ключ или keyless) |
| GitHub CLI (`gh`) | приватные репозитории проектов |
| Каталог откатов `rollback-catalog` + INVR-Tools (реестр+локер+шим `backup-util.ps1`) | политика бэкапа/отката изменений |
| Автозапуск (Startup): ollama-сервер, Docker Desktop | сервисы при загрузке Windows |

## Требования к целевой машине

- Windows 10 22H2+ (build ≥ 19045) или Windows 11.
- ОЗУ ≥ 16 ГБ; ~40 ГБ свободного места на не-системном диске (для моделей и каталога откатов).
- Интернет (для пакетов, моделей, конфигураций).
- Права администратора (UAC при установках).

## Быстрый старт

```powershell
# 0. Инсталлер (bootstrap с GitHub Release; сам скачает-распакует и запустит deploy.ps1):
irm https://github.com/Lab-100/devstation-deploy/releases/latest/download/install.ps1 | iex
#    или из клона:  pwsh install.ps1 -CheckOnly   (см. install.ps1 -?) /  pwsh install.ps1

# 1. Склонировать:        (git clone <private>/devstation-deploy && cd devstation-deploy)
cd devstation-deploy
pwsh deploy.ps1 -CheckOnly        # предварительная проверка готовности машины
pwsh deploy.ps1 -DryRun           # план без изменений

# 2. Полный деплой (при перезапуске с UAC запросит подтверждение)
pwsh deploy.ps1                   # или: pwsh deploy.ps1 -PullQwen3 -SetupGitHub

# 3. Если система запросила перезагрузку (WSL2): перезагрузиться, затем продолжить:
pwsh deploy.ps1 -Resume
```

Деплойер идемпотентный: повторный запуск пропускает выполненные этапы, состояние хранится в
`%ProgramData%\devstation-deploy\state.json`, логи команд пишутся прямо в консоль.

## Одноразовые ручные шаги (после деплоя)

1. **`gh auth login`** — если `GITHUB_PERSONAL_ACCESS_TOKEN` не задан (device-flow, ввод кода).
2. **Firecrawl — опционально**: без ключа работает keyless; постоянный ключ:
   `firecrawl-key.ps1 -Mode Init` → клик Authorize в браузере → `-Mode Poll`.
3. **Облачные ключи Гордона** — заполнить `%USERPROFILE%\.devstation\gordon-providers.json`
   (модель по умолчанию — локальная `smollm2`, облако подключается автоматически при наличии ключей).

## Этапы

| Этап | Что делает |
|---|---|
| `env-check` | ОС/RAM/диски/winget/сеть/GPU |
| `install-core` | pwsh7, git, Node LTS, Python 3.12, Ollama, gh, Docker Desktop, opencode (`npm i -g opencode-ai`) |
| `ollama` | env-конфиг CPU, серверный `ollama-server.cmd`, pull `hermes3:3b/8b/3b-cpu` |
| `docker-install` | включение WSL2 (возможна перезагрузка → `-Resume`), установка Docker Desktop |
| `docker-setup` | старт движка, плагины Гордона, Model Runner, pull `smollm2` (+`ai/qwen3` при `-PullQwen3`), импорт профиля dev_workflow, gh auth |
| `tools` | разворачивание INVR-Tools: реестр `registry/` + локер `resolve-tools.ps1` → `%USERPROFILE%\.devstation`, линковка `tools\<tool>` (junction) + шимы `tools\*.ps1` |
| `firecrawl` | npm CLI, скиллы, `firecrawl-key.ps1` (шим реестра) |
| `opencode` | venv для `local-llm`, рабочий `opencode.json` (ollama+MCP), глобальный opencode.json, `AGENTS.md` |
| `mcp` | проверка/импорт профиля `dev_workflow`, глобальный конфиг MCP_DOCKER |
| `rollback` | git-каталог откатов + `%USERPROFILE%\.devstation\rollback-root.txt`, при `-SetupGitHub` — приватный репо (инструмент — шим `backup-util.ps1` из этапа tools) |
| `gordon` | `~\.agents\gordon.yaml`, `%USERPROFILE%\.devstation\gordon-providers.json` (роутер — шим `gordon.ps1`) |
| `startup` | ярлыки автозапуска (ollama-сервер, Docker Desktop) |
| `verify` | итоговый отчёт + `verify-report.json` |

## Параметры

```
-Stage <name>                только один этап
-Resume                      пропустить уже выполненные этапы
-CheckOnly / -DryRun         проверка / план без изменений
-PullQwen3                   дополнительно тянуть ai/qwen3 (≥5 ГБ RAM)
-SetupGitHub                 создавать приватный репо <Owner>/rollback-catalog
-Owner <owner>               владелец GitHub (по умолчанию Lab-100)
-WorkspaceDir <path>         куда кладётся opencode.json/AGENTS.md (по умолчанию C:\Scripts)
-OllamaModelsDir <path>      каталог моделей (по умолчанию <первый не-системный диск>\OllamaModels)
-RollbackRoot <path>         каталог откатов (по умолчанию <диск моделей>\rollback-catalog)
-NoElevate                   не перезапускаться с UAC
-ForceHardware               продолжить, даже если RAM < 16 ГБ
-ForceOverwriteConfig        перезаписывать существующие opencode.json/AGENTS.md
-SmokeGordon                 прогон Гордона в verify (медленно)
```

## Структура репозитория

```
deploy.ps1                      оркестратор (самоподъём UAC, state, resume)
install.ps1                     инсталлер-бустрап: скачивает zip Release, распаковывает, запускает deploy.ps1
modules/                        функции этапов (env-check, install-core, ollama, docker-*,
                                tools, firecrawl, opencode, mcp, rollback, gordon, startup, verify)
config/                         шаблоны конфигов + импортируемый профиль dev_workflow.yaml
tools/                          дистрибутив INVR-Tools:
  registry/                       снимок реестра registry\<tool>\<version>\ + tool.json + latest.txt
  resolve-tools.ps1               bootstrap локера (копия актуальной версии из registry\resolve-tools)
project.json                    манифест проекта (mode=dist; этап tools создаёт манифест на таргете)
```

## Обновление инструментов в дистрибутиве

`tools/registry` — это снимок реестра `invr-tools` (источник: `Lab-100/scripts-tools`).
Чтобы синхронизировать дистрибутив: скопировать `registry\*` и `registry\resolve-tools\<latest>\resolve-tools.ps1`
из источника в `tools/` и закоммитить. Этап `tools` на таргете разворачивает реестр в
`%USERPROFILE%\.devstation\tools\registry`, линкует инструменты (junction) и собирает плоские
шимы `tools\*.ps1` — пути вызова сохраняются как раньше (`tools\backup-util.ps1` и т.д.).

## Известные замечания

- CPU-машина: большие локальные модели медленные — это ожидаемо, модели/hard-limit настроены.
- `npm`/`node` ставится штатно (winget); на эталонной машине была ручная nvm-шима — в deploy это не воспроизводится.
- Docker при первом старте может предложить выход из системы/перезагрузку — см. этап `docker-install`.
- Профиль `dev_workflow.yaml` секретен (содержит декларацию токена GitHub) — репозиторий деплоя держать приватным.