# Локализация

Кастомный паттерн ключей: `^String.Titles.someKey`.

- Файлы локализаций лежат в `Resourses/` (опечатка намеренная, так исторически).
- Языки: `ru_RU`, `en`, `es`, `fr`, `uz`, `zh-Hans`.
- Ключ `^String.Titles.someKey` в `.strings` пишется с **заглавной первой буквы**
  (`SomeKey`), т.к. extension капитализирует первую букву.
- Определения ключей — `Common/Extensions/LocalizedStrings.swift`.
- После правки `.strings` проверяй валидность:

```bash
plutil -lint Resourses/ru.lproj/Localizable.strings
```

## Связи
[[code-style]] · [[../modules/_index]]
