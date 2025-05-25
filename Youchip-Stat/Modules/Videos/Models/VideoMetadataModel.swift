import Foundation

struct VideoMetadata {
    var team1: String = ""
    var team2: String = ""
    var score: String = ""
    var url: URL?
    var dateTime: Date = Date()
    
    init(team1: String = "", team2: String = "", score: String = "", url: URL? = nil, dateTime: Date = Date()) {
        self.team1 = team1
        self.team2 = team2
        self.score = score
        self.url = url
        self.dateTime = dateTime
    }
    
    func generateFileName() -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd_HH-mm"
        let dateStr = dateFormatter.string(from: dateTime)
        
        let safeTeam1 = team1.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: " ", with: "_")
        let safeTeam2 = team2.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: " ", with: "_")
        let safeScore = score.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: " ", with: "_")
        
        return "\(safeTeam1)_\(safeTeam2)_\(safeScore)_\(dateStr)"
    }
}
