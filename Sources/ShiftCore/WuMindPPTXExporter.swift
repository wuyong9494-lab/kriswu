import Foundation

/// Pure-Swift ECMA-376 OpenXML `.pptx` exporter for WUMIND PPT Studio.
/// Produces 100% natively editable PowerPoint / WPS presentations (16:9 widescreen):
/// - Native editable text shapes (`<p:sp>`) with `<a:normAutofit/>`
/// - Native editable DrawingML tables (`<a:tbl>`)
/// - Native editable charts (`ppt/charts/chartN.xml`) backed by REAL embedded Excel `.xlsx` workbooks
///   (`ppt/embeddings/Microsoft_Excel_WorksheetN.xlsx`) so "Edit Data / 编辑数据" works live in PowerPoint & WPS
/// - Native slide speaker notes (`ppt/notesSlides/notesSlideN.xml`)
/// - Optional native embedded `<p:pic>` slide images
public enum WuMindPPTXExporter {
    public enum Failure: LocalizedError, Equatable, Sendable {
        case emptyDeck

        public var errorDescription: String? {
            switch self {
            case .emptyDeck: return "还没有可导出的 PPT 页面。"
            }
        }
    }

    // 16:9 widescreen slide canvas in EMUs (13.333 in × 7.5 in)
    public static let slideWidthEMU = 12_192_000
    public static let slideHeightEMU = 6_858_000

    /// Deterministic non-overlapping 16:9 slide geometry computed from actual title length & line wrapping.
    /// Guarantees `titleBottom < contentTop` and `contentBottom < traceabilityTop < footerTop` even when a title doubles in length.
    public struct SlideGeometry: Equatable, Sendable {
        public let titleX: Int
        public let titleY: Int
        public let titleWidth: Int
        public let titleHeight: Int
        public let titleFontSizePt: Int
        public let estimatedTitleLines: Int
        public let contentTop: Int
        public let contentHeight: Int
        public let traceabilityTop: Int
        public let footerTop: Int

        public var titleBottom: Int { titleY + titleHeight }
        public var contentBottom: Int { contentTop + contentHeight }
        public var hasZeroOverlap: Bool {
            titleBottom < contentTop && contentBottom < traceabilityTop && traceabilityTop < footerTop
        }
    }

    public static func computeSlideGeometry(for title: String, hasLogo: Bool = false) -> SlideGeometry {
        let titleX = 685_800
        let titleWidth = hasLogo ? 9_450_000 : 10_820_000
        let titleY = 470_000
        let traceabilityTop = 5_870_000
        let footerTop = 6_300_000

        // Weighted display units: CJK/full-width = 1.0, ASCII/narrow = 0.56
        let weightedUnits = title.unicodeScalars.reduce(0.0) { acc, scalar in
            acc + (scalar.value > 0x00FF ? 1.0 : 0.56)
        }

        // Approximate characters per line across titleWidth (10.82M EMU ~ 852pt, 9.45M EMU ~ 744pt)
        let widthFactor = Double(titleWidth) / 10_820_000.0
        let singleLineCap = 26.0 * widthFactor
        let twoLineCap = 58.0 * widthFactor

        let fontSizePt: Int
        let lines: Int
        let titleHeight: Int

        if weightedUnits <= singleLineCap {
            fontSizePt = 25
            lines = 1
            titleHeight = 680_000
        } else if weightedUnits <= twoLineCap {
            fontSizePt = 21
            lines = 2
            titleHeight = 980_000
        } else {
            fontSizePt = 18
            lines = 3
            titleHeight = 1_240_000
        }

        let contentTop = titleY + titleHeight + 130_000
        let maxContentBottom = traceabilityTop - 90_000
        let contentHeight = max(2_800_000, maxContentBottom - contentTop)

        return SlideGeometry(
            titleX: titleX,
            titleY: titleY,
            titleWidth: titleWidth,
            titleHeight: titleHeight,
            titleFontSizePt: fontSizePt,
            estimatedTitleLines: lines,
            contentTop: contentTop,
            contentHeight: contentHeight,
            traceabilityTop: traceabilityTop,
            footerTop: footerTop
        )
    }

    private struct ThemeColors {
        let bgHex: String
        let bgEndHex: String
        let cardHex: String
        let cardBorderHex: String
        let textHex: String
        let subTextHex: String
        let accentHex: String
        let accent2Hex: String
        let accent3Hex: String
        let accent4Hex: String
        let tableHeaderHex: String
        let tableHeaderTextHex: String
        let tableRowAltHex: String
        let tableBorderHex: String
        let chartBgHex: String
        let chartGridHex: String
    }

    private struct ChartArtifact {
        let chartIndex: Int
        let chartXML: String
        let chartRelsXML: String
        let xlsxData: Data
    }

    private struct ImageArtifact {
        let filename: String
        let data: Data
    }

