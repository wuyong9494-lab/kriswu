import Foundation

extension StarRail {
    /// Layout and rule revision are separate from the persisted document format.
    /// Revision 1 remains immutable so old action logs still replay exactly.
    public static let catalogRevision = 2
    public static let stages: [Stage] = revisionTwoStages
    /// Published R2 layouts back SX2 challenge codes and must remain immutable.
    static let revisionTwoStages: [Stage] = originalStages.map { original in
        let assignments: [Int: [Int]] = [
            3: [0,0,0,1,4, 4,5,6,6,7, 3,2,1,3,1, 7,2,3,2,4,5, 5,6,7],
            4: [0,0,0,6, 3,2,3,1, 1,5,3,2, 5,7,4,4, 1,7,5,6,2,4, 6,7],
            5: [0,0,0,1,5, 4,2,8,4,3, 8,1,1,4,3, 6,6,2,7,3, 7,5,2, 5,6,7,8],
            6: [0,0,0,3,2, 9,9,6,7,1, 8,4,2,5,5, 3,1,4,4,3, 6,1,2,8, 5,6,7,7,8,9]
        ]
        let tips: [Int: String] = [
            3: "先比较第三张火箭在哪里。拆掉一张上层太阳，可能比立即移动整条轨道更省槽；再检查终点会盖住哪些牌。",
            4: "远端会盖住一张月亮。可先拆下上层土星，拿到月亮补能，再把保留的太阳带回起点。",
            5: "先留好星星对子，A 离开后再补第三张，为返程充能。B 去远端也会重新覆盖底部牌，要对比两条轨道的窗口。",
            6: "为两次返程分别准备可用的三消。查看天线、望远镜和星星的第三张，会在哪个窗口露出；A 被 B 压住时不能移动。"
        ]
        let cards = original.cards.map { c -> Card in
            var y = c.y
            if original.id == 5 && c.rail != nil { y = 6 }
            if original.id == 6, let rail = c.rail { y = rail == 0 ? 6 : 2 }
            return Card(id: c.id, kind: assignments[original.id]?[c.id] ?? c.kind,
                        x: c.x, y: y, z: c.z, rail: c.rail)
        }
        return Stage(id: original.id, title: original.title,
                     lesson: original.id == 5 ? "让行之后，为 A 保留返程窗口" : original.lesson,
                     objective: original.id == 5 ? "清空棋盘；A 完成往返，B 到达远端" : original.objective,
                     tip: tips[original.id] ?? original.tip, cards: cards, rails: original.rails,
                     requiredArrivals: original.id == 5 ? 11 : original.requiredArrivals,
                     plannedMoves: original.id == 5 ? 3 : original.plannedMoves,
                     targetPeak: original.targetPeak, revision: 2)
    }
}
