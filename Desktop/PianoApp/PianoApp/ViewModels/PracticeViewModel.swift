import Foundation
import Combine
import SwiftUI

// MARK: - 练习状态

@MainActor
class PracticeViewModel: ObservableObject {
    // 当前乐谱
    @Published var currentScore: Score?

    // 练习模式
    @Published var practiceMode: PracticeMode = .wait

    // 当前位置
    @Published var currentMeasure: Int = 1
    @Published var currentNoteIndex: Int = 0
    @Published var expectedNotes: Set<UInt8> = []
    @Published var matchedNotes: Set<UInt8> = []

    // 统计
    @Published var correctCount: Int = 0
    @Published var totalAttempts: Int = 0
    @Published var isPlaying: Bool = false

    // 校准
    @Published var calibration = CalibrationData()
    @Published var isCalibrating: Bool = false
    @Published var calibrationStep: CalibrationStep = .idle

    // 练习历史
    @Published var practiceHistory: [PracticeRecord] = []

    // 时间
    @Published var practiceStartTime: Date?
    @Published var tempo: Double = 70  // BPM 百分比

    private var cancellables = Set<AnyCancellable>()
    private let storageKey = "PracticeHistory"

    enum CalibrationStep: String {
        case idle = "未开始"
        case lowestKey = "按下最左边的键"
        case highestKey = "按下最右边的键"
        case latency = "跟节拍敲击 4 次"
        case saving = "保存中..."
        case done = "完成"
    }

    init() {
        loadDemoScore()
        loadHistory()
    }

    // MARK: - 加载乐谱

    func loadDemoScore() {
        currentScore = ScoreLoader.demoScore()
        resetPosition()
    }

    func loadScore(from url: URL) {
        if let score = ScoreLoader.load(from: url) {
            currentScore = score
            resetPosition()
        }
    }

    // MARK: - 位置控制

    func resetPosition() {
        currentMeasure = 1
        currentNoteIndex = 0
        correctCount = 0
        totalAttempts = 0
        matchedNotes = []
        updateExpectedNotes()
    }

    func updateExpectedNotes() {
        guard let score = currentScore,
              let measure = score.measures.first(where: { $0.number == currentMeasure }) else {
            expectedNotes = []
            return
        }

        // 获取当前时间点应该弹的音符
        let currentTime = Double(currentNoteIndex)
        let notes = measure.notes.filter { note in
            note.startTime <= currentTime && note.startTime + note.duration > currentTime
        }

        expectedNotes = Set(notes.map { UInt8($0.pitch) })
    }

    // MARK: - MIDI 输入处理

    func handleNoteOn(_ note: UInt8, velocity: UInt8) {
        guard isPlaying else { return }

        switch practiceMode {
        case .wait:
            handleWaitMode(note: note)
        case .freeplay:
            handleFreeplay(note: note)
        case .handsSplit:
            handleHandsSplit(note: note)
        case .loop:
            handleLoop(note: note)
        }
    }

    private func handleWaitMode(note: UInt8) {
        totalAttempts += 1

        if expectedNotes.contains(note) {
            // 正确！
            matchedNotes.insert(note)
            correctCount += 1

            // 检查是否所有音都按对了
            if matchedNotes == expectedNotes {
                advanceToNext()
            }
        }
    }

    private func handleFreeplay(note: UInt8) {
        // 自由模式，只记录
        totalAttempts += 1
        if expectedNotes.contains(note) {
            correctCount += 1
        }
    }

    private func handleHandsSplit(note: UInt8) {
        // 分手练习逻辑
        handleWaitMode(note: note)
    }

    private func handleLoop(note: UInt8) {
        // 循环模式
        handleWaitMode(note: note)
    }

    // MARK: - 前进到下一个音符

    private func advanceToNext() {
        guard let score = currentScore else { return }

        matchedNotes = []

        if let measure = score.measures.first(where: { $0.number == currentMeasure }) {
            let nextIndex = currentNoteIndex + 1
            let maxIndex = Int(measure.notes.map { $0.startTime + $0.duration }.max() ?? 0)

            if nextIndex <= maxIndex {
                currentNoteIndex = nextIndex
            } else {
                // 下一小节
                if currentMeasure < score.measures.count {
                    currentMeasure += 1
                    currentNoteIndex = 0
                } else {
                    // 练习完成
                    finishPractice()
                }
            }
        }

        updateExpectedNotes()
    }

    // MARK: - 播放控制

    func startPractice() {
        isPlaying = true
        practiceStartTime = Date()
        resetPosition()
    }

    func stopPractice() {
        isPlaying = false
        finishPractice()
    }

    private func finishPractice() {
        guard let startTime = practiceStartTime else { return }

        let record = PracticeRecord(
            id: UUID(),
            date: Date(),
            scoreTitle: currentScore?.title ?? "Unknown",
            totalNotes: totalAttempts,
            correctNotes: correctCount,
            duration: Date().timeIntervalSince(startTime),
            mode: practiceMode
        )

        practiceHistory.append(record)
        saveHistory()
        practiceStartTime = nil
    }

    // MARK: - 准确率

    var accuracy: Double {
        guard totalAttempts > 0 else { return 0 }
        return Double(correctCount) / Double(totalAttempts) * 100
    }

    var formattedAccuracy: String {
        String(format: "%.0f%%", accuracy)
    }

    // MARK: - 校准流程

    func startCalibration() {
        isCalibrating = true
        calibrationStep = .lowestKey
    }

    func handleCalibrationNote(_ note: UInt8) {
        switch calibrationStep {
        case .lowestKey:
            calibration.lowestNote = note
            calibrationStep = .highestKey
        case .highestKey:
            if note > calibration.lowestNote {
                calibration.highestNote = note
                calibrationStep = .latency
            }
        case .latency:
            // 简化：假设延迟为 0
            calibration.isCalibrated = true
            calibrationStep = .done
            isCalibrating = false
        default:
            break
        }
    }

    // MARK: - 持久化

    private func saveHistory() {
        if let data = try? JSONEncoder().encode(practiceHistory) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    private func loadHistory() {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let history = try? JSONDecoder().decode([PracticeRecord].self, from: data) {
            practiceHistory = history
        }
    }

    // MARK: - 队列数据

    struct QueueItem: Identifiable {
        let id = UUID()
        let title: String
        let detail: String
        let state: String
    }

    var queueItems: [QueueItem] {
        [
            QueueItem(
                title: currentScore?.title ?? "No Score",
                detail: "\(currentScore?.measures.count ?? 0) 小节",
                state: "当前"
            ),
            QueueItem(
                title: "Broken Chords Warm-up",
                detail: "3 分钟热身 · C / G / Am",
                state: "接下来"
            ),
            QueueItem(
                title: "Loop \(currentMeasure)-\(currentMeasure + 3)",
                detail: "错误热点重复段落",
                state: "重点"
            ),
        ]
    }
}
