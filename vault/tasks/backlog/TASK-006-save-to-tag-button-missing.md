---
id: TASK-006
title: Кнопка «Сохранить на тег» пропадает, хотя плейхэд пересекает теги
status: backlog
assignee: -
created: 2026-08-03
updated: 2026-08-03
tags: [VideoPlayer, editor, screenshots, save-to-tag]
---

# TASK-006 — «Сохранить на тег» не появляется для всех тегов под плейхэдом

## Постановка (со слов пользователя)
При добавлении рисунка опция «сохранить на тег» появляется не для всех тегов. На видео
из тикета видно: в текущий момент несколько тегов (плейхэд их пересекает), но при открытии
редактора кнопки «сохранить на тег» нет. Прерывисто, стабильно не воспроизвёл.

## Находки (расследование)
- Кнопка `editorSaveToTag` показывается ТОЛЬКО если `getIntersectingStamps()` непуст:
  `VideoPlayerView.swift:407` — `if !isEditingExistingScreenshot && !getIntersectingStamps().isEmpty`.
- Пересечение считается в ДВУХ копиях (одинаково): `VideoPlayerViewModel.getIntersectingStamps()`
  (VideoPlayerViewModel.swift:988) и `VideoPlayerView.intersectingStamps` (VideoPlayerView.swift:855):
  `videoTime >= stamp.timeStartSeconds && videoTime <= stamp.timeFinishSeconds`.
- `videoTime` = `state.editorScreenshotVideoTime`, выставляется при открытии редактора
  (VideoPlayerViewModel.swift:625/652/692), сбрасывается в 0 при закрытии (:808).
- Инстант-тегам ставится спан `[t - defaultTimeBefore, t + defaultTimeAfter]` (по умолч. 5/3с,
  TagLibraryView:929–930), т.е. НЕ нулевая ширина по умолчанию.

## Гипотезы (проверить)
1. Рассинхрон времени: `editorScreenshotVideoTime` не совпадает с реальным плейхэдом в
   каком-то режиме (live/review) → пересечение пусто. Уточнить: баг в live или в файловой разметке?
2. Если `defaultTimeBefore/After == 0` (юзер настроил) — инстант-тег нулевой ширины,
   строгая проверка `>=/<=` его теряет.

## План (набросок)
- [ ] Уточнить у пользователя: live или файловая разметка; теги-интервалы или точечные.
- [ ] Добавить допуск в пересечение (ловить нулевую ширину/погрешность) + дедуп двух копий.
- [ ] Проверить корректность `editorScreenshotVideoTime` в проблемном режиме.
