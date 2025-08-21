#!/bin/bash

output_file="output.txt"
> "$output_file"
for svg_file in *.svg; do
    if [ ! -f "$svg_file" ]; then
        continue
    fi
    filename=$(basename "$svg_file" .svg)
    if command -v gbase64 &> /dev/null; then
        base64_content=$(gbase64 -w 0 "$svg_file")
    else
        base64_content=$(base64 -i "$svg_file" | tr -d '\n')
    fi    
    echo "{" >> "$output_file"
    echo "                  identifier: '$filename'," >> "$output_file"
    echo "                  name: '$filename'," >> "$output_file"
    echo "                  thumbnailURI: 'data:image/svg+xml;base64,$base64_content'," >> "$output_file"
    echo "                  stickerURI: 'data:image/svg+xml;base64,$base64_content'" >> "$output_file"
    echo "                }," >> "$output_file"
    echo "" >> "$output_file"
    
    echo "Обработан файл: $svg_file"
done
echo "Готово! Результат сохранен в $output_file"