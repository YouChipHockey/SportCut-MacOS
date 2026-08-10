# License

Валидация лицензии и авторизация (Firebase-backed). Проверяется на старте в
`Youchip_StatApp.swift` перед показом `ContentView`.

- `AuthManager` — валидация лицензии, передаётся как `@EnvironmentObject` из корня.
- Секреты — в Keychain (`KeychainHelper`), инфо о лицензии — в UserDefaults.

## Правило UI
Активная лицензия = без лимитов: показывать только «Лицензия активна», без счётчика.

## Связи
[[../architecture]]
