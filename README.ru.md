# <img src="Resources/AppIcon.png" alt="" width="48" align="center"> Silicon Reader

[🇬🇧 English](README.md) | 🇷🇺 Русский

Быстрая читалка PDF и DjVu для macOS на Apple Silicon с управлением с клавиатуры, в духе
[SumatraPDF](https://github.com/sumatrapdfreader/sumatrapdf): нативный Swift + AppKit поверх
тех же движков, что использует Sumatra.

![CI](https://github.com/Arroheim/silicon_reader/actions/workflows/ci.yml/badge.svg)
[![Release](https://img.shields.io/github/v/release/Arroheim/silicon_reader?sort=semver)](https://github.com/Arroheim/silicon_reader/releases/latest)
![macOS](https://img.shields.io/badge/macOS-14%2B-black?logo=apple)
![Apple Silicon](https://img.shields.io/badge/Apple%20Silicon-arm64-blue)
![Swift](https://img.shields.io/badge/Swift-6-orange?logo=swift)
![License](https://img.shields.io/badge/license-AGPL--3.0-green.svg)

![Silicon Reader](docs/assets/screenshot-light.png)

## ✨ Возможности

- 📖 **PDF и DjVu** — MuPDF 1.28 для PDF, djvudec (собственный декодер Sumatra) для DjVu
- 🧭 **Режимы Sumatra** — одна страница, разворот, книжный; непрерывно или постранично
- 🔍 **Масштаб как в Sumatra** — по странице / ширине / высоте / содержимому, 100 %,
  от 8,33 % до 6400 % шагами Sumatra, pinch и ⌘-прокрутка на трекпаде
- ⌨️ **Клавиатура Sumatra** в мак-варианте — `j` `k` `n` `p` `z` `c` `[` `]`, палитра ⌘K,
  `?` — полный список
- 🗂️ **Вкладки, оглавление и избранное** — нативные вкладки, оглавление и избранное в сайдбаре
- 🖼️ **Миниатюры страниц** в сайдбаре, которые следуют за текущей страницей
- 📂 **Open Recent и drag-and-drop** — файлы, брошенные на окно, открываются вкладками
- ⚙️ **Настройки** — режим и масштаб по умолчанию, что запоминать, восстановление сессии, автоперезагрузка
- 🏠 **Домашняя страница** с миниатюрами «Frequently Read»
- 🔎 **Поиск** с подсветкой всех совпадений, учёт регистра, ⌘G / ⇧⌘G
- ✂️ **Выделение и копирование текста**, двойной/тройной клик, масштаб по выделению, ссылки
- 💾 **Всё помнит** — страницу, масштаб и режим для каждого документа, восстанавливает сессию
- 🔄 **Сама перезагружает** документ, когда файл меняется на диске (удобно с LaTeX)
- 🖨️ **Печать**, свойства документа, режим презентации и полный экран, инверсия цветов
- ⚡ **Фоновый рендер кусками** — сначала чётко то, на что смотрите, остальное следом
- 🧪 **Протестирована**: unit-тесты, end-to-end тесты, которые управляют настоящим приложением,
  и пакетная проверка на библиотеке из 1 300 книг

<p align="center">
  <img src="docs/assets/screenshot-dark.png" width="49%" alt="Разворот в тёмной теме">
  <img src="docs/assets/screenshot-search.png" width="49%" alt="Поиск с подсветкой">
</p>

## 📥 Скачать

Скачайте DMG из [последнего релиза](https://github.com/Arroheim/silicon_reader/releases/latest),
откройте его и перетащите **SiliconReader** в **Applications** («Программы»).

Приложение пока не нотаризовано Apple, поэтому macOS заблокирует первый запуск. Либо откройте
**Системные настройки → Конфиденциальность и безопасность** и нажмите **Всё равно открыть**,
либо выполните:

```bash
xattr -dr com.apple.quarantine /Applications/SiliconReader.app
```

Нужна macOS 14 или новее на Apple Silicon.

## 🚀 Быстрый старт (из исходников)

Достаточно **Command Line Tools** (`xcode-select --install`), полный Xcode не нужен.

```bash
git clone --recurse-submodules --shallow-submodules https://github.com/Arroheim/silicon_reader.git
cd silicon_reader
make run FILE=path/to/book.djvu
```

Первая сборка компилирует MuPDF (около минуты), дальше — секунды.

## ⌨️ Клавиатура

Самое нужное; в приложении `?` покажет все сочетания.

| Клавиши | Действие |
|---|---|
| `j` `k` / `↓` `↑` | Прокрутка |
| `Space` / `⇧Space` | Экран вниз / вверх |
| `n` `p` | Следующая / предыдущая страница |
| `Home` `End`, `⌘↑` `⌘↓` | Первая / последняя страница |
| `g`, `⌥⌘G` | Перейти к странице |
| `⌘[` `⌘]`, `⌫` | Назад / вперёд |
| `⌘9` `⌘2` `⌘3` `⌘0` | По странице / ширине / содержимому, 100 % |
| `⌘+` `⌘-`, `z` | Крупнее / мельче, перебор режимов подгонки |
| `⌘6` `⌘7` `⌘8`, `c` | Одна страница / разворот / книжный, непрерывно вкл/выкл |
| `[` `]` | Поворот |
| `⌘F`, `⌘G` `⇧⌘G` | Поиск, следующее / предыдущее совпадение |
| `⌘K` (или `>` `@` `#` `$` `%`) | Палитра команд (команды, вкладки, недавние, избранное, оглавление) |
| `⌘D` | В избранное |
| `⌃⌘S` | Показать / скрыть сайдбар |
| `⌥⌘2` / `⌥⌘3` | Сайдбар: миниатюры / оглавление |
| `⌘,` | Настройки |
| `⇧⌘F`, `f` | Презентация, полный экран |
| `⇧I` | Инверсия цветов |
| `⇧⌘→` `⇧⌘←` | Следующий / предыдущий файл в папке |

## 🏗️ Архитектура

```
Sources/
├── CMuPDF/          C-обёртка над MuPDF (fz_try/fz_catch нельзя вызывать из Swift)
├── ReaderCore/      без AppKit, полностью покрыт unit-тестами
│   ├── Layout/      раскладка страниц и масштаб по модели SumatraPDF, геометрия страниц
│   ├── Text/        выделение, поиск по документу, кеш текста
│   ├── Commands/    таблица команд клавиатуры и меню, поиск в палитре
│   ├── Library/     история, избранное, состояние файлов, сессия, слежение за файлами
│   ├── Control/     протокол отладочного канала управления (для e2e-тестов)
│   └── *Engine.swift  движки документов MuPDF и DjVu
├── SiliconReader/   AppKit-приложение: холст, окно, тулбар, сайдбар, домашняя страница, палитра
└── ReaderCheck/     пакетная проверка библиотеки документов
Vendor/
├── mupdf/           git submodule, зафиксирован на релизном теге
└── djvudec/         однофайловый декодер DjVu (+ локальные патчи)
Tests/
├── ReaderCoreTests/ unit-тесты
└── E2ETests/        управляют собранным приложением через сокет
```

## 🧪 Разработка

| Команда | Что делает |
|---|---|
| `make deps` | Скачивает submodule'ы и собирает MuPDF статическими библиотеками (один раз) |
| `make build` | `swift build` (`CONFIG=release` — оптимизированная сборка) |
| `make test` | Unit-тесты |
| `make e2e` | Собирает приложение и гоняет end-to-end тесты против него |
| `make lint` / `make format` | Проверка / переформатирование `swift format` |
| `make app` | Release-сборка в `build/SiliconReader.app` |
| `make smoke` | Открывает тестовые документы в нескольких режимах и сохраняет снимки окна |
| `make check-library DIR=…` | Открывает каждый PDF/DjVu в папке, рендерит выборочные страницы (или все с `ALL_PAGES=1`), выдаёт отчёт о сбоях |
| `make dmg` | Упаковывает приложение в `build/SiliconReader-<версия>.dmg` |
| `make release VERSION=x.y.z` | Проверяет, тестирует и ставит тег релиза |
| `make run FILE=…` | Собирает и открывает документ |

**End-to-end тесты** запускают настоящее приложение с `-control <сокет>` и общаются с ним JSON'ом
через Unix-сокет: нажимают клавиши через настоящее меню и обработку клавиш, а проверяют
сообщённое состояние (страница, масштаб, выделение, совпадение поиска, вкладки), а не пиксели.
Протокол — в `Sources/ReaderCore/Control/ControlProtocol.swift`.

**Отладочные флаги** для снимков и тестов: `-snapshot out.png`, `-actions a,b`, `-find текст`,
`-palette текст`, `-printToPDF out.pdf`, `-library path.json` (тесты не трогают вашу историю),
`-persist YES`, `-snapshotAfter N`.

> С тулчейном Command Line Tools голый `swift test` иногда падает с
> `plugin for module 'TestingMacros' not found`. Makefile подключает плагин явно —
> запускайте `make test`.

## 🚢 Релизы

1. Переименуйте `## [Unreleased]` в [CHANGELOG.md](CHANGELOG.md) в `## [x.y.z] - ГГГГ-ММ-ДД` и закоммитьте.
2. `make release VERSION=x.y.z` — проверит дерево и changelog, прогонит lint, unit и e2e, поставит тег `vx.y.z`.
3. `git push origin vx.y.z` — [workflow релиза](.github/workflows/release.yml) ещё раз прогонит тесты,
   соберёт DMG и опубликует GitHub Release с ним и разделом changelog в качестве описания.

## 📦 Зависимости

| Компонент | Версия | Лицензия | Как подключён |
|---|---|---|---|
| [MuPDF](https://mupdf.com) | 1.28.5 | AGPL-3.0 | git submodule, статическая библиотека |
| [djvudec](https://github.com/kjk/djvudec) | `cfd3251` + [локальный патч](Vendor/djvudec/PATCHES.md) | MIT | `djvu.c` / `djvu.h` в репозитории |
| Swift Testing | из тулчейна | Apache-2.0 | unit и e2e тесты |

Тулчейн: Swift 6, macOS 14+ SDK, Apple Silicon.

## 🗺️ Планы

См. [TODO.md](TODO.md): чек-лист релиза 1.0, что ещё отличает приложение от SumatraPDF
(аннотации, формы, SyncTeX, настройки и темы…) и фаза 2 — EPUB, MOBI, FB2, XPS, CBZ/CBR.

## 🤝 Участие в разработке

1. Сделайте форк репозитория
2. Создайте ветку (`git checkout -b feature/amazing-feature`)
3. Прогоните `make lint test e2e`
4. Закоммитьте изменения по [Conventional Commits](https://www.conventionalcommits.org/)
5. Запушьте ветку и откройте Pull Request

## 🙏 Благодарности

[SumatraPDF](https://github.com/sumatrapdfreader/sumatrapdf) — Кшиштоф Ковальчик и участники
проекта: его поведение, режимы и раскладка клавиш — спецификация, по которой сделано это приложение.

## 📝 Лицензия

[AGPL-3.0-or-later](LICENSE) — этого требует MuPDF. djvudec — под MIT. Тестовые файлы взяты из
DjVuLibre и SumatraPDF под GPL (см.
[Tests/ReaderCoreTests/Fixtures/README.md](Tests/ReaderCoreTests/Fixtures/README.md)).
