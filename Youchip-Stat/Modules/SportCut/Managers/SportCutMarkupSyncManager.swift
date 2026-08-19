//
//  SportCutMarkupSyncManager.swift
//  Youchip-Stat
//
//  Связь разметки и режима просмотра: разметка проекта переносится в сессии просмотра, куда этот
//  проект добавлен.
//
//  ВАЖНО (перф): синк НЕ живой. Раньше он висел на `.projectTimelinesDidChange` и срабатывал на
//  каждое изменение разметки — а идущий счётчик обновляет свой штамп раз в секунду, и каждый раз
//  пересобирались ВСЕ сессии просмотра под проект (плюс запись на диск). На больших проектах это
//  давало посекундный рывок. Теперь синк — только в моменты, когда он действительно нужен:
//    • вход в проект просмотра  — `SportCutSessionManager.syncAllProjectSources(sessionID:)`;
//    • вход в проект разметки   — `syncCurrentMarkupProject()`;
//    • выход из проекта разметки (после финализации счётчиков) — `syncCurrentMarkupProject()`;
//    • кнопка «Обновить разметку в просмотре» в окне полного контроля;
//    • открытие окна просмотра из разметки (WindowsManager делает это явно).
//
//  Плейлисты сессии при синке НЕ трогаются: это уже вынесенные отдельно клипы, ими распоряжается
//  пользователь (и они несут своё содержимое с собой — см. `SportCutClockSnapshot`).
//

import Foundation

final class SportCutMarkupSyncManager {

    static let shared = SportCutMarkupSyncManager()

    private init() {}

    /// Оставлено ради единой точки инициализации в `AppSetupManager`. Подписки больше нет —
    /// живой синк убран намеренно (см. комментарий к файлу).
    func start() {}

    /// Переносит ТЕКУЩУЮ разметку открытого проекта во все сессии просмотра, где он есть.
    /// Возвращает true, если что-то реально изменилось.
    @discardableResult
    func syncCurrentMarkupProject() -> Bool {
        let projectID = WindowsManager.shared.liveVideoId ?? WindowsManager.shared.currentVideoId
        return syncMarkupProject(projectID: projectID, timelines: TimelineDataManager.shared.lines)
    }

    /// Переносит переданную разметку проекта во все сессии просмотра, где он есть.
    @discardableResult
    func syncMarkupProject(projectID: String, timelines: [TimelineLine]) -> Bool {
        guard !projectID.isEmpty else { return false }
        // Проект не добавлен ни в одну сессию просмотра — самый частый случай, выходим сразу.
        guard SportCutSessionManager.shared.sessions.contains(where: { session in
            session.sources.contains { $0.projectID == projectID }
        }) else { return false }
        return SportCutSessionManager.shared.syncProjectTimelines(projectID: projectID, timelines: timelines)
    }

    /// Совместимость с прежними вызовами «доведи накопленное прямо сейчас» (перед открытием окна
    /// просмотра, при финализации лайва). Теперь это просто явный синк текущего проекта.
    func flushNow() {
        syncCurrentMarkupProject()
    }
}
