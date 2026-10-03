# devstation-deploy

Авторазвёртывание локальной AI-инфраструктуры Windows (10/11) с характеристиками не ниже референсной машины:
**16+ ГБ ОЗУ, WSL2 для Docker**. GPU используется автоматически, если он есть (fallback — CPU). Всё конфигурируется под свободное место и диски
определённой машины, используется только бесплатное/локальное железо и офлайн-модели.

Лицензия: [Apache-2.0](LICENSE).

## Что разворачивается

| Компонент | Роль |
|---|---|
| Ollama (GPU-first с fallback на CPU, контекст 16384, каталог моделей на не-системном диске) | локальные модели, MCP `local-llm` |
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
# 0. Инсталлер (bootstrap; сам скачает дистрибутив с GitHub и запустит deploy.ps1).
#    gh и авторизация не нужны: используется публичный codeload-архив.
irm https://github.com/Lab-100/devstation-deploy/releases/latest/download/install.ps1 | iex
#    или из клона:  pwsh install.ps1 -CheckOnly   (см. install.ps1 -?) /  pwsh install.ps1
#    конкретная версия/ветка:  pwsh install.ps1 -Tag v0.3.3   /   -Ref main

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
| `ollama` | env-конфиг по железу (GPU-first), серверный `ollama-server.cmd`, pull `hermes3:3b/8b/3b-cpu` |
| `docker-install` | включение WSL2 (возможна перезагрузка → `-Resume`), установка Docker Desktop |
| `docker-setup` | старт движка, плагины Гордона, Model Runner, pull `smollm2` (+`ai/qwen3` при `-PullQwen3`), импорт профиля dev_workflow, gh auth |
| `tools` | разворачивание INVR-Tools: скачивание релиза `Lab-100/scripts-tools` (`tools/registry`) → `%USERPROFILE%\.devstation`, локер `resolve-tools.ps1` из реестра, линковка `tools\<tool>` (junction) + шимы `tools\*.ps1` + cmd-шимы мониторов |
| `firecrawl` | npm CLI, скиллы, `firecrawl-key.ps1` (шим реестра) |
| `opencode` | venv для `local-llm`, рабочий `opencode.json` (ollama+MCP), глобальный opencode.json (merge), JS-плагины opencode локально и глобально, `AGENTS.md` |
| `mcp` | проверка/импорт профиля `dev_workflow`, глобальный конфиг MCP_DOCKER |
| `rollback` | git-каталог откатов + `%USERPROFILE%\.devstation\rollback-root.txt`, при `-SetupGitHub` — приватный репо (инструмент — шим `backup-util.ps1` из этапа tools) |
| `gordon` | `~\.agents\gordon.yaml`, `%USERPROFILE%\.devstation\gordon-providers.json` (роутер — шим `gordon.ps1`) |
| `startup` | ярлыки автозапуска (ollama-сервер, Docker Desktop) |
| `verify` | итоговый отчёт + `verify-report.json` |

### Перезапуск opencode

После установки и правки конфигов (`opencode.json`, плагины, MCP) текущая
сессия opencode не подхватывает изменения — нужен перезапуск. На развёрнутой
машине есть готовый шим реестра:

```powershell
# из отдельного окна PowerShell или Проводника (текущая сессия opencode оборвётся)
& "$env:USERPROFILE\.devstation\tools\opencode-restart.cmd"

# вариант для скриптов: ждать готовности MCP, ничего не запускать
pwsh -NoProfile -File "$env:USERPROFILE\.devstation\tools\opencode-restart.ps1" -NoLaunch -Json
```

Скрипт перезапускает opencode, поднимает демон-страж `mcp-watchdog` и дожидается
готовности MCP-серверов. Рядом живёт `mcp-watchdog-guardian` — сторож, который
сам поднимает демон-страж, если тот завис (автостарт через HKCU Run).

## Параметры

```
-Stage <name>                только один этап
-Resume                      пропустить уже выполненные этапы
-CheckOnly / -DryRun         проверка / план без изменений
-PullQwen3                   дополнительно тянуть ai/qwen3 (≥5 ГБ RAM)
-SetupGitHub                 создавать приватный репо <Owner>/rollback-catalog
-Owner <owner>               владелец GitHub (по умолчанию Lab-100)
-WorkspaceDir <path>         куда кладётся opencode.json/AGENTS.md (по умолчанию: DEVSTATION_WORKSPACE, иначе существующий каталог оркестрации, иначе корень этого репозитория)
-OllamaModelsDir <path>      каталог моделей (по умолчанию <первый не-системный диск>\OllamaModels)
-RollbackRoot <path>         каталог откатов (по умолчанию <диск моделей>\rollback-catalog)
-NoElevate                   не перезапускаться с UAC
-ForceHardware               продолжить, даже если RAM < 16 ГБ
-ForceOverwriteConfig        перезаписывать существующие opencode.json/AGENTS.md
-SmokeGordon                 прогон Гордона в verify (медленно)
-RegistrySource <path>       реестр из каталога/архива (офлайн-развёртывание)
-RegistryRepo <owner/name>   репозиторий реестра (по умолчанию Lab-100/scripts-tools)
-RegistryRef <ref>           ветка/тег реестра (по умолчанию main)
-UpdateRegistry              перекачать реестр, даже если он уже развёрнут
```

