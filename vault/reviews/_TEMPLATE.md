---
task: TASK-000
reviewer: reviewer
date: YYYY-MM-DD
verdict: changes-requested   # approved | changes-requested | blocked
---

# Ревью TASK-000

## Что ревьюил
Ссылка на задачу [[../tasks/…]], список изменённых файлов / дифф.

## Сборка
- [ ] `xcodebuild … build CODE_SIGNING_ALLOWED=NO` → BUILD SUCCEEDED

## Замечания
| # | Файл:строка | Severity | Что не так | Предложение |
|---|-------------|----------|------------|-------------|
| 1 | `file.swift:42` | high/med/low | … | … |

## Соответствие конвенциям
- [[../knowledge/conventions/code-style]] — да/нет
- [[../knowledge/conventions/localization]] — если трогали строки

## Вердикт
approved / changes-requested / blocked — и почему.
