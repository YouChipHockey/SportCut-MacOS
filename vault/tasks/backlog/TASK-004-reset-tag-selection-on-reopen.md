---
id: TASK-004
title: Сбрасывать выделение тегов при перезаходе в проект
status: backlog
assignee: -
created: 2026-08-03
updated: 2026-08-03
tags: [VideoPlayer, selection, project-lifecycle]
---

# TASK-004 — Сброс выделения тегов при перезаходе в проект

## Постановка (со слов пользователя)
После перезахода в проект не сбрасывается выделение тегов с прошлого раза — остаётся
старое выделение. Нужно сбрасывать при открытии проекта.

## Кандидаты (уточнить)
- `TimelineDataManager` — состояние выделения (`selectedStampID`, `lastAddedStampID`,
  `stampsSelectedForSportCut`). Проверить, какое именно «выделение тегов» имеется в виду
  (мультивыбор для склейки? выделенный штамп? подсветка в библиотеке?).
- Хук открытия проекта — `WindowsManager` (openVideo/openLiveVideo) — там же, где
  `ClipAutoSaveManager.promptFolderForNewSessionIfNeeded` и
  `VideoMarkupActivityBanner.clearTagMarkupHistoryForNewVideoSession`.

## План (набросок)
- [ ] Определить, какое состояние выделения персистит/остаётся между сессиями проекта.
- [ ] Очищать его при открытии проекта (рядом с уже существующими сбросами сессии).
- [ ] Сборка проходит.
