import Foundation

struct 📝DrawingData: Codable, Equatable {
    var data: Data
    
    init(data: Data = Data()) {
        self.data = data
    }
    
    var isEmpty: Bool {
        self.data.isEmpty
    }
}
