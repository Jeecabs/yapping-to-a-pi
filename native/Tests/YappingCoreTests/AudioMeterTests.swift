import AVFoundation
import Testing
@testable import YappingCore

@Test func speechMeterRespondsToQuietSpeechInFloatAndIntegerBuffers() throws {
    // A quiet -40 dBFS voice must visibly move a 20-point waveform.
    let floatFormat = try #require(AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false))
    let integerFormat = try #require(AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16_000, channels: 1, interleaved: false))
    let floatBuffer = try #require(AVAudioPCMBuffer(pcmFormat: floatFormat, frameCapacity: 320))
    let integerBuffer = try #require(AVAudioPCMBuffer(pcmFormat: integerFormat, frameCapacity: 320))
    floatBuffer.frameLength = 320
    integerBuffer.frameLength = 320
    for index in 0..<320 {
        floatBuffer.floatChannelData![0][index] = index.isMultiple(of: 2) ? 0.01 : -0.01
        integerBuffer.int16ChannelData![0][index] = index.isMultiple(of: 2) ? 328 : -328
    }
    let floatLevel = AudioMeter.level(in: floatBuffer)
    let integerLevel = AudioMeter.level(in: integerBuffer)
    #expect(floatLevel > 0.5)
    #expect(integerLevel > 0.5)
    #expect(abs(floatLevel - integerLevel) < 0.01)
}

@Test func speechMeterKeepsSilenceFlatAndReadsTheActiveStereoChannel() throws {
    let format = try #require(AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 48_000, channels: 2, interleaved: true))
    let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 100))
    buffer.frameLength = 100
    let audioBuffer = UnsafeMutableAudioBufferListPointer(buffer.mutableAudioBufferList)[0]
    let samples = try #require(audioBuffer.mData?.assumingMemoryBound(to: Int16.self))
    samples.initialize(repeating: 0, count: 200)
    #expect(AudioMeter.level(in: buffer) == 0)
    for index in 0..<100 { samples[index * 2 + 1] = 328 }
    #expect(AudioMeter.level(in: buffer) > 0.5)
    for index in 0..<100 { samples[index * 2 + 1] = Int16.min }
    #expect(AudioMeter.level(in: buffer) == 1)
    buffer.frameLength = 0
    #expect(AudioMeter.level(in: buffer) == 0)
}

@Test func waveformShowsRecentSpeechAndReturnsToSilence() {
    var waveform = WaveformHistory()
    waveform.append(0.1)
    waveform.append(0.8)
    #expect(Array(waveform.samples.suffix(2)) == [0.1, 0.8])
    #expect(WaveformHistory.height(for: 0.8) - WaveformHistory.height(for: 0.1) > 12)
    for _ in 0..<WaveformHistory.barCount { waveform.append(0) }
    #expect(waveform.samples.allSatisfy { $0 == 0 })
    #expect(WaveformHistory.height(for: 0) == 2)
    waveform.append(.nan)
    #expect(waveform.samples.last == 0)
    #expect(WaveformHistory.height(for: 0.8, sensitivity: 2) == 20)
}

@Test func existingBarPreferencesLoadWithDefaultWaveformSensitivity() throws {
    let oldSettings = Data(#"{"theme":"dark","barScale":0.9,"bottomSpacing":8,"edge":"screen","opacity":0.9}"#.utf8)
    let preferences = try JSONDecoder().decode(AppearancePreferences.self, from: oldSettings)
    #expect(preferences.sensitivity == 1)
    #expect(preferences.barScale == 0.9)
}