    public static func make(deck: WuMindPPTDeck) throws -> Data {
        guard !deck.slides.isEmpty else { throw Failure.emptyDeck }
        let colors = themeColors(for: deck.theme)

        var files: [(String, Data)] = []
        var slideOverrides: [String] = []
        var notesOverrides: [String] = []
        var chartOverrides: [String] = []
        var presentationRels: [String] = [
            rel(id: "rId1", type: "http://schemas.openxmlformats.org/officeDocument/2006/relationships/slideMaster", target: "slideMasters/slideMaster1.xml"),
            rel(id: "rId2", type: "http://schemas.openxmlformats.org/officeDocument/2006/relationships/presProps", target: "presProps.xml"),
            rel(id: "rId3", type: "http://schemas.openxmlformats.org/officeDocument/2006/relationships/viewProps", target: "viewProps.xml"),
            rel(id: "rId4", type: "http://schemas.openxmlformats.org/officeDocument/2006/relationships/theme", target: "theme/theme1.xml"),
            rel(id: "rId5", type: "http://schemas.openxmlformats.org/officeDocument/2006/relationships/tableStyles", target: "tableStyles.xml"),
            rel(id: "rId6", type: "http://schemas.openxmlformats.org/officeDocument/2006/relationships/notesMaster", target: "notesMasters/notesMaster1.xml")
        ]
        var slideIdList: [String] = []
        var charts: [ChartArtifact] = []
        var images: [ImageArtifact] = []
        var hasJPEG = false
        var hasPNG = false

        var logoFilename: String? = nil
        if let logoB64 = deck.logoDataBase64,
           let rawLogo = Data(base64Encoded: logoB64),
           rawLogo.count > 16 {
            let isPNG = rawLogo.prefix(4) == Data([0x89, 0x50, 0x4E, 0x47])
            let ext = isPNG ? "png" : "jpg"
            if isPNG { hasPNG = true } else { hasJPEG = true }
            let fname = "logo.\(ext)"
            logoFilename = fname
            images.append(ImageArtifact(filename: fname, data: rawLogo))
        }

        let total = deck.slides.count
        var slideImageCounter = 0
        for (idx, slide) in deck.slides.enumerated() {
            let slideNum = idx + 1
            let presRelID = "rId\(10 + slideNum)"
            presentationRels.append(
                rel(id: presRelID, type: "http://schemas.openxmlformats.org/officeDocument/2006/relationships/slide", target: "slides/slide\(slideNum).xml")
            )
            slideIdList.append("<p:sldId id=\"\(255 + slideNum)\" r:id=\"\(presRelID)\"/>")
            slideOverrides.append("<Override PartName=\"/ppt/slides/slide\(slideNum).xml\" ContentType=\"application/vnd.openxmlformats-officedocument.presentationml.slide+xml\"/>")
            notesOverrides.append("<Override PartName=\"/ppt/notesSlides/notesSlide\(slideNum).xml\" ContentType=\"application/vnd.openxmlformats-officedocument.presentationml.notesSlide+xml\"/>")

            var slideRels: [String] = [
                rel(id: "rId1", type: "http://schemas.openxmlformats.org/officeDocument/2006/relationships/slideLayout", target: "../slideLayouts/slideLayout1.xml"),
                rel(id: "rId2", type: "http://schemas.openxmlformats.org/officeDocument/2006/relationships/notesSlide", target: "../notesSlides/notesSlide\(slideNum).xml")
            ]

            var chartRelID: String? = nil
            if let chartData = slide.chart,
               chartData.categories.count >= 2,
               !chartData.series.isEmpty {
                let cIdx = charts.count + 1
                let rId = "rId3"
                chartRelID = rId
                slideRels.append(
                    rel(id: rId, type: "http://schemas.openxmlformats.org/officeDocument/2006/relationships/chart", target: "../charts/chart\(cIdx).xml")
                )
                let chartXML = buildChartXML(chart: chartData, colors: colors)
                let chartRels = relsEnvelope([
                    rel(id: "rId1", type: "http://schemas.openxmlformats.org/officeDocument/2006/relationships/package", target: "../embeddings/Microsoft_Excel_Worksheet\(cIdx).xlsx")
                ])
                let xlsxData = buildEmbeddedWorkbookXLSX(chart: chartData)
                charts.append(ChartArtifact(chartIndex: cIdx, chartXML: chartXML, chartRelsXML: chartRels, xlsxData: xlsxData))
                chartOverrides.append("<Override PartName=\"/ppt/charts/chart\(cIdx).xml\" ContentType=\"application/vnd.openxmlformats-officedocument.drawingml.chart+xml\"/>")
            }

            var imageRelID: String? = nil
            if chartRelID == nil,
               slide.table == nil,
               let b64 = slide.imageDataBase64,
               let rawImg = Data(base64Encoded: b64),
               rawImg.count > 16 {
                slideImageCounter += 1
                let isPNG = rawImg.prefix(4) == Data([0x89, 0x50, 0x4E, 0x47])
                let ext = isPNG ? "png" : "jpg"
                if isPNG { hasPNG = true } else { hasJPEG = true }
                let fname = "image\(slideImageCounter).\(ext)"
                let rId = "rId4"
                imageRelID = rId
                slideRels.append(
                    rel(id: rId, type: "http://schemas.openxmlformats.org/officeDocument/2006/relationships/image", target: "../media/\(fname)")
                )
                images.append(ImageArtifact(filename: fname, data: rawImg))
            }

            var logoRelID: String? = nil
            if let logoFilename {
                let rId = "rId5"
                logoRelID = rId
                slideRels.append(
                    rel(id: rId, type: "http://schemas.openxmlformats.org/officeDocument/2006/relationships/image", target: "../media/\(logoFilename)")
                )
            }

            let slideXML = buildSlideXML(
                slide: slide,
                deck: deck,
                slideNumber: slideNum,
                totalSlides: total,
                colors: colors,
                chartRelID: chartRelID,
                imageRelID: imageRelID,
                logoRelID: logoRelID
            )
            let notesXML = buildNotesSlideXML(
                notesText: slide.speakerNotes,
                slideNumber: slideNum
            )
            let notesRels = relsEnvelope([
                rel(id: "rId1", type: "http://schemas.openxmlformats.org/officeDocument/2006/relationships/notesMaster", target: "../notesMasters/notesMaster1.xml"),
                rel(id: "rId2", type: "http://schemas.openxmlformats.org/officeDocument/2006/relationships/slide", target: "../slides/slide\(slideNum).xml")
            ])

            files.append(("ppt/slides/slide\(slideNum).xml", Data(slideXML.utf8)))
            files.append(("ppt/slides/_rels/slide\(slideNum).xml.rels", Data(relsEnvelope(slideRels).utf8)))
            files.append(("ppt/notesSlides/notesSlide\(slideNum).xml", Data(notesXML.utf8)))
            files.append(("ppt/notesSlides/_rels/notesSlide\(slideNum).xml.rels", Data(notesRels.utf8)))
        }

        for c in charts {
            files.append(("ppt/charts/chart\(c.chartIndex).xml", Data(c.chartXML.utf8)))
            files.append(("ppt/charts/_rels/chart\(c.chartIndex).xml.rels", Data(c.chartRelsXML.utf8)))
            files.append(("ppt/embeddings/Microsoft_Excel_Worksheet\(c.chartIndex).xlsx", c.xlsxData))
        }
        for img in images {
            files.append(("ppt/media/\(img.filename)", img.data))
        }

        let contentTypesXML = buildContentTypesXML(
            slideOverrides: slideOverrides,
            notesOverrides: notesOverrides,
            chartOverrides: chartOverrides,
            hasXLSX: !charts.isEmpty,
            hasJPEG: hasJPEG,
            hasPNG: hasPNG
        )
        let rootRelsXML = relsEnvelope([
            rel(id: "rId1", type: "http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument", target: "ppt/presentation.xml"),
            rel(id: "rId2", type: "http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties", target: "docProps/core.xml"),
            rel(id: "rId3", type: "http://schemas.openxmlformats.org/officeDocument/2006/relationships/extended-properties", target: "docProps/app.xml")
        ])

        var packageFiles: [(String, Data)] = [
            ("[Content_Types].xml", Data(contentTypesXML.utf8)),
            ("_rels/.rels", Data(rootRelsXML.utf8)),
            ("docProps/core.xml", Data(buildCorePropsXML(deck: deck).utf8)),
            ("docProps/app.xml", Data(buildAppPropsXML(slideCount: total, deck: deck).utf8)),
            ("ppt/presentation.xml", Data(buildPresentationXML(slideIdList: slideIdList).utf8)),
            ("ppt/_rels/presentation.xml.rels", Data(relsEnvelope(presentationRels).utf8)),
            ("ppt/presProps.xml", Data(presPropsXML.utf8)),
            ("ppt/viewProps.xml", Data(viewPropsXML.utf8)),
            ("ppt/tableStyles.xml", Data(tableStylesXML.utf8)),
            ("ppt/theme/theme1.xml", Data(buildThemeXML(colors: colors).utf8)),
            ("ppt/slideMasters/slideMaster1.xml", Data(buildSlideMasterXML(colors: colors).utf8)),
            ("ppt/slideMasters/_rels/slideMaster1.xml.rels", Data(relsEnvelope([
                rel(id: "rId1", type: "http://schemas.openxmlformats.org/officeDocument/2006/relationships/slideLayout", target: "../slideLayouts/slideLayout1.xml"),
                rel(id: "rId2", type: "http://schemas.openxmlformats.org/officeDocument/2006/relationships/theme", target: "../theme/theme1.xml")
            ]).utf8)),
            ("ppt/slideLayouts/slideLayout1.xml", Data(slideLayoutXML.utf8)),
            ("ppt/slideLayouts/_rels/slideLayout1.xml.rels", Data(relsEnvelope([
                rel(id: "rId1", type: "http://schemas.openxmlformats.org/officeDocument/2006/relationships/slideMaster", target: "../slideMasters/slideMaster1.xml")
            ]).utf8)),
            ("ppt/notesMasters/notesMaster1.xml", Data(notesMasterXML.utf8)),
            ("ppt/notesMasters/_rels/notesMaster1.xml.rels", Data(relsEnvelope([
                rel(id: "rId1", type: "http://schemas.openxmlformats.org/officeDocument/2006/relationships/theme", target: "../theme/theme1.xml")
            ]).utf8))
        ]
        packageFiles.append(contentsOf: files)
        return storedZIP(packageFiles)
    }

    // MARK: - Slide Builder (Strictly Non-Overlapping Dynamic 16:9 EMU Geometry)

