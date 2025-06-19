import Foundation

struct FieldMapFilters: Equatable {
    var selectedEvents: Set<String> = []
    var selectedTagGroups: Set<String> = []
    var selectedTags: Set<String> = []
    var selectedLabelGroups: Set<String> = []
    var selectedLabels: Set<String> = []
    
    var isAnyFilterActive: Bool {
        !selectedEvents.isEmpty || !selectedTagGroups.isEmpty || !selectedTags.isEmpty ||
        !selectedLabelGroups.isEmpty || !selectedLabels.isEmpty
    }
    
    func shouldShowStamp(_ stamp: TimelineStamp) -> Bool {
        if !isAnyFilterActive { return true }
        
        // Проверка тегов и групп тегов (ИЛИ)
        if !selectedTags.isEmpty || !selectedTagGroups.isEmpty {
            var matchesTagFilters = false
            
            // Проверка на соответствие тегу
            if !selectedTags.isEmpty {
                matchesTagFilters = selectedTags.contains(stamp.idTag)
            }
            
            // Проверка на соответствие группе тегов, если не соответствует тегу
            if !matchesTagFilters && !selectedTagGroups.isEmpty {
                if let tagGroup = TagLibraryManager.shared.findTagGroupForTag(stamp.idTag) {
                    matchesTagFilters = selectedTagGroups.contains(tagGroup.id)
                }
            }
            
            // Если не соответствует ни одному из выбранных вариантов, исключаем
            if (!selectedTags.isEmpty || !selectedTagGroups.isEmpty) && !matchesTagFilters {
                return false
            }
        }
        
        // События, группы лейблов и лейблы работают по принципу "И"
        
        // Проверка событий: должны присутствовать ВСЕ выбранные события
        if !selectedEvents.isEmpty {
            let stampEventSet = Set(stamp.timeEvents)
            // Возвращаем false если хотя бы одно из выбранных событий отсутствует в стампе
            if !selectedEvents.isSubset(of: stampEventSet) {
                return false
            }
        }
        
        // Проверка групп лейблов: должны присутствовать ВСЕ выбранные группы
        if !selectedLabelGroups.isEmpty {
            let stampLabelGroups = getStampLabelGroups(stamp)
            // Возвращаем false если хотя бы одна выбранная группа лейблов отсутствует в стампе
            if !selectedLabelGroups.isSubset(of: stampLabelGroups) {
                return false
            }
        }
        
        // Проверка лейблов: должны присутствовать ВСЕ выбранные лейблы
        if !selectedLabels.isEmpty {
            let stampLabelSet = Set(stamp.labels)
            // Возвращаем false если хотя бы один выбранный лейбл отсутствует в стампе
            if !selectedLabels.isSubset(of: stampLabelSet) {
                return false
            }
        }
        
        return true
    }
    
    private func getStampLabelGroups(_ stamp: TimelineStamp) -> Set<String> {
        var groupIDs = Set<String>()
        
        for labelID in stamp.labels {
            for group in TagLibraryManager.shared.allLabelGroups {
                if group.lables.contains(labelID) {
                    groupIDs.insert(group.id)
                    break
                }
            }
        }
        
        return groupIDs
    }
}
