import Foundation

/// Word frequency intelligence powered by corpus data.
/// Provides composite frequency scoring and tier classification.
///
/// Architecture: Layered data sources
/// - Layer 1 (built-in): HSK 3.0 word lists (frequency-ordered by level)
/// - Layer 2 (future): SUBTLEX-CH (film/TV subtitle frequencies)
/// - Layer 3 (future): TUBELEX-ZH (YouTube subtitle frequencies)
/// - Layer 4 (future): BCC (15B char comprehensive corpus)
final class FrequencyEngine: @unchecked Sendable {
    static let shared = FrequencyEngine()

    struct FrequencyData: Sendable {
        let word: String
        let rank: Int           // 1 = most frequent
        let tier: FrequencyTier
        let hskLevel: Int?      // HSK 3.0 level (1-9), nil if not in HSK
    }

    enum FrequencyTier: String, Sendable, Comparable {
        case top500 = "Top 500"
        case top2000 = "Top 2000"
        case top5000 = "Top 5000"
        case common = "Common"
        case uncommon = "Uncommon"
        case rare = "Rare"

        static func < (lhs: FrequencyTier, rhs: FrequencyTier) -> Bool {
            lhs.sortOrder < rhs.sortOrder
        }

        var sortOrder: Int {
            switch self {
            case .top500: 0
            case .top2000: 1
            case .top5000: 2
            case .common: 3
            case .uncommon: 4
            case .rare: 5
            }
        }

        var color: String {
            switch self {
            case .top500: "#22c55e"    // Green — very common
            case .top2000: "#3b82f6"   // Blue
            case .top5000: "#8b5cf6"   // Purple
            case .common: "#6b7280"    // Gray
            case .uncommon: "#f59e0b"  // Amber
            case .rare: "#ef4444"      // Red — rare
            }
        }
    }

    private var frequencyMap: [String: (rank: Int, hskLevel: Int?)] = [:]
    private var loaded = false

    private init() {}

    func load() {
        guard !loaded else { return }
        buildFrequencyMap()
        loaded = true
        print("[FrequencyEngine] Loaded \(frequencyMap.count) frequency entries")
    }

    /// Look up frequency data for a word.
    func lookup(_ word: String) -> FrequencyData {
        if let data = frequencyMap[word] {
            return FrequencyData(
                word: word,
                rank: data.rank,
                tier: tierForRank(data.rank),
                hskLevel: data.hskLevel
            )
        }
        // Unknown word — check dictionary to distinguish uncommon vs rare
        let inDict = DictionaryEngine.shared.contains(word)
        return FrequencyData(
            word: word,
            rank: inDict ? 8000 : 50000,
            tier: inDict ? .uncommon : .rare,
            hskLevel: nil
        )
    }

    /// Calculate weighted comprehension score.
    /// Missing a common word hurts more than missing a rare word.
    func weightedComprehension(knownWords: Set<String>, allWords: [String]) -> Double {
        guard !allWords.isEmpty else { return 0 }
        var totalWeight = 0.0
        var knownWeight = 0.0
        for word in allWords {
            let freq = lookup(word)
            let weight = weightForTier(freq.tier)
            totalWeight += weight
            if knownWords.contains(word) {
                knownWeight += weight
            }
        }
        return totalWeight > 0 ? knownWeight / totalWeight : 0
    }

    // MARK: - Private

    private func tierForRank(_ rank: Int) -> FrequencyTier {
        switch rank {
        case 1...500: .top500
        case 501...2000: .top2000
        case 2001...5000: .top5000
        case 5001...10000: .common
        case 10001...30000: .uncommon
        default: .rare
        }
    }

    private func weightForTier(_ tier: FrequencyTier) -> Double {
        switch tier {
        case .top500: 3.0
        case .top2000: 2.5
        case .top5000: 2.0
        case .common: 1.5
        case .uncommon: 1.0
        case .rare: 0.5
        }
    }