    private static func buildSlideXML(
        slide: WuMindPPTDeck.Slide,
        deck: WuMindPPTDeck,
        slideNumber: Int,
        totalSlides: Int,
        colors: ThemeColors,
        chartRelID: String?,
        imageRelID: String?,
        logoRelID: String?
    ) -> String {
        var nextID = 2
        func allocID() -> Int {
            defer { nextID += 1 }
            return nextID
        }

        var shapes: [String] = []

        // Top accent bar (left)
        shapes.append(rectShape(
            id: allocID(),
            name: "AccentBar",
            x: 685_800, y: 340_000, cx: 760_000, cy: 64_000,
            fillHex: colors.accentHex
        ))

        // Optional Company Logo (cleanly placed in top-right header, zero overlap with title or slide number)
        if let logoRelID {
            let logoX = slide.layout == .cover ? 685_800 : 10_320_000
            let logoY = slide.layout == .cover ? 660_000 : 470_000
            let logoW = slide.layout == .cover ? 1_450_000 : 1_160_000
            let logoH = slide.layout == .cover ? 580_000 : 440_000
            shapes.append(pictureElement(
                id: allocID(),
                name: "CompanyLogo",
                x: logoX, y: logoY, cx: logoW, cy: logoH,
                relID: logoRelID
            ))
        }

        // Slide number badge (top right)
        shapes.append(textBox(
            id: allocID(),
            name: "SlideNumber",
            x: 10_200_000, y: 240_000, cx: 1_300_000, cy: 240_000,
            paragraphs: [
                paragraph(text: "\(slideNumber) / \(totalSlides)", fontSizePt: 11, bold: true, colorHex: colors.subTextHex, align: "r")
            ]
        ))

        if slide.layout == .cover {
            // Decorative right vertical accent ribbon
            shapes.append(rectShape(
                id: allocID(),
                name: "CoverDecorPanel",
                x: 11_300_000, y: 0, cx: 892_000, cy: slideHeightEMU,
                fillHex: colors.accentHex,
                alphaPercent: 18
            ))

            // Cover Title (dynamic font sizing so even long cover titles never clip)
            let coverTitleSize = slide.title.count > 26 ? 30 : 36
            shapes.append(textBox(
                id: allocID(),
                name: "CoverTitle",
                x: 685_800, y: 1_550_000, cx: 10_000_000, cy: 1_750_000,
                paragraphs: [
                    paragraph(text: slide.title, fontSizePt: coverTitleSize, bold: true, colorHex: colors.textHex, align: "l", spaceAfterPt: 10)
                ],
                verticalAlign: "b"
            ))

            // Cover Subtitle
            let subText = deck.subtitle.isEmpty ? "WUMIND 自主生成演示文稿" : deck.subtitle
            shapes.append(textBox(
                id: allocID(),
                name: "CoverSubtitle",
                x: 685_800, y: 3_420_000, cx: 9_800_000, cy: 880_000,
                paragraphs: [
                    paragraph(text: subText, fontSizePt: 18, bold: false, colorHex: colors.subTextHex, align: "l")
                ]
            ))

            // Cover metadata & optional opening highlights
            var metaLines: [String] = []
            if let aud = deck.audience {
                let durStr = deck.targetDurationMinutes.map { " · 约 \($0) 分钟" } ?? ""
                metaLines.append("目标受众：\(aud.title)\(durStr)")
            }
            if let src = deck.sourceFiles, !src.isEmpty {
                metaLines.append("参考资料：\(src.prefix(3).joined(separator: "、"))")
            }
            metaLines.append(contentsOf: slide.bullets.prefix(2))
            if !metaLines.isEmpty {
                let cardY = 4_550_000
                shapes.append(roundedCard(
                    id: allocID(),
                    name: "CoverMetaCard",
                    x: 685_800, y: cardY, cx: 9_400_000, cy: 1_180_000,
                    fillHex: colors.cardHex,
                    borderHex: colors.cardBorderHex,
                    paragraphs: metaLines.map {
                        paragraph(text: "• \($0)", fontSizePt: 13, bold: false, colorHex: colors.textHex, spaceAfterPt: 6)
                    }
                ))
            }
        } else {
            // Dynamic title-wrap & reflow geometry: guarantees zero overlap even when title doubles in length!
            let geom = computeSlideGeometry(for: slide.title, hasLogo: logoRelID != nil)
            shapes.append(textBox(
                id: allocID(),
                name: "SlideTitle",
                x: geom.titleX, y: geom.titleY, cx: geom.titleWidth, cy: geom.titleHeight,
                paragraphs: [
                    paragraph(text: slide.title, fontSizePt: geom.titleFontSizePt, bold: true, colorHex: colors.textHex, align: "l")
                ],
                verticalAlign: "ctr"
            ))

            let contentTop = geom.contentTop
            let contentHeight = geom.contentHeight

            if let chartRelID, let chart = slide.chart {
                // Left insights card (w = 3,720,000) + Right native editable chart (w = 6,860,000)
                let leftBullets = slide.bullets.isEmpty ? ["关键数据对比与趋势解读"] : Array(slide.bullets.prefix(4))
                var insightParas: [String] = [
                    paragraph(text: "核心洞察", fontSizePt: 14, bold: true, colorHex: colors.accentHex, spaceAfterPt: 10)
                ]
                for b in leftBullets {
                    insightParas.append(paragraph(text: "▪ \(b)", fontSizePt: 13, bold: false, colorHex: colors.textHex, spaceAfterPt: 10))
                }
                if let unit = chart.unit, !unit.isEmpty {
                    insightParas.append(paragraph(text: "统计单位：\(unit)", fontSizePt: 11, bold: false, colorHex: colors.subTextHex, spaceAfterPt: 4))
                }
                shapes.append(roundedCard(
                    id: allocID(),
                    name: "ChartInsightsCard",
                    x: 685_800, y: contentTop, cx: 3_720_000, cy: contentHeight,
                    fillHex: colors.cardHex,
                    borderHex: colors.cardBorderHex,
                    paragraphs: insightParas
                ))

                shapes.append(chartGraphicFrame(
                    id: allocID(),
                    name: "EditableChart",
                    x: 4_640_000, y: contentTop, cx: 6_865_000, cy: contentHeight,
                    relID: chartRelID
                ))
            } else if let table = slide.table, !table.headers.isEmpty {
                // Optional top summary strip + Native editable DrawingML table below (zero overlap!)
                var tableTop = contentTop
                var tableHeight = contentHeight
                let leadBullets = Array(slide.bullets.prefix(2))
                if !leadBullets.isEmpty {
                    let leadH = 920_000
                    shapes.append(roundedCard(
                        id: allocID(),
                        name: "TableSummaryCard",
                        x: 685_800, y: contentTop, cx: 10_820_000, cy: leadH,
                        fillHex: colors.cardHex,
                        borderHex: colors.cardBorderHex,
                        paragraphs: leadBullets.map {
                            paragraph(text: "▪ \($0)", fontSizePt: 13, bold: false, colorHex: colors.textHex, spaceAfterPt: 4)
                        }
                    ))
                    tableTop = contentTop + leadH + 180_000
                    tableHeight = contentHeight - leadH - 180_000
                }
                shapes.append(tableGraphicFrame(
                    id: allocID(),
                    name: "EditableTable",
                    x: 685_800, y: tableTop, cx: 10_820_000, cy: tableHeight,
                    table: table,
                    colors: colors
                ))
            } else if slide.layout == .metrics, let metric = slide.highlightMetric, !metric.isEmpty {
                // Left KPI card + Right structured bullets card
                var kpiParas: [String] = [
                    paragraph(text: metric, fontSizePt: 34, bold: true, colorHex: colors.accentHex, align: "l", spaceAfterPt: 10)
                ]
                if let label = slide.highlightLabel, !label.isEmpty {
                    kpiParas.append(paragraph(text: label, fontSizePt: 14, bold: true, colorHex: colors.textHex, align: "l", spaceAfterPt: 8))
                }
                if !slide.visualHint.isEmpty {
                    kpiParas.append(paragraph(text: slide.visualHint, fontSizePt: 11, bold: false, colorHex: colors.subTextHex, align: "l"))
                }
                shapes.append(roundedCard(
                    id: allocID(),
                    name: "MetricHighlightCard",
                    x: 685_800, y: contentTop, cx: 3_520_000, cy: contentHeight,
                    fillHex: colors.cardHex,
                    borderHex: colors.accentHex,
                    paragraphs: kpiParas,
                    verticalAlign: "ctr"
                ))

                let bulletParas = slide.bullets.prefix(4).map {
                    paragraph(text: "▪ \($0)", fontSizePt: 16, bold: false, colorHex: colors.textHex, spaceAfterPt: 14)
                }
                shapes.append(roundedCard(
                    id: allocID(),
                    name: "MetricDetailsCard",
                    x: 4_480_000, y: contentTop, cx: 7_025_000, cy: contentHeight,
                    fillHex: colors.cardHex,
                    borderHex: colors.cardBorderHex,
                    paragraphs: bulletParas
                ))
            } else if slide.layout == .twoColumn && slide.bullets.count >= 2 {
                let mid = (slide.bullets.count + 1) / 2
                let leftItems = Array(slide.bullets.prefix(mid))
                let rightItems = Array(slide.bullets.dropFirst(mid))
                shapes.append(roundedCard(
                    id: allocID(),
                    name: "LeftColumnCard",
                    x: 685_800, y: contentTop, cx: 5_240_000, cy: contentHeight,
                    fillHex: colors.cardHex,
                    borderHex: colors.cardBorderHex,
                    paragraphs: [
                        paragraph(text: "核心模块 A", fontSizePt: 14, bold: true, colorHex: colors.accentHex, spaceAfterPt: 10)
                    ] + leftItems.map {
                        paragraph(text: "▪ \($0)", fontSizePt: 15, bold: false, colorHex: colors.textHex, spaceAfterPt: 12)
                    }
                ))
                shapes.append(roundedCard(
                    id: allocID(),
                    name: "RightColumnCard",
                    x: 6_265_000, y: contentTop, cx: 5_240_000, cy: contentHeight,
                    fillHex: colors.cardHex,
                    borderHex: colors.cardBorderHex,
                    paragraphs: [
                        paragraph(text: "核心模块 B", fontSizePt: 14, bold: true, colorHex: colors.accent2Hex, spaceAfterPt: 10)
                    ] + rightItems.map {
                        paragraph(text: "▪ \($0)", fontSizePt: 15, bold: false, colorHex: colors.textHex, spaceAfterPt: 12)
                    }
                ))
            } else if let imageRelID {
                // Left bullet card + Right native embedded picture
                let bulletParas = slide.bullets.prefix(4).map {
                    paragraph(text: "▪ \($0)", fontSizePt: 15, bold: false, colorHex: colors.textHex, spaceAfterPt: 13)
                }
                shapes.append(roundedCard(
                    id: allocID(),
                    name: "ImageTextCard",
                    x: 685_800, y: contentTop, cx: 5_800_000, cy: contentHeight,
                    fillHex: colors.cardHex,
                    borderHex: colors.cardBorderHex,
                    paragraphs: bulletParas
                ))
                shapes.append(pictureElement(
                    id: allocID(),
                    name: "SlideVisual",
                    x: 6_740_000, y: contentTop, cx: 4_765_000, cy: contentHeight,
                    relID: imageRelID
                ))
            } else {
                // Full-width structured bullets / agenda / summary card
                let fontSize = slide.bullets.count >= 5 ? 15 : 17
                let bulletParas = slide.bullets.prefix(5).enumerated().map { idx, item in
                    let prefix = slide.layout == .agenda ? "0\(idx + 1)  " : "▪ "
                    return paragraph(text: "\(prefix)\(item)", fontSizePt: fontSize, bold: false, colorHex: colors.textHex, spaceAfterPt: 14)
                }
                shapes.append(roundedCard(
                    id: allocID(),
                    name: "MainBodyCard",
                    x: 685_800, y: contentTop, cx: 10_820_000, cy: contentHeight,
                    fillHex: colors.cardHex,
                    borderHex: colors.cardBorderHex,
                    paragraphs: bulletParas
                ))
            }
        }

        // Source citation / pending items traceability bar (y = 5,860,000 ... 6,220,000)
        var traceParts: [String] = []
        if let cites = slide.citations, !cites.isEmpty {
            traceParts.append("出处：\(cites.prefix(2).joined(separator: " | "))")
        }
        if let pending = slide.pendingItems, !pending.isEmpty {
            traceParts.append("待补：\(pending.prefix(2).joined(separator: "；"))")
        }
        if !traceParts.isEmpty {
            shapes.append(textBox(
                id: allocID(),
                name: "TraceabilityNote",
                x: 685_800, y: 5_870_000, cx: 10_820_000, cy: 340_000,
                paragraphs: [
                    paragraph(text: String(traceParts.joined(separator: "   ·   ").prefix(115)), fontSizePt: 10, bold: false, colorHex: colors.accentHex, align: "l")
                ]
            ))
        }

        // Footer watermark (y = 6,300,000)
        shapes.append(textBox(
            id: allocID(),
            name: "SlideFooter",
            x: 685_800, y: 6_300_000, cx: 10_820_000, cy: 280_000,
            paragraphs: [
                paragraph(text: "WUMIND AI PPT Studio  ·  \(deck.title)", fontSizePt: 10, bold: false, colorHex: colors.subTextHex, align: "l")
            ]
        ))

        return xmlHeader + """
        <p:sld xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main">
          <p:cSld>
            <p:bg>
              <p:bgPr>
                <a:gradFill flip="none" rotWithShape="1">
                  <a:gsLst>
                    <a:gs pos="0"><a:srgbClr val="\(colors.bgHex)"/></a:gs>
                    <a:gs pos="100000"><a:srgbClr val="\(colors.bgEndHex)"/></a:gs>
                  </a:gsLst>
                  <a:lin ang="2700000" scaled="1"/>
                </a:gradFill>
                <a:effectLst/>
              </p:bgPr>
            </p:bg>
            <p:spTree>
              <p:nvGrpSpPr>
                <p:cNvPr id="1" name=""/>
                <p:cNvGrpSpPr/>
                <p:nvPr/>
              </p:nvGrpSpPr>
              <p:grpSpPr>
                <a:xfrm>
                  <a:off x="0" y="0"/>
                  <a:ext cx="0" cy="0"/>
                  <a:chOff x="0" y="0"/>
                  <a:chExt cx="0" cy="0"/>
                </a:xfrm>
              </p:grpSpPr>
              \(shapes.joined(separator: "\n"))
            </p:spTree>
          </p:cSld>
          <p:clrMapOvr><a:masterClrMapping/></p:clrMapOvr>
        </p:sld>
        """
    }

