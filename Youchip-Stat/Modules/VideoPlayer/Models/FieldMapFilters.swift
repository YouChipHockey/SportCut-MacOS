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
        if !selectedTags.isEmpty || !selectedTagGroups.isEmpty {
            var matchesTagFilters = false
            if !selectedTags.isEmpty {
                matchesTagFilters = !selectedTags.isDisjoint(with: stamp.idTags)
            }
            if !matchesTagFilters && !selectedTagGroups.isEmpty {
                for tagID in stamp.idTags {
                    if let tagGroup = TagLibraryManager.shared.findTagGroupForTag(tagID),
                       selectedTagGroups.contains(tagGroup.id) {
                        matchesTagFilters = true
                        break
                    }
                }
            }
            if (!selectedTags.isEmpty || !selectedTagGroups.isEmpty) && !matchesTagFilters {
                return false
            }
        }
        if !selectedEvents.isEmpty {
            let stampEventSet = Set(stamp.timeEvents)
            if !selectedEvents.isSubset(of: stampEventSet) {
                return false
            }
        }
        if !selectedLabelGroups.isEmpty {
            let stampLabelGroups = getStampLabelGroups(stamp)
            if !selectedLabelGroups.isSubset(of: stampLabelGroups) {
                return false
            }
        }
        
        if !selectedLabels.isEmpty {
            let stampLabelSet = Set(stamp.labelIDs)
            if !selectedLabels.isSubset(of: stampLabelSet) {
                return false
            }
        }
        
        return true
    }
    
    private func getStampLabelGroups(_ stamp: TimelineStamp) -> Set<String> {
        var groupIDs = Set<String>()
        
        for labelID in stamp.labelIDs {
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