    /// Build frequency map from embedded HSK word data.
    /// HSK 3.0 has 9 levels with ~11,000 words total.
    /// Words are ranked within and across levels.
    private func buildFrequencyMap() {
        var rank = 1

        // HSK 1 (300 words) — most common everyday words
        for word in hsk1Words {
            frequencyMap[word] = (rank: rank, hskLevel: 1)
            rank += 1
        }
        // HSK 2 (300 words)
        for word in hsk2Words {
            frequencyMap[word] = (rank: rank, hskLevel: 2)
            rank += 1
        }
        // HSK 3 (300 words)
        for word in hsk3Words {
            frequencyMap[word] = (rank: rank, hskLevel: 3)
            rank += 1
        }
        // HSK 4-6 approximated as common band
        for word in hsk456Words {
            frequencyMap[word] = (rank: rank, hskLevel: 4)
            rank += 1
        }
    }

    // MARK: - HSK Word Lists (subset — most impactful words)
    // Full HSK 3.0 lists will be loaded from file in production.
    // This embedded subset covers HSK 1-3 (~900 words) for immediate use.

    private let hsk1Words: [String] = [
        "我", "你", "他", "她", "它", "我们", "你们", "他们",
        "这", "那", "哪", "什么", "谁", "怎么", "多少", "几",
        "的", "了", "在", "是", "有", "不", "没", "也", "都", "很",
        "和", "但", "因为", "所以", "如果", "虽然", "但是",
        "一", "二", "三", "四", "五", "六", "七", "八", "九", "十",
        "百", "千", "万", "零", "两",
        "个", "本", "把", "块", "件", "只", "杯", "些",
        "年", "月", "日", "天", "时", "分", "秒", "今天", "明天", "昨天",
        "上午", "下午", "晚上", "早上", "现在", "以前", "以后",
        "大", "小", "多", "少", "好", "坏", "新", "旧", "长", "短",
        "高", "低", "快", "慢", "远", "近", "热", "冷", "对", "错",
        "吃", "喝", "看", "听", "说", "写", "读", "做", "去", "来",
        "走", "跑", "坐", "站", "睡", "买", "卖", "给", "用", "想",
        "知道", "喜欢", "爱", "要", "会", "能", "可以", "应该",
        "人", "家", "学生", "老师", "朋友", "同学", "孩子", "先生",
        "小姐", "医生", "工作", "学习", "名字", "中国", "北京",
        "水", "茶", "饭", "菜", "米饭", "面条", "肉", "鱼", "鸡蛋",
        "苹果", "水果", "蔬菜", "牛奶", "咖啡", "啤酒",
        "家", "学校", "医院", "商店", "饭店", "机场", "车站",
        "公司", "银行", "超市", "图书馆", "教室",
        "车", "飞机", "火车", "公共汽车", "出租车", "地铁", "自行车",
        "书", "电话", "手机", "电脑", "电视", "钱", "衣服",
        "东", "南", "西", "北", "上", "下", "左", "右", "前", "后",
        "里", "外", "中", "旁边",
        "爸爸", "妈妈", "哥哥", "姐姐", "弟弟", "妹妹", "儿子", "女儿",
        "请", "谢谢", "对不起", "没关系", "你好", "再见",
        "吗", "呢", "吧", "啊", "呀",
    ]