    // MARK: - Native Editable DrawingML Table (<a:tbl>)

    private static func tableGraphicFrame(
        id: Int,
        name: String,
        x: Int, y: Int, cx: Int, cy: Int,
        table: WuMindPPTDeck.TableData,
        colors: ThemeColors
    ) -> String {
        let colCount = max(1, table.headers.count)
        let colWidth = cx / colCount
        let lastColWidth = cx - colWidth * (colCount - 1)
        let widths = (0..<colCount).map { $0 == colCount - 1 ? lastColWidth : colWidth }
        let totalRows = 1 + table.rows.count
        let rowHeight = max(340_000, min(680_000, cy / max(1, totalRows)))

        let gridCols = widths.map { "<a:gridCol w=\"\($0)\"/>" }.joined()

        func makeCell(text: String, fillHex: String, textHex: String, bold: Bool, fontSizePt: Int) -> String {
            let border = "<a:ln w=\"12700\" cap=\"flat\" cmpd=\"sng\" algn=\"ctr\"><a:solidFill><a:srgbClr val=\"\(colors.tableBorderHex)\"/></a:solidFill></a:ln>"
            let lnL = border.replacingOccurrences(of: "<a:ln ", with: "<a:lnL ").replacingOccurrences(of: "</a:ln>", with: "</a:lnL>")
            let lnR = border.replacingOccurrences(of: "<a:ln ", with: "<a:lnR ").replacingOccurrences(of: "</a:ln>", with: "</a:lnR>")
            let lnT = border.replacingOccurrences(of: "<a:ln ", with: "<a:lnT ").replacingOccurrences(of: "</a:ln>", with: "</a:lnT>")
            let lnB = border.replacingOccurrences(of: "<a:ln ", with: "<a:lnB ").replacingOccurrences(of: "</a:ln>", with: "</a:lnB>")
            return """
            <a:tc>
              <a:txBody>
                <a:bodyPr wrap="square"/>
                <a:lstStyle/>
                \(paragraph(text: text, fontSizePt: fontSizePt, bold: bold, colorHex: textHex, align: "l"))
              </a:txBody>
              <a:tcPr marL="91440" marR="91440" marT="55000" marB="55000" anchor="ctr">
                \(lnL)\(lnR)\(lnT)\(lnB)
                <a:solidFill><a:srgbClr val="\(fillHex)"/></a:solidFill>
              </a:tcPr>
            </a:tc>
            """
        }

        let headerRowXML = "<a:tr h=\"\(rowHeight)\">"
            + table.headers.map { makeCell(text: $0, fillHex: colors.tableHeaderHex, textHex: colors.tableHeaderTextHex, bold: true, fontSizePt: 13) }.joined()
            + "</a:tr>"

        let bodyRowsXML = table.rows.enumerated().map { rIdx, row in
            let bg = (rIdx % 2 == 0) ? colors.cardHex : colors.tableRowAltHex
            let padded = (0..<colCount).map { cIdx in cIdx < row.count ? row[cIdx] : "【待补】" }
            let cells = padded.map { cellText in
                let isPending = cellText.contains("待补")
                return makeCell(
                    text: cellText,
                    fillHex: bg,
                    textHex: isPending ? colors.accentHex : colors.textHex,
                    bold: isPending,
                    fontSizePt: 12
                )
            }.joined()
            return "<a:tr h=\"\(rowHeight)\">\(cells)</a:tr>"
        }.joined()

        return """
        <p:graphicFrame>
          <p:nvGraphicFramePr>
            <p:cNvPr id="\(id)" name="\(escapeXML(name))"/>
            <p:cNvGraphicFramePr><a:graphicFrameLocks noGrp="1"/></p:cNvGraphicFramePr>
            <p:nvPr/>
          </p:nvGraphicFramePr>
          <p:xfrm><a:off x="\(x)" y="\(y)"/><a:ext cx="\(cx)" cy="\(cy)"/></p:xfrm>
          <a:graphic>
            <a:graphicData uri="http://schemas.openxmlformats.org/drawingml/2006/table">
              <a:tbl>
                <a:tblPr firstRow="1" bandRow="1"/>
                <a:tblGrid>\(gridCols)</a:tblGrid>
                \(headerRowXML)
                \(bodyRowsXML)
              </a:tbl>
            </a:graphicData>
          </a:graphic>
        </p:graphicFrame>
        """
    }

    // MARK: - Native Editable DrawingML Chart + Embedded Real Excel (.xlsx) Workbook

    private static func chartGraphicFrame(id: Int, name: String, x: Int, y: Int, cx: Int, cy: Int, relID: String) -> String {
        """
        <p:graphicFrame>
          <p:nvGraphicFramePr>
            <p:cNvPr id="\(id)" name="\(escapeXML(name))"/>
            <p:cNvGraphicFramePr/>
            <p:nvPr/>
          </p:nvGraphicFramePr>
          <p:xfrm><a:off x="\(x)" y="\(y)"/><a:ext cx="\(cx)" cy="\(cy)"/></p:xfrm>
          <a:graphic>
            <a:graphicData uri="http://schemas.openxmlformats.org/drawingml/2006/chart">
              <c:chart xmlns:c="http://schemas.openxmlformats.org/drawingml/2006/chart" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" r:id="\(relID)"/>
            </a:graphicData>
          </a:graphic>
        </p:graphicFrame>
        """
    }

