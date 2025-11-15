import Foundation

struct VideoMetadata: Codable {
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
    
    init(team1: String, team2: String, score: String, dateTime: Date) {
        self.team1 = team1
        self.team2 = team2
        self.score = score
        self.url = nil
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
    
    enum CodingKeys: String, CodingKey {
        case team1, team2, score, dateTime
        case urlString = "url"
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        team1 = try container.decode(String.self, forKey: .team1)
        team2 = try container.decode(String.self, forKey: .team2)
        score = try container.decode(String.self, forKey: .score)
        dateTime = try container.decode(Date.self, forKey: .dateTime)
        
        if let urlString = try container.decodeIfPresent(String.self, forKey: .urlString) {
            url = URL(string: urlString)
        } else {
            url = nil
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(team1, forKey: .team1)
        try container.encode(team2, forKey: .team2)
        try container.encode(score, forKey: .score)
        try container.encode(dateTime, forKey: .dateTime)
        try container.encodeIfPresent(url?.absoluteString, forKey: .urlString)
    }
}
