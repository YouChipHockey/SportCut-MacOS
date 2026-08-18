//
//  BulkSelectCornerCircle.swift
//  Youchip-Stat
//
//  Кружок в левом-верхнем углу обложки проекта — единая точка входа в массовое удаление
//  на всех вкладках главного меню (разметка / просмотр / редактор). Клик по кружку включает
//  режим выбора и отмечает карточку; дальше выбор идёт этим же кружком/оверлеем карточки.
//

import SwiftUI

struct BulkSelectCornerCircle: View {
    /// Отмечен ли элемент (влияет только на вид кружка).
    var isSelected: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(isSelected ? Color.red : Color.black.opacity(0.35))
                Circle()
                    .strokeBorder(Color.white, lineWidth: 1.5)
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.white)
                }
            }
            .frame(width: 22, height: 22)
            .shadow(color: .black.opacity(0.25), radius: 2, x: 0, y: 1)
            .contentShape(Circle())
        }
        .buttonStyle(PlainButtonStyle())
    }
}