    private static func buildChartXML(chart: WuMindPPTDeck.ChartData, colors: ThemeColors) -> String {
        let seriesPalette = [colors.accentHex, colors.accent2Hex, colors.accent3Hex, colors.accent4Hex]
        let catCount = chart.categories.count
        let lastRow = catCount + 1

        let catPoints = chart.categories.enumerated().map { i, label in
            "<c:pt idx=\"\(i)\"><c:v>\(escapeXML(label))</c:v></c:pt>"
        }.joined()
        let catRefXML = """
        <c:cat>
          <c:strRef>
            <c:f>Sheet1!$A$2:$A$\(lastRow)</c:f>
            <c:strCache>
              <c:ptCount val="\(catCount)"/>
              \(catPoints)
            </c:strCache>
          </c:strRef>
        </c:cat>
        """

        func buildSeriesXML(index: Int, series: WuMindPPTDeck.ChartSeries, isLine: Bool, isPie: Bool) -> String {
            let colLetter = excelColumnLetter(index + 2) // B, C, D, E
            let colorHex = seriesPalette[index % seriesPalette.count]
            let isPct = series.isPercentage == true
            let fmtCode = isPct ? "0.0%" : "General"
            let valPoints = series.values.prefix(catCount).enumerated().compactMap { i, optVal -> String? in
                guard let val = optVal, val.isFinite else { return nil }
                return "<c:pt idx=\"\(i)\"><c:v>\(formatXMLNumber(val))</c:v></c:pt>"
            }.joined()

            let spPrXML: String
            if isLine {
                spPrXML = """
                <c:spPr><a:ln w="28575" cap="rnd"><a:solidFill><a:srgbClr val="\(colorHex)"/></a:solidFill></a:ln></c:spPr>
                <c:marker><c:symbol val="circle"/><c:size val="6"/><c:spPr><a:solidFill><a:srgbClr val="\(colorHex)"/></a:solidFill></c:spPr></c:marker>
                """
            } else if isPie {
                let dPts = (0..<catCount).map { ptIdx in
                    let sliceHex = seriesPalette[ptIdx % seriesPalette.count]
                    return "<c:dPt><c:idx val=\"\(ptIdx)\"/><c:bubble3D val=\"0\"/><c:spPr><a:solidFill><a:srgbClr val=\"\(sliceHex)\"/></a:solidFill></c:spPr></c:dPt>"
                }.joined()
                spPrXML = dPts
            } else {
                spPrXML = "<c:spPr><a:solidFill><a:srgbClr val=\"\(colorHex)\"/></a:solidFill><a:ln><a:noFill/></a:ln></c:spPr>"
            }

            return """
            <c:ser>
              <c:idx val="\(index)"/>
              <c:order val="\(index)"/>
              <c:tx>
                <c:strRef>
                  <c:f>Sheet1!$\(colLetter)$1</c:f>
                  <c:strCache>
                    <c:ptCount val="1"/>
                    <c:pt idx="0"><c:v>\(escapeXML(series.name))</c:v></c:pt>
                  </c:strCache>
                </c:strRef>
              </c:tx>
              \(spPrXML)
              \(catRefXML)
              <c:val>
                <c:numRef>
                  <c:f>Sheet1!$\(colLetter)$2:$\(colLetter)$\(lastRow)</c:f>
                  <c:numCache>
                    <c:formatCode>\(fmtCode)</c:formatCode>
                    <c:ptCount val="\(catCount)"/>
                    \(valPoints)
                  </c:numCache>
                </c:numRef>
              </c:val>
            </c:ser>
            """
        }

        let allPercentage = !chart.series.isEmpty && chart.series.allSatisfy { $0.isPercentage == true }
        let axisFormatCode = allPercentage ? "0.0%" : "General"

        let plotBodyXML: String
        switch chart.kind {
        case .pie:
            let ser = buildSeriesXML(index: 0, series: chart.series[0], isLine: false, isPie: true)
            plotBodyXML = """
            <c:pieChart>
              <c:varyColors val="1"/>
              \(ser)
              <c:dLbls>
                <c:txPr><a:bodyPr/><a:lstStyle/><a:p><a:pPr><a:defRPr sz="1000"><a:solidFill><a:srgbClr val="\(colors.textHex)"/></a:solidFill></a:defRPr></a:pPr><a:endParaRPr lang="zh-CN"/></a:p></c:txPr>
                <c:showLegendKey val="0"/><c:showVal val="1"/><c:showCatName val="1"/><c:showSerName val="0"/><c:showPercent val="1"/><c:showBubbleSize val="0"/>
              </c:dLbls>
              <c:firstSliceAng val="0"/>
            </c:pieChart>
            """
        case .line:
            let sers = chart.series.enumerated().map { buildSeriesXML(index: $0.offset, series: $0.element, isLine: true, isPie: false) }.joined()
            plotBodyXML = """
            <c:lineChart>
              <c:grouping val="standard"/>
              <c:varyColors val="0"/>
              \(sers)
              <c:dLbls>
                <c:txPr><a:bodyPr/><a:lstStyle/><a:p><a:pPr><a:defRPr sz="950"><a:solidFill><a:srgbClr val="\(colors.textHex)"/></a:solidFill></a:defRPr></a:pPr><a:endParaRPr lang="zh-CN"/></a:p></c:txPr>
                <c:showLegendKey val="0"/><c:showVal val="1"/><c:showCatName val="0"/><c:showSerName val="0"/><c:showPercent val="0"/><c:showBubbleSize val="0"/>
              </c:dLbls>
              <c:marker val="1"/>
              <c:smooth val="0"/>
              <c:axId val="1001"/>
              <c:axId val="1002"/>
            </c:lineChart>
            \(chartAxesXML(colors: colors, valAxisFormatCode: axisFormatCode))
            """
        case .bar:
            let sers = chart.series.enumerated().map { buildSeriesXML(index: $0.offset, series: $0.element, isLine: false, isPie: false) }.joined()
            plotBodyXML = """
            <c:barChart>
              <c:barDir val="col"/>
              <c:grouping val="clustered"/>
              <c:varyColors val="0"/>
              \(sers)
              <c:dLbls>
                <c:txPr><a:bodyPr/><a:lstStyle/><a:p><a:pPr><a:defRPr sz="950"><a:solidFill><a:srgbClr val="\(colors.textHex)"/></a:solidFill></a:defRPr></a:pPr><a:endParaRPr lang="zh-CN"/></a:p></c:txPr>
                <c:showLegendKey val="0"/><c:showVal val="1"/><c:showCatName val="0"/><c:showSerName val="0"/><c:showPercent val="0"/><c:showBubbleSize val="0"/>
              </c:dLbls>
              <c:gapWidth val="120"/>
              <c:axId val="1001"/>
              <c:axId val="1002"/>
            </c:barChart>
            \(chartAxesXML(colors: colors, valAxisFormatCode: axisFormatCode))
            """
        }

        let displayTitle = chart.unit.map { "\(chart.title)（\($0)）" } ?? chart.title
        return xmlHeader + """
        <c:chartSpace xmlns:c="http://schemas.openxmlformats.org/drawingml/2006/chart" xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
          <c:date1904 val="0"/>
          <c:lang val="zh-CN"/>
          <c:roundedCorners val="0"/>
          <c:chart>
            <c:title>
              <c:tx>
                <c:rich>
                  <a:bodyPr/>
                  <a:lstStyle/>
                  <a:p>
                    <a:pPr><a:defRPr sz="1400" b="1"><a:solidFill><a:srgbClr val="\(colors.textHex)"/></a:solidFill></a:defRPr></a:pPr>
                    <a:r><a:rPr lang="zh-CN" sz="1400" b="1"><a:solidFill><a:srgbClr val="\(colors.textHex)"/></a:solidFill></a:rPr><a:t>\(escapeXML(displayTitle))</a:t></a:r>
                  </a:p>
                </c:rich>
              </c:tx>
              <c:overlay val="0"/>
            </c:title>
            <c:autoTitleDeleted val="0"/>
            <c:plotArea>
              <c:layout/>
              \(plotBodyXML)
            </c:plotArea>
            <c:legend>
              <c:legendPos val="b"/>
              <c:overlay val="0"/>
              <c:txPr><a:bodyPr/><a:lstStyle/><a:p><a:pPr><a:defRPr sz="1000"><a:solidFill><a:srgbClr val="\(colors.subTextHex)"/></a:solidFill></a:defRPr></a:pPr><a:endParaRPr lang="zh-CN"/></a:p></c:txPr>
            </c:legend>
            <c:plotVisOnly val="1"/>
            <c:dispBlanksAs val="gap"/>
          </c:chart>
          <c:spPr>
            <a:solidFill><a:srgbClr val="\(colors.chartBgHex)"/></a:solidFill>
            <a:ln w="12700"><a:solidFill><a:srgbClr val="\(colors.cardBorderHex)"/></a:solidFill></a:ln>
          </c:spPr>
          <c:externalData r:id="rId1"><c:autoUpdate val="0"/></c:externalData>
        </c:chartSpace>
        """
    }

    private static func chartAxesXML(colors: ThemeColors, valAxisFormatCode: String = "General") -> String {
        """
        <c:catAx>
          <c:axId val="1001"/>
          <c:scaling><c:orientation val="minMax"/></c:scaling>
          <c:delete val="0"/>
          <c:axPos val="b"/>
          <c:majorTickMark val="none"/>
          <c:minorTickMark val="none"/>
          <c:tickLblPos val="nextTo"/>
          <c:spPr><a:ln w="9525"><a:solidFill><a:srgbClr val="\(colors.chartGridHex)"/></a:solidFill></a:ln></c:spPr>
          <c:txPr><a:bodyPr/><a:lstStyle/><a:p><a:pPr><a:defRPr sz="1000"><a:solidFill><a:srgbClr val="\(colors.subTextHex)"/></a:solidFill></a:defRPr></a:pPr><a:endParaRPr lang="zh-CN"/></a:p></c:txPr>
          <c:crossAx val="1002"/>
          <c:crosses val="autoZero"/>
          <c:auto val="1"/>
          <c:lblAlgn val="ctr"/>
          <c:lblOffset val="100"/>
        </c:catAx>
        <c:valAx>
          <c:axId val="1002"/>
          <c:scaling><c:orientation val="minMax"/></c:scaling>
          <c:delete val="0"/>
          <c:axPos val="l"/>
          <c:majorGridlines><c:spPr><a:ln w="6350"><a:solidFill><a:srgbClr val="\(colors.chartGridHex)"/></a:solidFill></a:ln></c:spPr></c:majorGridlines>
          <c:numFmt formatCode="\(valAxisFormatCode)" sourceLinked="1"/>
          <c:majorTickMark val="none"/>
          <c:minorTickMark val="none"/>
          <c:tickLblPos val="nextTo"/>
          <c:spPr><a:ln><a:noFill/></a:ln></c:spPr>
          <c:txPr><a:bodyPr/><a:lstStyle/><a:p><a:pPr><a:defRPr sz="1000"><a:solidFill><a:srgbClr val="\(colors.subTextHex)"/></a:solidFill></a:defRPr></a:pPr><a:endParaRPr lang="zh-CN"/></a:p></c:txPr>
          <c:crossAx val="1001"/>
          <c:crosses val="autoZero"/>
          <c:crossBetween val="between"/>
        </c:valAx>
        """
    }