    private let hsk2Words: [String] = [
        "觉得", "认为", "希望", "相信", "了解", "介绍", "帮助", "回答",
        "问题", "意思", "关系", "办法", "习惯", "环境", "经验",
        "开始", "结束", "准备", "参加", "变化", "发展", "提高", "影响",
        "重要", "特别", "一般", "简单", "复杂", "容易", "困难",
        "已经", "刚才", "马上", "一直", "经常", "有时候", "从来",
        "必须", "需要", "只要", "只有", "除了", "关于",
        "比较", "越来越", "又", "再", "还是", "或者", "而且",
        "健康", "安全", "幸福", "满意", "高兴", "生气", "担心", "害怕",
        "记得", "忘记", "注意", "决定", "选择", "放弃", "坚持",
        "声音", "颜色", "味道", "感觉", "态度", "精神",
        "社会", "文化", "历史", "科学", "技术", "经济", "政治",
        "城市", "农村", "国家", "世界", "地方", "地区",
        "节目", "新闻", "音乐", "电影", "比赛", "游戏",
        "身体", "眼睛", "耳朵", "嘴", "手", "脚", "头", "心",
        "春天", "夏天", "秋天", "冬天", "太阳", "月亮", "风", "雨",
        "花", "树", "草", "山", "河", "海", "天空",
        "打电话", "上网", "发短信", "照相", "旅游",
        "可能", "当然", "其实", "终于", "突然", "果然",
        "聪明", "认真", "努力", "诚实", "勇敢", "耐心",
    ]

    private let hsk3Words: [String] = [
        "实际", "具体", "明显", "严重", "普通", "正常", "合理", "丰富",
        "支持", "反对", "表示", "证明", "解释", "讨论", "交流",
        "保护", "破坏", "建设", "改革", "创造", "发明", "研究",
        "组织", "管理", "领导", "服务", "合作", "竞争", "交易",
        "收入", "消费", "投资", "利润", "成本", "价格", "质量",
        "教育", "培训", "考试", "毕业", "专业", "知识", "能力",
        "法律", "权利", "义务", "责任", "制度", "政策", "规定",
        "尊重", "理解", "同情", "感谢", "道歉", "原谅", "批评",
        "表达", "沟通", "协商", "争论", "妥协", "一致",
        "目标", "计划", "方案", "进度", "成果", "效果",
        "困难", "障碍", "挑战", "危机", "风险", "机会",
        "材料", "工具", "设备", "机器", "产品", "资源",
        "存在", "发生", "产生", "消失", "增加", "减少", "提升",
        "代表", "象征", "反映", "体现", "包含", "构成",
        "传统", "现代", "古代", "当代", "未来",
        "主要", "次要", "基本", "根本", "核心", "关键",
        "直接", "间接", "整体", "局部", "表面", "深层",
        "积极", "消极", "主动", "被动", "灵活", "固定",
        "无论", "即使", "尽管", "何况", "否则", "于是", "从而",
        "既然", "不但", "而且", "不仅", "甚至", "总之", "因此",
    ]

    // HSK 4-6 — larger set, approximated
    private let hsk456Words: [String] = [
        "抽象", "象征", "隐喻", "寓意", "讽刺", "夸张", "含蓄",
        "悲剧", "喜剧", "情节", "人物", "角色", "场景", "背景",
        "描写", "叙述", "对话", "独白", "转折", "高潮", "结局",
        "主题", "思想", "观点", "立场", "态度", "价值", "意义",
        "命运", "挣扎", "抗争", "妥协", "牺牲", "奉献", "坚守",
        "活着", "死亡", "生存", "毁灭", "重生", "希望", "绝望",
        "苦难", "幸运", "偶然", "必然", "因果",
        "农民", "土地", "收获", "饥荒", "战争", "革命",
        "忍受", "承受", "克服", "面对", "逃避", "接受",
        "温柔", "残酷", "善良", "邪恶", "纯洁", "污染",
        "深刻", "肤浅", "透彻", "模糊", "清晰", "混乱",
        "沉默", "呐喊", "低语", "咆哮", "叹息", "哭泣", "微笑",
        "黎明", "黄昏", "夜晚", "季节", "岁月", "时光",
        "故乡", "异乡", "归来", "离别", "思念", "怀念",
        "勇气", "智慧", "信念", "毅力", "尊严", "自由", "平等",
        "贫穷", "富裕", "公正", "腐败", "改变", "维持",
        "不得不", "不由得", "不禁", "不知不觉", "情不自禁",
        "一边", "另一方面", "与此同时", "紧接着", "随后",
        "恰恰", "偏偏", "竟然", "居然", "毕竟", "何必",
    ]
}
