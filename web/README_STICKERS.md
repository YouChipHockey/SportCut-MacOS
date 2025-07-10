# Добавление кастомных стикеров в PhotoEditor SDK

## Структура файлов

Для добавления кастомных стикеров была создана следующая структура:

```
web/public/assets/stickers/custom/
├── stickers.json          # Конфигурационный файл (не используется)
├── emoji/                 # Папка с эмодзи стикерами
│   ├── happy_face.svg
│   ├── sad_face.svg
│   └── love_face.svg
└── shapes/                # Папка с геометрическими фигурами
    ├── arrow_right.svg
    ├── star.svg
    └── heart.svg
```

## Конфигурация в коде

В файле `PhotoEditor.jsx` добавлена конфигурация стикеров:

```javascript
sticker: {
  categories: [
    {
      identifier: 'custom_emoji',
      name: 'Emoji',
      items: [
        {
          identifier: 'happy_face',
          name: 'Happy Face',
          thumbnailURI: './assets/stickers/custom/emoji/happy_face.svg',
          stickerURI: './assets/stickers/custom/emoji/happy_face.svg'
        },
        // ... другие стикеры
      ]
    },
    {
      identifier: 'custom_shapes',
      name: 'Shapes',
      items: [
        // ... стикеры фигур
      ]
    }
  ]
}
```

## Как добавить новые стикеры

### 1. Добавить файл стикера
Поместите SVG или PNG файл в соответствующую папку:
- `web/public/assets/stickers/custom/emoji/` - для эмодзи
- `web/public/assets/stickers/custom/shapes/` - для фигур
- Или создайте новую категорию

### 2. Обновить конфигурацию
В файле `PhotoEditor.jsx` добавьте новый стикер в массив `items`:

```javascript
{
  identifier: 'my_new_sticker',
  name: 'My New Sticker',
  thumbnailURI: './assets/stickers/custom/category/my_sticker.svg',
  stickerURI: './assets/stickers/custom/category/my_sticker.svg'
}
```

### 3. Создать новую категорию
Для добавления новой категории стикеров:

```javascript
{
  identifier: 'new_category',
  name: 'New Category',
  items: [
    // ... стикеры категории
  ]
}
```

## Поддерживаемые форматы

- **SVG** - векторные изображения (рекомендуется)
- **PNG** - растровые изображения с прозрачностью
- **JPG** - растровые изображения (без прозрачности)

## Рекомендации

1. **Размер файлов**: Используйте оптимизированные SVG или PNG не более 100KB
2. **Разрешение**: Для PNG рекомендуется 256x256px или 512x512px
3. **Прозрачность**: Используйте прозрачный фон для лучшего вида
4. **Именование**: Используйте понятные имена файлов и идентификаторы

## Пример создания SVG стикера

```svg
<svg width="100" height="100" viewBox="0 0 100 100" xmlns="http://www.w3.org/2000/svg">
  <!-- Ваш дизайн здесь -->
  <circle cx="50" cy="50" r="40" fill="#FFC107"/>
</svg>
```

## Отладка

Если стикеры не загружаются:

1. Проверьте правильность путей к файлам
2. Убедитесь, что файлы доступны по HTTP
3. Проверьте консоль браузера на ошибки
4. Убедитесь, что файлы имеют правильный формат

## Расширенная настройка

Для более сложной конфигурации стикеров можно:

1. Добавить метаданные к стикерам
2. Настроить группировку и фильтрацию
3. Добавить анимированные стикеры
4. Интегрировать с внешними API для динамической загрузки

Подробнее о расширенных возможностях см. в [официальной документации PhotoEditor SDK](https://img.ly/docs/pesdk/). 