    /// Generates a real, minimal, ECMA-376 valid Excel `.xlsx` workbook embedded inside each chart
    /// so clicking "Edit Data / 编辑数据" in PowerPoint or WPS opens the live editable spreadsheet.
    /// Missing (`nil`) values are left genuinely blank in the worksheet (never coerced to `0`).
    private static func buildEmbeddedWorkbookXLSX(chart: WuMindPPTDeck.ChartData) -> Data {
        let seriesToWrite = chart.kind == .pie ? Array(chart.series.prefix(1)) : chart.series
        var rowsXML = ""

        // Header row 1: A1 = "类目", B1.. = series names
        var headerCells = "<c r=\"A1\" t=\"inlineStr\"><is><t>类目</t></is></c>"
        for (idx, ser) in seriesToWrite.enumerated() {
            let col = excelColumnLetter(idx + 2)
            headerCells += "<c r=\"\(col)1\" t=\"inlineStr\"><is><t>\(escapeXML(ser.name))</t></is></c>"
        }
        rowsXML += "<row r=\"1\">\(headerCells)</row>"

        // Data rows 2..N+1 (missing nil values stay genuinely blank; genuine 0 writes <v>0</v>)
        for (catIdx, category) in chart.categories.enumerated() {
            let rowNum = catIdx + 2
            var cells = "<c r=\"A\(rowNum)\" t=\"inlineStr\"><is><t>\(escapeXML(category))</t></is></c>"
            for (sIdx, ser) in seriesToWrite.enumerated() {
                let col = excelColumnLetter(sIdx + 2)
                if catIdx < ser.values.count, let val = ser.values[catIdx], val.isFinite {
                    let styleAttr = ser.isPercentage == true ? " s=\"1\"" : ""
                    cells += "<c r=\"\(col)\(rowNum)\"\(styleAttr)><v>\(formatXMLNumber(val))</v></c>"
                }
            }
            rowsXML += "<row r=\"\(rowNum)\">\(cells)</row>"
        }

        let lastCol = excelColumnLetter(seriesToWrite.count + 1)
        let lastRow = chart.categories.count + 1
        let sheetXML = xmlHeader + """
        <worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
          <dimension ref="A1:\(lastCol)\(lastRow)"/>
          <sheetViews><sheetView tabSelected="1" workbookViewId="0"/></sheetViews>
          <sheetFormatPr defaultRowHeight="15"/>
          <sheetData>\(rowsXML)</sheetData>
        </worksheet>
        """

        let workbookXML = xmlHeader + """
        <workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
          <sheets><sheet name="Sheet1" sheetId="1" r:id="rId1"/></sheets>
        </workbook>
        """

        let wbRels = relsEnvelope([
            rel(id: "rId1", type: "http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet", target: "worksheets/sheet1.xml"),
            rel(id: "rId2", type: "http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles", target: "styles.xml")
        ])

        let rootRels = relsEnvelope([
            rel(id: "rId1", type: "http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument", target: "xl/workbook.xml")
        ])

        let xlStylesXML = xmlHeader + """
        <styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
          <numFmts count="1"><numFmt numFmtId="164" formatCode="0.0%"/></numFmts>
          <fonts count="1"><font><sz val="11"/><name val="Calibri"/></font></fonts>
          <fills count="2"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill></fills>
          <borders count="1"><border><left/><right/><top/><bottom/><diagonal/></border></borders>
          <cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>
          <cellXfs count="2">
            <xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/>
            <xf numFmtId="164" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1"/>
          </cellXfs>
        </styleSheet>
        """

        let xlContentTypes = xmlHeader + """
        <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
          <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
          <Default Extension="xml" ContentType="application/xml"/>
          <Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>
          <Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>
          <Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>
        </Types>
        """

        return storedZIP([
            ("[Content_Types].xml", Data(xlContentTypes.utf8)),
            ("_rels/.rels", Data(rootRels.utf8)),
            ("xl/workbook.xml", Data(workbookXML.utf8)),
            ("xl/_rels/workbook.xml.rels", Data(wbRels.utf8)),
            ("xl/styles.xml", Data(xlStylesXML.utf8)),
            ("xl/worksheets/sheet1.xml", Data(sheetXML.utf8))
        ])
    }

    // MARK: - Native Shapes, Text Boxes, Pictures & Speaker Notes

    private static func rectShape(
        id: Int, name: String,
        x: Int, y: Int, cx: Int, cy: Int,
        fillHex: String,
        alphaPercent: Int = 100
    ) -> String {
        let alphaXML = alphaPercent < 100 ? "<a:alpha val=\"\(alphaPercent * 1000)\"/>" : ""
        return """
        <p:sp>
          <p:nvSpPr><p:cNvPr id="\(id)" name="\(escapeXML(name))"/><p:cNvSpPr/><p:nvPr/></p:nvSpPr>
          <p:spPr>
            <a:xfrm><a:off x="\(x)" y="\(y)"/><a:ext cx="\(cx)" cy="\(cy)"/></a:xfrm>
            <a:prstGeom prst="roundRect"><a:avLst><a:gd name="adj" fmla="val 50000"/></a:avLst></a:prstGeom>
            <a:solidFill><a:srgbClr val="\(fillHex)">\(alphaXML)</a:srgbClr></a:solidFill>
            <a:ln><a:noFill/></a:ln>
          </p:spPr>
        </p:sp>
        """
    }

    private static func roundedCard(
        id: Int, name: String,
        x: Int, y: Int, cx: Int, cy: Int,
        fillHex: String,
        borderHex: String,
        paragraphs: [String],
        verticalAlign: String = "t"
    ) -> String {
        let bodyParas = paragraphs.isEmpty ? "<a:p><a:endParaRPr lang=\"zh-CN\"/></a:p>" : paragraphs.joined(separator: "\n")
        return """
        <p:sp>
          <p:nvSpPr><p:cNvPr id="\(id)" name="\(escapeXML(name))"/><p:cNvSpPr/><p:nvPr/></p:nvSpPr>
          <p:spPr>
            <a:xfrm><a:off x="\(x)" y="\(y)"/><a:ext cx="\(cx)" cy="\(cy)"/></a:xfrm>
            <a:prstGeom prst="roundRect"><a:avLst><a:gd name="adj" fmla="val 4500"/></a:avLst></a:prstGeom>
            <a:solidFill><a:srgbClr val="\(fillHex)"/></a:solidFill>
            <a:ln w="12700"><a:solidFill><a:srgbClr val="\(borderHex)"/></a:solidFill></a:ln>
          </p:spPr>
          <p:txBody>
            <a:bodyPr wrap="square" lIns="220000" tIns="190000" rIns="220000" bIns="190000" anchor="\(verticalAlign)">
              <a:normAutofit/>
            </a:bodyPr>
            <a:lstStyle/>
            \(bodyParas)
          </p:txBody>
        </p:sp>
        """
    }

    private static func textBox(
        id: Int, name: String,
        x: Int, y: Int, cx: Int, cy: Int,
        paragraphs: [String],
        verticalAlign: String = "t"
    ) -> String {
        let bodyParas = paragraphs.isEmpty ? "<a:p><a:endParaRPr lang=\"zh-CN\"/></a:p>" : paragraphs.joined(separator: "\n")
        return """
        <p:sp>
          <p:nvSpPr><p:cNvPr id="\(id)" name="\(escapeXML(name))"/><p:cNvSpPr txBox="1"/><p:nvPr/></p:nvSpPr>
          <p:spPr>
            <a:xfrm><a:off x="\(x)" y="\(y)"/><a:ext cx="\(cx)" cy="\(cy)"/></a:xfrm>
            <a:prstGeom prst="rect"><a:avLst/></a:prstGeom>
            <a:noFill/>
            <a:ln><a:noFill/></a:ln>
          </p:spPr>
          <p:txBody>
            <a:bodyPr wrap="square" lIns="45720" tIns="22860" rIns="45720" bIns="22860" anchor="\(verticalAlign)">
              <a:normAutofit/>
            </a:bodyPr>
            <a:lstStyle/>
            \(bodyParas)
          </p:txBody>
        </p:sp>
        """
    }

    private static func pictureElement(id: Int, name: String, x: Int, y: Int, cx: Int, cy: Int, relID: String) -> String {
        """
        <p:pic>
          <p:nvPicPr>
            <p:cNvPr id="\(id)" name="\(escapeXML(name))"/>
            <p:cNvPicPr><a:picLocks noChangeAspect="1"/></p:cNvPicPr>
            <p:nvPr/>
          </p:nvPicPr>
          <p:blipFill>
            <a:blip r:embed="\(relID)"/>
            <a:stretch><a:fillRect/></a:stretch>
          </p:blipFill>
          <p:spPr>
            <a:xfrm><a:off x="\(x)" y="\(y)"/><a:ext cx="\(cx)" cy="\(cy)"/></a:xfrm>
            <a:prstGeom prst="roundRect"><a:avLst><a:gd name="adj" fmla="val 4000"/></a:avLst></a:prstGeom>
          </p:spPr>
        </p:pic>
        """
    }

    private static func paragraph(
        text: String,
        fontSizePt: Int,
        bold: Bool,
        colorHex: String,
        align: String = "l",
        spaceAfterPt: Int = 0
    ) -> String {
        let sz = fontSizePt * 100
        let boldAttr = bold ? " b=\"1\"" : ""
        let spcAft = spaceAfterPt > 0 ? "<a:spcAft><a:spcPts val=\"\(spaceAfterPt * 100)\"/></a:spcAft>" : ""
        return """
        <a:p>
          <a:pPr algn="\(align)">\(spcAft)</a:pPr>
          <a:r>
            <a:rPr lang="zh-CN" altLang="en-US" sz="\(sz)"\(boldAttr) dirty="0">
              <a:solidFill><a:srgbClr val="\(colorHex)"/></a:solidFill>
              <a:latin typeface="Calibri"/>
              <a:ea typeface="PingFang SC"/>
            </a:rPr>
            <a:t>\(escapeXML(text))</a:t>
          </a:r>
          <a:endParaRPr lang="zh-CN" sz="\(sz)"/>
        </a:p>
        """
    }

