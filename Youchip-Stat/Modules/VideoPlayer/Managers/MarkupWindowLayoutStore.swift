//
//  MarkupWindowLayoutStore.swift
//  Youchip-Stat
//

import AppKit
import Combine

/// Запоминает положение и размер окон трёхоконного раздела разметки, чтобы при
/// следующем открытии проекта разложить их так же, как оставил пользователь.
///
/// Кадры пишутся в UserDefaults с небольшой задержкой (во время перетаскивания
/// окна уведомления сыплются десятками), а перед закрытием окон сбрасываются
/// принудительно через `flush()`.
///
/// Режим блокировки (`isLocked`): при включении снимается «слепок» текущего
/// расположения окон. Пока блокировка активна, при каждом открытии проекта окна
/// расставляются по этому слепку — даже если пользователь потом их двигал.
/// Выключение блокировки возвращает обычное поведение «последняя позиция».
final class MarkupWindowLayoutStore: ObservableObject {

    static let shared = MarkupWindowLayoutStore()

    enum Role: String, CaseIterable {
        case video = "markupVideo"
        case control = "markupControl"
        case tagLibrary = "markupTagLibrary"
    }

    private let defaultsKeyPrefix = "markupWindowLayout."
    private let lockedKeyPrefix = "markupWindowLockedLayout."
    private let lockedFlagKey = "markupWindowsLocked"
    private let saveDelay: TimeInterval = 0.4
    /// Меньше этого окно считаем «схлопнутым» и не восстанавливаем.
    private let minimumRestorableSide: CGFloat = 200

    private var frames: [Role: NSRect] = [:]
    /// Слепок расположения на момент включения блокировки.
    private var lockedFrames: [Role: NSRect] = [:]
    /// Активна ли блокировка раскладки. Наблюдается тумблером в UI разметки.
    @Published private(set) var isLocked: Bool = false
    private var observers: [NSObjectProtocol] = []
    private var pendingSave: DispatchWorkItem?

    private init() {
        for role in Role.allCases {
            if let stored = UserDefaults.standard.string(forKey: defaultsKeyPrefix + role.rawValue) {
                let frame = NSRectFromString(stored)
                if frame.width > 0, frame.height > 0 {
                    frames[role] = frame
                }
            }
            if let storedLocked = UserDefaults.standard.string(forKey: lockedKeyPrefix + role.rawValue) {
                let frame = NSRectFromString(storedLocked)
                if frame.width > 0, frame.height > 0 {
                    lockedFrames[role] = frame
                }
            }
        }
        isLocked = UserDefaults.standard.bool(forKey: lockedFlagKey)
    }

    // MARK: - Восстановление

    /// Слепок блокировки снят для всех трёх окон.
    private var hasCompleteLockedSnapshot: Bool {
        Role.allCases.allSatisfy { isRestorable(lockedFrames[$0]) }
    }

    /// Есть ли раскладка, которую можно применить при открытии.
    /// Если блокировка активна и слепок валиден — используется слепок,
    /// иначе — последняя позиция. Частичное восстановление не делаем: окна
    /// перекрыли бы друг друга.
    var hasCompleteLayout: Bool {
        if isLocked, hasCompleteLockedSnapshot { return true }
        return Role.allCases.allSatisfy { isRestorable(frames[$0]) }
    }

    /// Кадр, который нужно применить при открытии окна: слепок блокировки, если
    /// она активна и валидна, иначе — последняя запомненная позиция.
    func savedFrame(for role: Role) -> NSRect? {
        if isLocked, hasCompleteLockedSnapshot,
           let locked = lockedFrames[role], isRestorable(locked) {
            return locked
        }
        guard let frame = frames[role], isRestorable(frame) else { return nil }
        return frame
    }

    // MARK: - Блокировка

    /// Включает/выключает блокировку раскладки. При включении снимает слепок
    /// текущего расположения окон и сохраняет его; при выключении слепок удаляется.
    func setLocked(_ locked: Bool) {
        guard locked != isLocked else { return }
        isLocked = locked
        UserDefaults.standard.set(locked, forKey: lockedFlagKey)

        if locked {
            lockedFrames = frames
            for role in Role.allCases {
                if let frame = lockedFrames[role], frame.width > 0, frame.height > 0 {
                    UserDefaults.standard.set(NSStringFromRect(frame), forKey: lockedKeyPrefix + role.rawValue)
                } else {
                    UserDefaults.standard.removeObject(forKey: lockedKeyPrefix + role.rawValue)
                }
            }
        } else {
            lockedFrames.removeAll()
            for role in Role.allCases {
                UserDefaults.standard.removeObject(forKey: lockedKeyPrefix + role.rawValue)
            }
        }
    }

    /// Кадр пригоден, если он не вырожден и заметная часть окна попадает на
    /// один из подключённых экранов (конфигурация мониторов могла поменяться).
    private func isRestorable(_ frame: NSRect?) -> Bool {
        guard let frame,
              frame.width >= minimumRestorableSide,
              frame.height >= minimumRestorableSide else { return false }

        let visibleArea = NSScreen.screens.reduce(CGFloat(0)) { partial, screen in
            let intersection = screen.visibleFrame.intersection(frame)
            return partial + (intersection.isNull ? 0 : intersection.width * intersection.height)
        }
        let frameArea = frame.width * frame.height
        guard frameArea > 0 else { return false }

        return visibleArea / frameArea >= 0.5
    }

    // MARK: - Слежение

    /// Подписывается на перемещение/изменение размера окна и запоминает его кадр.
    func track(_ window: NSWindow?, as role: Role) {
        guard let window else { return }

        frames[role] = window.frame

        for name in [NSWindow.didMoveNotification, NSWindow.didResizeNotification, NSWindow.willCloseNotification] {
            let observer = NotificationCenter.default.addObserver(
                forName: name,
                object: window,
                queue: .main
            ) { [weak self, weak window] _ in
                guard let self, let window else { return }
                self.frames[role] = window.frame
                if name == NSWindow.willCloseNotification {
                    self.flush()
                } else {
                    self.scheduleSave()
                }
            }
            observers.append(observer)
        }
    }

    /// Снимает подписки — вызывается при закрытии сессии разметки.
    func stopTracking() {
        flush()
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        observers.removeAll()
    }

    // MARK: - Сохранение

    private func scheduleSave() {
        pendingSave?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.persist() }
        pendingSave = work
        DispatchQueue.main.asyncAfter(deadline: .now() + saveDelay, execute: work)
    }

    func flush() {
        pendingSave?.cancel()
        pendingSave = nil
        persist()
    }

    private func persist() {
        for (role, frame) in frames {
            guard frame.width > 0, frame.height > 0 else { continue }
            UserDefaults.standard.set(NSStringFromRect(frame), forKey: defaultsKeyPrefix + role.rawValue)
        }
    }

    /// Забыть раскладку (в т.ч. слепок блокировки) и открыть окна по умолчанию
    /// при следующем запуске.
    func reset() {
        pendingSave?.cancel()
        pendingSave = nil
        frames.removeAll()
        lockedFrames.removeAll()
        isLocked = false
        UserDefaults.standard.set(false, forKey: lockedFlagKey)
        for role in Role.allCases {
            UserDefaults.standard.removeObject(forKey: defaultsKeyPrefix + role.rawValue)
            UserDefaults.standard.removeObject(forKey: lockedKeyPrefix + role.rawValue)
        }
    }
}
