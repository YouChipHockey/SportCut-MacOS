# ImagesEditor / ImageEditor

Два связанных каталога:
- `ImagesEditor/` — редактирование скриншотов/изображений (исходный).
- `ImageEditor/` — новый таб **«Редактор»**: загружаешь фото и рисуешь поверх теми же
  инструментами, что и телестрация (общий `EditorDrawingState`), плюс аддитивный инструмент
  Images. Проекты в `~/Documents/EditorProjects`. Сведение — через `ImageRenderer`.

## Менеджеры (ImageEditor)
- `ImageEditorProjectsManager` — проекты редактора (CRUD, хранение в EditorProjects).
- `ImageEditorWindowManager` — окно редактора.

## Связи
[[Telestration]] · [[../architecture]]
