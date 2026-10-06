import Foundation
import Testing
@testable import TimeTrackerCore

@Suite("resolveTask")
struct TaskResolutionTests {
  private let alpha = TrackedTask(title: "Client Alpha")
  private let beta = TrackedTask(title: "Client Beta")
  private let cafe = TrackedTask(title: "Café")
  private var tasks: [TrackedTask] { [alpha, beta, cafe] }

  @Test("an id finds its task in any case")
  func byID() {
    #expect(resolveTask(beta.id.uuidString.lowercased(), in: tasks) == .found(beta))
  }

  @Test("an exact title wins, ignoring case and diacritics")
  func exactTitle() {
    #expect(resolveTask("client alpha", in: tasks) == .found(alpha))
    #expect(resolveTask("cafe", in: tasks) == .found(cafe))
  }

  @Test("an exact title beats a longer title it is a prefix of")
  func exactBeatsPrefix() {
    let short = TrackedTask(title: "Client")
    #expect(resolveTask("client", in: tasks + [short]) == .found(short))
  }

  @Test("a unique prefix finds its task")
  func uniquePrefix() {
    #expect(resolveTask("client b", in: tasks) == .found(beta))
  }

  @Test("a shared prefix is ambiguous and lists the candidates")
  func sharedPrefix() {
    #expect(resolveTask("client", in: tasks) == .ambiguous([alpha, beta]))
  }

  @Test("duplicate exact titles are ambiguous")
  func duplicateTitles() {
    let twin = TrackedTask(title: "Café")
    #expect(resolveTask("Café", in: tasks + [twin]) == .ambiguous([cafe, twin]))
  }

  @Test("a unique substring finds its task when no prefix does")
  func uniqueSubstring() {
    #expect(resolveTask("beta", in: tasks) == .found(beta))
    #expect(resolveTask("lient", in: tasks) == .ambiguous([alpha, beta]))
  }

  @Test("a prefix match beats a substring match")
  func prefixBeatsSubstring() {
    let beach = TrackedTask(title: "Beach")
    #expect(resolveTask("be", in: tasks + [beach]) == .found(beach))
  }

  @Test("no match, or a blank query, finds nothing")
  func notFound() {
    #expect(resolveTask("zzz", in: tasks) == .notFound)
    #expect(resolveTask("  ", in: tasks) == .notFound)
  }
}