Переменные окружения (удобно для стендов и проверок, чтобы не трогать боевую машину):

| Переменная | Назначение | По умолчанию |
|---|---|---|
| `DEVSTATION_ROOT` | корень развёртывания | `%USERPROFILE%\.devstation` |
| `DEVSTATION_WORKSPACE` | рабочий каталог (opencode.json, AGENTS.md) | существующий каталог оркестрации, иначе корень репозитория |
| `DEVSTATION_STATE_FILE` | файл состояния (для `-Resume`) | `%ProgramData%\devstation-deploy\state.json` |

## Структура репозитория

```
deploy.ps1                      оркестратор (самоподъём UAC, state, resume)
install.ps1                     инсталлер-бустрап: качает codeload-архив по тегу/ветке (без gh и авторизации), распаковывает, запускает deploy.ps1
modules/                        функции этапов (env-check, install-core, ollama, docker-*,
                                tools, firecrawl, opencode, mcp, rollback, gordon, startup, verify)
config/                         шаблоны конфигов + импортируемый профиль dev_workflow.yaml
project.json                    манифест дистрибутива (mode=dist; состав+версии инструментов,
                                параметры registry: repository/ref). Этап tools создаёт манифест на таргете
```

## Реестр инструментов (INVR-Tools)

Копии реестра в этом репозитории **нет** — единственный источник версий инструментов:
репозиторий `Lab-100/scripts-tools` (каталог `tools/registry`).

Этап `tools` на таргете:
1. берёт реестр из `-RegistrySource` (каталог/архив, офлайн) либо скачивает
   `https://codeload.github.com/Lab-100/scripts-tools/tar.gz/refs/heads/<ref>`;
2. копирует его в `%USERPROFILE%\.devstation\tools\registry`;
3. кладёт локер `resolve-tools.ps1` из `registry\resolve-tools\<latest>\`;
4. генерирует манифест таргета из `project.json` этого дистрибутива;
5. линкует `tools\<tool>` (junction → `registry\<tool>\<latest>`) и плоские шимы `tools\*.ps1`;
6. генерирует cmd-шимы мониторов (`infra-graph.cmd`, `opencode-status.cmd`,
   `opencode-monitor.cmd`, `opencode-restart.cmd`).

Шимы переносимые: реестр ищется от расположения самого шима, поэтому в
раскладке дистрибутива (шимы в `.devstation`, реестр в `.devstation\tools\registry`)
и в клоне реестра один и тот же шим работает без правок. Пути каталогов
задаются переменными окружения: `INVR_REGISTRY`, `INVR_LOG_DIR`,
`INVR_ROLLBACK_ROOT`, `INVR_VM_ROOT` (см. README реестра).

Обновить реестр на уже развёрнутой машине: `pwsh deploy.ps1 -Stage tools -UpdateRegistry`.
Версии инструментов меняются только в `project.json` этого репозитория и в самом реестре.

## Известные замечания

- CPU-машина: большие локальные модели медленные — это ожидаемо, модели/hard-limit настроены.
- GPU определяется автоматически (`Get-OllamaLlmLibrary`): Maxwell/Pascal/Volta (CC < 7.5) получают `OLLAMA_LLM_LIBRARY=cuda_v12`,
  т.к. CUDA 13 их не поддерживает и autodetect молча уходит на CPU; CC ≥ 7.5 — autodetect; без NVIDIA — `cpu_avx2`.
  Ручное «лечение» переменной не нужно: и `.cmd`, и User env ставятся одинаково.
  `env-check` показывает дискретную карту, а не встроенную графику (на ноутбуках
  встроенная приходит первой), и выводит её Compute Capability.
- `npm`/`node` ставится штатно (winget); на эталонной машине была ручная nvm-шима — в deploy это не воспроизводится.
- Docker при первом старте может предложить выход из системы/перезагрузку — см. этап `docker-install`.
- Профиль `dev_workflow.yaml` **не содержит токен** — только ссылку на переменную окружения
  `GITHUB_PERSONAL_ACCESS_TOKEN`. Проверено аудитом: в файле и в истории репозитория нет ни одного
  значения ключа. Токен подставляется на целевой машине из своего env.