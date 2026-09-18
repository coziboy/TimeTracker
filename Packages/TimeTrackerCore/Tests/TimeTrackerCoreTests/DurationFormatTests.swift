import Testing
@testable import TimeTrackerCore

@Suite("formatDuration")
struct FormatDurationTests {
  @Test("zero formats as 00:00:00")
  func zero() {
    #expect(formatDuration(0) == "00:00:00")
  }

  @Test("seconds under a minute pad to two digits")
  func underAMinute() {
    #expect(formatDuration(59) == "00:00:59")
  }

  @Test("hours, minutes and seconds all carry")
  func hoursMinutesSeconds() {
    #expect(formatDuration(3661) == "01:01:01")
  }

  @Test("hours are not capped at 24")
  func beyondADay() {
    #expect(formatDuration(172800) == "48:00:00")
  }

  @Test("negative input clamps to zero")
  func negative() {
    #expect(formatDuration(-5) == "00:00:00")
  }
}

@Suite("parseDuration")
struct ParseDurationTests {
  @Test("HH:MM:SS")
  func fullClock() {
    #expect(parseDuration("1:02:03") == 3723)
  }

  @Test("MM:SS")
  func minutesSeconds() {
    #expect(parseDuration("5:07") == 307)
  }

  @Test("bare seconds")
  func bareSeconds() {
    #expect(parseDuration("90") == 90)
  }

  @Test("compound 1h30m")
  func compound() {
    #expect(parseDuration("1h30m") == 5400)
  }

  @Test("compound is case-insensitive and tolerates spaces")
  func compoundCaseAndSpaces() {
    #expect(parseDuration("1H 30M") == 5400)
  }

  @Test("minutes only")
  func minutesOnly() {
    #expect(parseDuration("45m") == 2700)
  }

  @Test("seconds suffix")
  func secondsSuffix() {
    #expect(parseDuration("90s") == 90)
  }

  @Test("empty string is rejected")
  func empty() {
    #expect(parseDuration("") == nil)
  }

  @Test("letters are rejected")
  func letters() {
    #expect(parseDuration("abc") == nil)
  }

  @Test("too many clock components are rejected")
  func tooManyComponents() {
    #expect(parseDuration("1:2:3:4") == nil)
  }

  @Test("unknown unit suffix is rejected")
  func unknownUnit() {
    #expect(parseDuration("1h2x") == nil)
  }
}
