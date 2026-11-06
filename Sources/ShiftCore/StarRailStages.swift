import Foundation

extension StarRail {
    /// Six authored arrangements. No random seed, old removal order or old
    /// TileGame generator participates in these rules or their solvability.
    public static let originalStages: [Stage] = [
        make(1,"第一次变轨","先消三张，再改变遮挡","清空棋盘；让轨道 A 到达远端一次",
             "先凑齐三枚卫星获得能量。预览 A：绿色表示露出的牌，橙色表示将被压住的牌。",
             rows:[[0,0,0],[1,1,2],[1,2,2,3]],
             rails:[Rail(id:0,name:"轨道 A",delta:Point(x:8,y:0))],
             upper:[(0,3,0,4,1),(0,3,4,4,1)],goals:2,moves:1,peak:3),
        make(2,"往返航线","移走之后，还要留牌返回","清空棋盘；A 到远端后再回起点",
             "A 到远端会让另一排牌被盖住。保留至少一张轨道牌，利用底部同类牌补充返航能量。",
             rows:[[0,0,0],[1,2,1],[2,1,2],[3,4,5],[3,4,5]],
             rails:[Rail(id:0,name:"轨道 A",delta:Point(x:0,y:4))],
             upper:[(0,3,0,4,1),(0,4,4,4,1),(0,5,8,4,1)],goals:3,moves:2,peak:4),
        make(3,"留槽开窗","取上层牌还是先打开第三张","清空棋盘；A 到达远端；争取峰值不超过四格",
             "A 下方还有一层牌。先查看土星和星星的第三张，别把太阳、火箭同时塞满收集槽；移层后也要留意新压住的牌。",
             rows:[[0,0,0,2,7],[5,6,2,1,3],[4,1,6,3,1]],
             rails:[Rail(id:0,name:"轨道 A",delta:Point(x:8,y:0))],
             middle:[(7,0,4,1),(5,4,4,1),(4,8,4,1),(3,12,4,1),(4,16,4,1),(2,0,8,1)],
             upper:[(0,5,0,4,2),(0,6,4,4,2),(0,7,8,4,2)],goals:2,moves:1,peak:4),
        make(4,"回航储能","为返程留能量，也可拆掉一张补能","清空棋盘；A 完成往返；两次移层内完成",
             "远端会压住星星和地球。先储能，或只拆掉土星轨道牌完成补能；保留太阳轨道牌返航，才能再次打开窗口。",
             rows:[[0,0,0,3],[3,4,1,5],[4,2,2,7],[6,5,6,3]],
             rails:[Rail(id:0,name:"轨道 A",delta:Point(x:0,y:8))],
             middle:[(4,0,4,1),(7,4,4,1),(1,8,4,1),(1,12,4,1),(5,0,8,1),(2,4,8,1)],
             upper:[(0,6,4,4,2),(0,7,12,4,2)],goals:3,moves:2,peak:4),
        make(5,"双轨让行","先让出终点，再决定何时覆盖它","清空棋盘；A、B 各到达远端一次",
             "B 占着 A 的终点。可以先移 B，也可只拆掉挡路的轨道牌；两条轨道都须保留一张完成航线。注意底部月亮会被 B 再次盖住。",
             rows:[[0,0,0,1,1],[2,7,2,5,1],[6,3,5,3,7],[4,3,4,4,8]],
             rails:[Rail(id:0,name:"轨道 A",delta:Point(x:8,y:0)),Rail(id:1,name:"轨道 B",delta:Point(x:0,y:8))],
             middle:[(6,0,4,1),(2,4,4,1),(8,8,4,1)],
             upper:[(0,5,0,4,2),(0,6,4,4,2),(1,7,8,4,2),(1,8,12,4,2)],goals:10,moves:2,peak:5),
        make(6,"交错回环","上层轨道决定下层何时能走","清空棋盘；A、B 都完成往返",
             "A 能进入 B 下方，但被 B 压住时不能移动。观察上下层与能量，安排两条轨道的返程顺序。",
             rows:[[0,0,0,1,1],[4,4,6,3,1],[8,4,9,7,9],[5,6,2,8,2]],
             rails:[Rail(id:0,name:"轨道 A",delta:Point(x:0,y:-4)),Rail(id:1,name:"轨道 B",delta:Point(x:0,y:8))],
             middle:[(5,12,8,1),(3,16,8,1),(2,0,12,1),(3,4,12,1)],
             upper:[(0,5,0,8,1),(0,6,4,8,1),(0,7,8,8,1),(1,7,4,4,2),(1,8,8,4,2),(1,9,12,4,2)],goals:15,moves:4,peak:5)
    ]

    public static func stage(_ id: Int, revision: Int = catalogRevision) -> Stage? {
        switch revision {
        case 1: return originalStages.first { $0.id == id }
        case 2: return revisionTwoStages.first { $0.id == id }
        default: return nil
        }
    }

    private static func make(_ id:Int,_ title:String,_ lesson:String,_ objective:String,_ tip:String,
                             rows:[[Int]],rails:[Rail],middle:[(Int,Int,Int,Int)] = [],
                             upper:[(Int,Int,Int,Int,Int)],goals:Int,moves:Int,peak:Int) -> Stage {
        var cards:[Card] = []
        for (y,row) in rows.enumerated() {
            for (x,kind) in row.enumerated() { cards.append(Card(id:cards.count,kind:kind,x:x*4,y:y*4,z:0,rail:nil)) }
        }
        for (kind,x,y,z) in middle { cards.append(Card(id:cards.count,kind:kind,x:x,y:y,z:z,rail:nil)) }
        for (rail,kind,x,y,z) in upper { cards.append(Card(id:cards.count,kind:kind,x:x,y:y,z:z,rail:rail)) }
        return Stage(id:id,title:title,lesson:lesson,objective:objective,tip:tip,cards:cards,rails:rails,
                     requiredArrivals:goals,plannedMoves:moves,targetPeak:peak)
    }
}
