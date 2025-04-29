import Foundation

struct VideoMetadata {
    var team1: String = ""
    var team2: String = ""
    var score: String = ""
    var url: URL?
    
    func generateFileName() -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let dateStr = dateFormatter.string(from: Date())
        
        // Clean team names and score to be filename-friendly
        let safeTeam1 = team1.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: " ", with: "_")
        let safeTeam2 = team2.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: " ", with: "_")
        let safeScore = score.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: " ", with: "_")
        
        return "\(safeTeam1)_\(safeTeam2)_\(safeScore)_\(dateStr)"
    }
}
