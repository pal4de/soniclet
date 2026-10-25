import Foundation
import UniformTypeIdentifiers

struct DeviceDragItem: Codable, Sendable {
    let key: DeviceKey
    static func contentType(_ direction: AudioDirection) -> UTType {
        UTType(exportedAs: "io.github.pal4de.soniclet.device.\(direction.rawValue)", conformingTo: .data)
    }
    func itemProvider() -> NSItemProvider {
        let provider = NSItemProvider()
        let data = try? JSONEncoder().encode(self)
        provider.registerDataRepresentation(forTypeIdentifier: Self.contentType(key.direction).identifier, visibility: .ownProcess) { completion in
            completion(data, nil)
            return nil
        }
        return provider
    }
    static func load(from provider: NSItemProvider, direction: AudioDirection, completion: @escaping @Sendable (DeviceKey?) -> Void) {
        let type = contentType(direction).identifier
        guard provider.hasItemConformingToTypeIdentifier(type) else { completion(nil); return }
        provider.loadDataRepresentation(forTypeIdentifier: type) { data, _ in
            guard let data, let payload = try? JSONDecoder().decode(Self.self, from: data), payload.key.direction == direction else {
                completion(nil)
                return
            }
            completion(payload.key)
        }
    }
}