    private static func buildNotesSlideXML(notesText: String, slideNumber: Int) -> String {
        let clean = notesText.trimmingCharacters(in: .whitespacesAndNewlines)
        let lines = (clean.isEmpty ? "第 \(slideNumber) 页演示备注" : clean).components(separatedBy: .newlines)
        let paras = lines.map { line in
            "<a:p><a:r><a:rPr lang=\"zh-CN\" sz=\"1200\"/><a:t>\(escapeXML(line))</a:t></a:r><a:endParaRPr lang=\"zh-CN\" sz=\"1200\"/></a:p>"
        }.joined()
        return xmlHeader + """
        <p:notes xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main">
          <p:cSld>
            <p:spTree>
              <p:nvGrpSpPr><p:cNvPr id="1" name=""/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr>
              <p:grpSpPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="0" cy="0"/><a:chOff x="0" y="0"/><a:chExt cx="0" cy="0"/></a:xfrm></p:grpSpPr>
              <p:sp>
                <p:nvSpPr><p:cNvPr id="2" name="Slide Image Placeholder 1"/><p:cNvSpPr><a:spLocks noGrp="1" noRot="1" noChangeAspect="1"/></p:cNvSpPr><p:nvPr><p:ph type="sldImg"/></p:nvPr></p:nvSpPr>
                <p:spPr/>
              </p:sp>
              <p:sp>
                <p:nvSpPr><p:cNvPr id="3" name="Notes Placeholder 2"/><p:cNvSpPr><a:spLocks noGrp="1"/></p:cNvSpPr><p:nvPr><p:ph type="body" idx="1"/></p:nvPr></p:nvSpPr>
                <p:spPr/>
                <p:txBody>
                  <a:bodyPr/>
                  <a:lstStyle/>
                  \(paras)
                </p:txBody>
              </p:sp>
            </p:spTree>
          </p:cSld>
          <p:clrMapOvr><a:masterClrMapping/></p:clrMapOvr>
        </p:notes>
        """
    }

    // MARK: - Package Scaffolding XML (Masters, Layouts, Theme, Props, Content Types)

    private static let xmlHeader = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n"

    private static func buildContentTypesXML(
        slideOverrides: [String],
        notesOverrides: [String],
        chartOverrides: [String],
        hasXLSX: Bool,
        hasJPEG: Bool,
        hasPNG: Bool
    ) -> String {
        var defaults: [String] = [
            "<Default Extension=\"rels\" ContentType=\"application/vnd.openxmlformats-package.relationships+xml\"/>",
            "<Default Extension=\"xml\" ContentType=\"application/xml\"/>"
        ]
        if hasXLSX {
            defaults.append("<Default Extension=\"xlsx\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.sheet\"/>")
        }
        if hasJPEG {
            defaults.append("<Default Extension=\"jpg\" ContentType=\"image/jpeg\"/>")
        }
        if hasPNG {
            defaults.append("<Default Extension=\"png\" ContentType=\"image/png\"/>")
        }

        let staticOverrides = [
            "<Override PartName=\"/ppt/presentation.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.presentationml.presentation.main+xml\"/>",
            "<Override PartName=\"/ppt/presProps.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.presentationml.presProps+xml\"/>",
            "<Override PartName=\"/ppt/viewProps.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.presentationml.viewProps+xml\"/>",
            "<Override PartName=\"/ppt/tableStyles.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.presentationml.tableStyles+xml\"/>",
            "<Override PartName=\"/ppt/theme/theme1.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.theme+xml\"/>",
            "<Override PartName=\"/ppt/slideMasters/slideMaster1.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.presentationml.slideMaster+xml\"/>",
            "<Override PartName=\"/ppt/slideLayouts/slideLayout1.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.presentationml.slideLayout+xml\"/>",
            "<Override PartName=\"/ppt/notesMasters/notesMaster1.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.presentationml.notesMaster+xml\"/>",
            "<Override PartName=\"/docProps/core.xml\" ContentType=\"application/vnd.openxmlformats-package.core-properties+xml\"/>",
            "<Override PartName=\"/docProps/app.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.extended-properties+xml\"/>"
        ]

        return xmlHeader + """
        <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
          \((defaults + staticOverrides + slideOverrides + notesOverrides + chartOverrides).joined(separator: "\n  "))
        </Types>
        """
    }

    private static func buildPresentationXML(slideIdList: [String]) -> String {
        xmlHeader + """
        <p:presentation xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main" saveSubsetFonts="1">
          <p:sldMasterIdLst><p:sldMasterId id="2147483648" r:id="rId1"/></p:sldMasterIdLst>
          <p:notesMasterIdLst><p:notesMasterId r:id="rId6"/></p:notesMasterIdLst>
          <p:sldIdLst>
            \(slideIdList.joined(separator: "\n    "))
          </p:sldIdLst>
          <p:sldSz cx="\(slideWidthEMU)" cy="\(slideHeightEMU)"/>
          <p:notesSz cx="6858000" cy="9144000"/>
        </p:presentation>
        """
    }

    private static func buildCorePropsXML(deck: WuMindPPTDeck) -> String {
        let iso = ISO8601DateFormatter().string(from: deck.createdAt)
        return xmlHeader + """
        <cp:coreProperties xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties" xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:dcterms="http://purl.org/dc/terms/" xmlns:dcmitype="http://purl.org/dc/dcmitype/" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
          <dc:title>\(escapeXML(deck.title))</dc:title>
          <dc:subject>\(escapeXML(deck.subtitle))</dc:subject>
          <dc:creator>WUMIND PPT Studio</dc:creator>
          <dcterms:created xsi:type="dcterms:W3CDTF">\(iso)</dcterms:created>
          <dcterms:modified xsi:type="dcterms:W3CDTF">\(iso)</dcterms:modified>
        </cp:coreProperties>
        """
    }

    private static func buildAppPropsXML(slideCount: Int, deck: WuMindPPTDeck) -> String {
        xmlHeader + """
        <Properties xmlns="http://schemas.openxmlformats.org/officeDocument/2006/extended-properties" xmlns:vt="http://schemas.openxmlformats.org/officeDocument/2006/docPropsVTypes">
          <Application>WUMIND AI PPT Studio</Application>
          <PresentationFormat>Widescreen</PresentationFormat>
          <Slides>\(slideCount)</Slides>
          <Notes>\(slideCount)</Notes>
          <HiddenSlides>0</HiddenSlides>
          <Company>WUMIND</Company>
        </Properties>
        """
    }

    private static let presPropsXML = xmlHeader + """
    <p:presentationPr xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main"/>
    """

    private static let viewPropsXML = xmlHeader + """
    <p:viewPr xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main">
      <p:normalViewPr><p:restoredLeft sz="15620"/><p:restoredTop sz="94660"/></p:normalViewPr>
      <p:slideViewPr><p:cSldViewPr><p:cViewPr><p:scale><a:sx n="100" d="100"/><a:sy n="100" d="100"/></p:scale><p:origin x="0" y="0"/></p:cViewPr></p:cSldViewPr></p:slideViewPr>
    </p:viewPr>
    """

    private static let tableStylesXML = xmlHeader + """
    <a:tblStyleLst xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" def="{5C22544A-7EE6-4342-B048-85BDC9FD1C3A}"/>
    """

    private static func buildThemeXML(colors: ThemeColors) -> String {
        xmlHeader + """
        <a:theme xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" name="WUMIND Theme">
          <a:themeElements>
            <a:clrScheme name="WUMIND">
              <a:dk1><a:srgbClr val="111827"/></a:dk1>
              <a:lt1><a:srgbClr val="FFFFFF"/></a:lt1>
              <a:dk2><a:srgbClr val="1F2937"/></a:dk2>
              <a:lt2><a:srgbClr val="F3F4F6"/></a:lt2>
              <a:accent1><a:srgbClr val="\(colors.accentHex)"/></a:accent1>
              <a:accent2><a:srgbClr val="\(colors.accent2Hex)"/></a:accent2>
              <a:accent3><a:srgbClr val="\(colors.accent3Hex)"/></a:accent3>
              <a:accent4><a:srgbClr val="\(colors.accent4Hex)"/></a:accent4>
              <a:accent5><a:srgbClr val="8B5CF6"/></a:accent5>
              <a:accent6><a:srgbClr val="EC4899"/></a:accent6>
              <a:hlink><a:srgbClr val="38BDF8"/></a:hlink>
              <a:folHlink><a:srgbClr val="818CF8"/></a:folHlink>
            </a:clrScheme>
            <a:fontScheme name="WUMIND Fonts">
              <a:majorFont><a:latin typeface="Calibri"/><a:ea typeface="PingFang SC"/><a:cs typeface=""/></a:majorFont>
              <a:minorFont><a:latin typeface="Calibri"/><a:ea typeface="PingFang SC"/><a:cs typeface=""/></a:minorFont>
            </a:fontScheme>
            <a:fmtScheme name="WUMIND Format">
              <a:fillStyleLst>
                <a:solidFill><a:schemeClr val="phClr"/></a:solidFill>
                <a:solidFill><a:schemeClr val="phClr"/></a:solidFill>
                <a:solidFill><a:schemeClr val="phClr"/></a:solidFill>
              </a:fillStyleLst>
              <a:lnStyleLst>
                <a:ln w="9525"><a:solidFill><a:schemeClr val="phClr"/></a:solidFill></a:ln>
                <a:ln w="19050"><a:solidFill><a:schemeClr val="phClr"/></a:solidFill></a:ln>
                <a:ln w="28575"><a:solidFill><a:schemeClr val="phClr"/></a:solidFill></a:ln>
              </a:lnStyleLst>
              <a:effectStyleLst>
                <a:effectStyle><a:effectLst/></a:effectStyle>
                <a:effectStyle><a:effectLst/></a:effectStyle>
                <a:effectStyle><a:effectLst/></a:effectStyle>
              </a:effectStyleLst>
              <a:bgFillStyleLst>
                <a:solidFill><a:schemeClr val="phClr"/></a:solidFill>
                <a:solidFill><a:schemeClr val="phClr"/></a:solidFill>
                <a:solidFill><a:schemeClr val="phClr"/></a:solidFill>
              </a:bgFillStyleLst>
            </a:fmtScheme>
          </a:themeElements>
          <a:objectDefaults/>
          <a:extraClrSchemeLst/>
        </a:theme>
        """
    }

