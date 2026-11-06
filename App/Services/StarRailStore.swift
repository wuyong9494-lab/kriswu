import SwiftUI

@MainActor
final class StarRailStore: ObservableObject {
    static let shared: StarRailStore = {
        let arguments = ProcessInfo.processInfo.arguments
        guard arguments.contains("-demo") else { return StarRailStore() }
        let suffix = arguments.firstIndex(of: "-rails.testDomain").flatMap { index in
            index + 1 < arguments.count ? UUID(uuidString: arguments[index + 1])?.uuidString : nil
        } ?? "preview"
        return StarRailStore(defaults: UserDefaults(suiteName: "com.kriswu.shiftreminder.starRails.demo.\(suffix)")!)
    }()
    @Published private(set) var save: StarRail.Save
    @Published private(set) var trials: StarRail.TrialSave
    @Published private(set) var expeditions: StarRail.ExpeditionSave
    @Published private(set) var journal: StarRail.Journal
    @Published private(set) var journeys: StarJourney.Save
    @Published private(set) var earnedStars = 0
    @Published private(set) var notice: String?
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        trials = .init()
        expeditions = .init(); journal = .init(); journeys = .init()
        if let data = defaults.data(forKey: StarRail.Save.storageKey) {
            if let restored = StarRail.Save(data: data) {
                save = restored
            } else {
                // Preserve the unreadable document before allowing a fresh run.
                let backupKey = StarRail.Save.storageKey + ".unreadable"
                if defaults.data(forKey: backupKey) == nil { defaults.set(data, forKey: backupKey) }
                save = .init()
                notice = "星轨进度暂时无法读取，已保留原记录。本次从第一关开始。"
            }
        } else {
            save = .init()
        }
        if let data = defaults.data(forKey: StarRail.TrialSave.storageKey) {
            if let restored = StarRail.TrialSave(data: data) { trials = restored }
            else {
                let key = StarRail.TrialSave.storageKey + ".unreadable"
                if defaults.data(forKey: key) == nil { defaults.set(data, forKey: key) }
                notice = "试炼进度暂时无法读取，已保留原记录；主线进度不受影响。"
            }
        }
        if let data = defaults.data(forKey: StarRail.ExpeditionSave.storageKey) {
            if let value = StarRail.ExpeditionSave(data:data) { expeditions = value }
            else { preserve(data, key:StarRail.ExpeditionSave.storageKey); notice = "远征进度暂时无法读取，已保留原记录。主线与试炼仍可继续。" }
        }
        if let data = defaults.data(forKey: StarRail.Journal.storageKey) {
            if let value = StarRail.Journal(data:data) { journal = value }
            else { preserve(data, key:StarRail.Journal.storageKey); notice = "外观记录暂时无法读取，已保留原记录；已获得的星章仍然有效。" }
        }
        if let data = defaults.data(forKey:StarJourney.Save.storageKey) {
            if let value = StarJourney.Save(data:data) { journeys = value }
            else { preserve(data,key:StarJourney.Save.storageKey); notice = "旅程进度暂时无法读取，已保留原记录；其他航线仍可继续。" }
        }
        refreshStars()
    }

    @discardableResult func keep(_ game: StarRail.Game) -> Bool {
        if let configuration = game.stage.journey {
            var next = journeys
            guard next.keep(game,otherStars:max(0,earnedStars-journeys.totalStars)) else {
                notice = "这局旅程已经切换，旧棋盘不会覆盖新进度。"; return false
            }
            guard keepJourneys(next) else { return false }
            if game.status == .won { refreshStars(); dismissLesson(configuration.lesson) }
            return true
        }
        if game.stage.expeditionID != nil {
            var next = expeditions
            guard next.keep(game), let data = next.encoded() else { notice = "远征进度暂未保存，请先留在棋盘。"; return false }
            defaults.set(data,forKey:StarRail.ExpeditionSave.storageKey); expeditions = next
            if game.status == .won { refreshStars(); dismissLesson(.firstFork) }
            return true
        }
        if game.stage.trial != nil {
            var next = trials
            guard next.keep(game), let data = next.encoded() else {
                notice = "试炼进度暂未保存，请先留在棋盘。"
                return false
            }
            defaults.set(data, forKey: StarRail.TrialSave.storageKey)
            trials = next
            if game.status == .won { refreshStars() }
            return true
        }
        var next = save
        guard next.keep(game), let data = next.encoded() else {
            notice = "这局进度暂未保存，请先留在棋盘。"
            return false
        }
        defaults.set(data, forKey: StarRail.Save.storageKey)
        save = next
        if game.status == .won { refreshStars(); if game.stage.id == 1 { dismissLesson(.firstOrbit) } }
        return true
    }
    @discardableResult func startJourney(_ ability: StarJourney.Ability) -> Bool {
        var next = journeys; next.start(ability:ability); return keepJourneys(next)
    }
    func advanceJourney(route: StarJourney.Route? = nil) -> StarRail.Game? {
        var next = journeys
        guard next.advance(route:route), keepJourneys(next) else { return nil }
        return journeys.active?.game
    }
    func acknowledgeJourneyReward(_ id: UUID) {
        var next = journeys; next.acknowledgeReward(id); _ = keepJourneys(next)
    }
    private func keepJourneys(_ next: StarJourney.Save) -> Bool {
        guard let data = next.encoded() else { notice = "旅程暂未保存，请留在当前页面。"; return false }
        defaults.set(data,forKey:StarJourney.Save.storageKey); journeys = next; return true
    }
    var sky: StarRail.SkyTheme { earnedStars >= journal.sky.requiredStars ? journal.sky : .midnight }
    var cardBack: StarRail.CardBack { earnedStars >= journal.back.requiredStars ? journal.back : .starlines }
    func select(sky: StarRail.SkyTheme) {
        var next = journal; if next.select(sky:sky,earned:earnedStars) { keepJournal(next) }
    }
    func select(back: StarRail.CardBack) {
        var next = journal; if next.select(back:back,earned:earnedStars) { keepJournal(next) }
    }
    func dismissLesson(_ lesson: StarRail.Lesson) {
        guard !journal.dismissedLessons.contains(lesson) else { return }
        var next = journal; next.dismiss(lesson); keepJournal(next)
    }
    func resetLessons() { var next = journal; next.resetLessons(); keepJournal(next) }
    private func keepJournal(_ next: StarRail.Journal) {
        guard let data = next.encoded() else { notice = "外观与教学设置暂未保存。"; return }
        defaults.set(data,forKey:StarRail.Journal.storageKey); journal = next
    }
    private func refreshStars() { earnedStars = StarRail.StarMap.earned(progress:save.progress,trials:trials,expeditions:expeditions) + journeys.totalStars }
    private func preserve(_ data: Data, key: String) {
        if defaults.data(forKey:key + ".unreadable") == nil { defaults.set(data,forKey:key + ".unreadable") }
    }

}