    private static func buildSlideMasterXML(colors: ThemeColors) -> String {
        xmlHeader + """
        <p:sldMaster xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main">
          <p:cSld>
            <p:bg><p:bgPr><a:solidFill><a:srgbClr val="\(colors.bgHex)"/></a:solidFill><a:effectLst/></p:bgPr></p:bg>
            <p:spTree>
              <p:nvGrpSpPr><p:cNvPr id="1" name=""/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr>
              <p:grpSpPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="0" cy="0"/><a:chOff x="0" y="0"/><a:chExt cx="0" cy="0"/></a:xfrm></p:grpSpPr>
            </p:spTree>
          </p:cSld>
          <p:clrMap bg1="lt1" tx1="dk1" bg2="lt2" tx2="dk2" accent1="accent1" accent2="accent2" accent3="accent3" accent4="accent4" accent5="accent5" accent6="accent6" hlink="hlink" folHlink="folHlink"/>
          <p:sldLayoutIdLst><p:sldLayoutId id="2147483649" r:id="rId1"/></p:sldLayoutIdLst>
          <p:txStyles>
            <p:titleStyle><a:lvl1pPr><a:defRPr sz="3200" b="1"/></a:lvl1pPr></p:titleStyle>
            <p:bodyStyle><a:lvl1pPr><a:defRPr sz="1800"/></a:lvl1pPr></p:bodyStyle>
            <p:otherStyle><a:lvl1pPr><a:defRPr sz="1400"/></a:lvl1pPr></p:otherStyle>
          </p:txStyles>
        </p:sldMaster>
        """
    }

    private static let slideLayoutXML = xmlHeader + """
    <p:sldLayout xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main" type="blank" preserve="1">
      <p:cSld name="Blank">
        <p:spTree>
          <p:nvGrpSpPr><p:cNvPr id="1" name=""/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr>
          <p:grpSpPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="0" cy="0"/><a:chOff x="0" y="0"/><a:chExt cx="0" cy="0"/></a:xfrm></p:grpSpPr>
        </p:spTree>
      </p:cSld>
      <p:clrMapOvr><a:masterClrMapping/></p:clrMapOvr>
    </p:sldLayout>
    """

    private static let notesMasterXML = xmlHeader + """
    <p:notesMaster xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main">
      <p:cSld>
        <p:spTree>
          <p:nvGrpSpPr><p:cNvPr id="1" name=""/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr>
          <p:grpSpPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="0" cy="0"/><a:chOff x="0" y="0"/><a:chExt cx="0" cy="0"/></a:xfrm></p:grpSpPr>
        </p:spTree>
      </p:cSld>
      <p:clrMap bg1="lt1" tx1="dk1" bg2="lt2" tx2="dk2" accent1="accent1" accent2="accent2" accent3="accent3" accent4="accent4" accent5="accent5" accent6="accent6" hlink="hlink" folHlink="folHlink"/>
    </p:notesMaster>
    """

    // MARK: - Helpers

    private static func themeColors(for theme: WuMindPPTTheme) -> ThemeColors {
        switch theme {
        case .midnightTech:
            return ThemeColors(
                bgHex: "0D1224", bgEndHex: "1B1F40", cardHex: "161D36", cardBorderHex: "2C3861",
                textHex: "F8FAFC", subTextHex: "94A3B8", accentHex: "38BDF8", accent2Hex: "818CF8",
                accent3Hex: "34D399", accent4Hex: "F59E0B",
                tableHeaderHex: "1E3A5F", tableHeaderTextHex: "FFFFFF", tableRowAltHex: "1D2644",
                tableBorderHex: "334155", chartBgHex: "131A30", chartGridHex: "2D3B5E"
            )
        case .executiveBlue:
            return ThemeColors(
                bgHex: "0F234A", bgEndHex: "1A3B75", cardHex: "152E5E", cardBorderHex: "2E5291",
                textHex: "FFFFFF", subTextHex: "CBD5E1", accentHex: "FBBF24", accent2Hex: "60A5FA",
                accent3Hex: "34D399", accent4Hex: "FB7185",
                tableHeaderHex: "1D4ED8", tableHeaderTextHex: "FFFFFF", tableRowAltHex: "1B376D",
                tableBorderHex: "3B62A8", chartBgHex: "132A54", chartGridHex: "335694"
            )
        case .minimalIvory:
            return ThemeColors(
                bgHex: "FBFBF8", bgEndHex: "EFF2F7", cardHex: "FFFFFF", cardBorderHex: "DCE3EE",
                textHex: "181E2E", subTextHex: "5B6478", accentHex: "425CE0", accent2Hex: "0EA5E9",
                accent3Hex: "10B981", accent4Hex: "F59E0B",
                tableHeaderHex: "425CE0", tableHeaderTextHex: "FFFFFF", tableRowAltHex: "F4F6FB",
                tableBorderHex: "CBD5E1", chartBgHex: "FFFFFF", chartGridHex: "E2E8F0"
            )
        case .easternInk:
            return ThemeColors(
                bgHex: "142121", bgEndHex: "223833", cardHex: "1B2D2B", cardBorderHex: "33524D",
                textHex: "F5F2E8", subTextHex: "B8C7BE", accentHex: "66D1AD", accent2Hex: "EAB308",
                accent3Hex: "38BDF8", accent4Hex: "FB923C",
                tableHeaderHex: "245249", tableHeaderTextHex: "FFFFFF", tableRowAltHex: "213633",
                tableBorderHex: "3D615B", chartBgHex: "182826", chartGridHex: "33524D"
            )
        }
    }

    private static func rel(id: String, type: String, target: String) -> String {
        "<Relationship Id=\"\(id)\" Type=\"\(type)\" Target=\"\(target)\"/>"
    }

    private static func relsEnvelope(_ rels: [String]) -> String {
        xmlHeader + """
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
          \(rels.joined(separator: "\n  "))
        </Relationships>
        """
    }

    private static func excelColumnLetter(_ oneBasedIndex: Int) -> String {
        var n = max(1, oneBasedIndex)
        var out = ""
        while n > 0 {
            let rem = (n - 1) % 26
            out = String(UnicodeScalar(65 + rem)!) + out
            n = (n - 1) / 26
        }
        return out
    }

    private static func formatXMLNumber(_ value: Double) -> String {
        guard value.isFinite else { return "0" }
        if value.rounded() == value && abs(value) < 1_000_000_000_000 {
            return String(Int64(value))
        }
        return String(format: "%.4f", value)
            .replacingOccurrences(of: #"0+$"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\.$"#, with: "", options: .regularExpression)
    }

    private static func escapeXML(_ raw: String) -> String {
        let scalars = raw.unicodeScalars.filter { s in
            let n = s.value
            return [9, 10, 13].contains(n) || (32...0xD7FF).contains(n)
                || (0xE000...0xFFFD).contains(n) || (0x10000...0x10FFFF).contains(n)
        }
        return String(String.UnicodeScalarView(scalars))
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }

    // Standard PKZIP writer with UTF-8 flag (0x0800), stored entries, and IEEE 802.3 CRC-32.
    private static func storedZIP(_ files: [(String, Data)]) -> Data {
        var output = Data()
        var directory = Data()
        let utf8Flag: UInt16 = 0x0800
        for (path, contents) in files {
            let name = Data(path.utf8)
            let checksum = crc32(contents)
            let offset = UInt32(output.count)
            let bytes = UInt32(contents.count)
            let length = UInt16(name.count)

            output.pptxLE32(0x0403_4B50)
            output.pptxLE16(20)
            output.pptxLE16(utf8Flag)
            output.pptxLE16(0) // stored
            output.pptxLE16(0)
            output.pptxLE16(33)
            output.pptxLE32(checksum)
            output.pptxLE32(bytes)
            output.pptxLE32(bytes)
            output.pptxLE16(length)
            output.pptxLE16(0)
            output.append(name)
            output.append(contents)

            directory.pptxLE32(0x0201_4B50)
            directory.pptxLE16(20)
            directory.pptxLE16(20)
            directory.pptxLE16(utf8Flag)
            directory.pptxLE16(0)
            directory.pptxLE16(0)
            directory.pptxLE16(33)
            directory.pptxLE32(checksum)
            directory.pptxLE32(bytes)
            directory.pptxLE32(bytes)
            directory.pptxLE16(length)
            directory.pptxLE16(0)
            directory.pptxLE16(0)
            directory.pptxLE16(0)
            directory.pptxLE16(0)
            directory.pptxLE32(0)
            directory.pptxLE32(offset)
            directory.append(name)
        }

        let start = UInt32(output.count)
        let size = UInt32(directory.count)
        let count = UInt16(files.count)
        output.append(directory)
        output.pptxLE32(0x0605_4B50)
        output.pptxLE16(0)
        output.pptxLE16(0)
        output.pptxLE16(count)
        output.pptxLE16(count)
        output.pptxLE32(size)
        output.pptxLE32(start)
        output.pptxLE16(0)
        return output
    }

    private static func crc32(_ data: Data) -> UInt32 {
        var value: UInt32 = 0xFFFF_FFFF
        for byte in data {
            value ^= UInt32(byte)
            for _ in 0..<8 {
                value = (value >> 1) ^ (value & 1 == 1 ? 0xEDB8_8320 : 0)
            }
        }
        return ~value
    }
}

private extension Data {
    mutating func pptxLE16(_ value: UInt16) {
        append(UInt8(truncatingIfNeeded: value))
        append(UInt8(truncatingIfNeeded: value >> 8))
    }

    mutating func pptxLE32(_ value: UInt32) {
        pptxLE16(UInt16(truncatingIfNeeded: value))
        pptxLE16(UInt16(truncatingIfNeeded: value >> 16))
    }
}
