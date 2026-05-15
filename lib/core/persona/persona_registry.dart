/// 内建思维透镜注册表 — 从 nuwa-skill 蒸馏的思维模型
///
/// 混合检测策略：
/// 1. 关键词打分（coreHints ×3, triggerHints ×1, antiHints ×-2）
/// 2. 若 top1 分 > top2 分 ×2 → 直接使用（快速通道，80%命中）
/// 3. 否则 → 交由 LLM 从候选中判决（精准通道）
library;

/// 透镜匹配置信度
enum LensConfidence {
  direct,  // 关键词碾压，直接选用
  llm,     // 需 LLM 判决
  none,    // 未匹配
}

class ScoredPersona {

  const ScoredPersona({
    required this.persona,
    required this.score,
    required this.confidence,
  });
  final Persona persona;
  final int score;
  final LensConfidence confidence;
}

class PersonaRegistry {
  static const List<Persona> all = [
    product, decision, learning, life, risk, startup, org, tech,
  ];

  // ─── 产品直觉 ───
  static const product = Persona(
    id: 'product',
    lensLabel: '产品直觉',
    coreHints: ['设计', 'UX', 'UI', '交互', '体验'],
    triggerHints: [
      '产品', '界面', '简约', '优雅', '砍功能', '做减法', '好用', '难用', '不好看',
      'product', 'design', 'simplicity', 'elegance',
    ],
    antiHints: [
      '多少钱', '价格', '价格', '购买', '下单', '支付', '优惠', '折扣',
      '我的简历', '面试', '怎么写', '语法',
    ],
    mentalModels: [
      'Focus = 说不：专注不是选择做什么，而是对一百个好想法说不',
      '完整产品观：认真做软件的人应该自己做硬件，掌控体验全链路',
      '科技 x 人文：科技本身不够，必须与人文结合才能打动人心',
    ],
    heuristics: [
      '先做减法：面对任何产品决策，先问"能砍掉什么"',
      '不问用户要什么：用户不知道自己要什么，直到你给他们看',
      '一句话定义：如果你不能用一句话描述一个产品，产品就有问题',
    ],
  );

  // ─── 决策与投资 ───
  static const decision = Persona(
    id: 'decision',
    lensLabel: '决策与投资',
    coreHints: ['投资', '决策', '取舍', '风险'],
    triggerHints: [
      '选择', '机会', '收益', '利弊', '犯错', '误判', '亏损', '股票', '基金', '资产',
      'invest', 'decision', 'risk', 'choice', 'opportunity', 'return',
    ],
    antiHints: [
      '今天吃什么', '周末去哪', '天气', '帮我写', '翻译',
    ],
    mentalModels: [
      '多元思维模型网格：从多个学科提取核心模型编织决策框架，单学科思维必有盲区',
      '逆向思维：不知道如何成功时，研究如何保证失败，然后避开那些路径',
      '激励决定一切：告诉我激励结构，我告诉你结果；不要听人们说什么，看他们被奖励什么',
    ],
    heuristics: [
      '三筐分类法：每个决策分到 Yes/No/Too Hard 三个筐，大部分属于 Too Hard',
      '激励诊断：分析任何行为前，先画激励结构图——谁获益、谁担风险',
      '愚蠢清单：收集该领域所有已知的愚蠢错误，系统性地避开它们',
    ],
  );

  // ─── 学习与理解 ───
  static const learning = Persona(
    id: 'learning',
    lensLabel: '学习与理解',
    coreHints: ['学习', '理解', '原理', '为什么'],
    triggerHints: [
      '解释', '教学', '怎么学', '教我', '搞懂', '不明白', '概念', '基础',
      'learn', 'understand', 'explain', 'teach', 'principle', 'why', 'how to learn',
    ],
    antiHints: [
      '产品设计', '投资回报', '团队管理', '融资',
    ],
    mentalModels: [
      '命名 ≠ 理解：知道一个东西叫什么和真正理解它如何工作是两回事',
      '不确定性是力量："我不知道"不是终点，而是探索的起点',
      '具体可视化：把不可见的东西变可见，用具体可感知的类比代替抽象概念',
    ],
    heuristics: [
      '货物崇拜检测：如果一个实践有所有外在形式但缺乏内在精神，飞机不会降落',
      '演示 > 论证：10 秒的演示胜过 100 页的论证',
      '从具体到一般：永远从一个具体例子开始，再推导出一般原则',
    ],
  );

  // ─── 人生与财富 ───
  static const life = Persona(
    id: 'life',
    lensLabel: '人生与财富',
    coreHints: ['财富', '自由', '职业', '幸福', '焦虑'],
    triggerHints: [
      '人生', '杠杆', '离职', '打工', '工作', '赚钱', '意义', '创业',
      'wealth', 'freedom', 'career', 'life', 'happiness', 'anxiety', 'leverage',
    ],
    antiHints: [
      '投资策略', '股票代码', '怎么写', '怎么学',
    ],
    mentalModels: [
      '杠杆：不要用时间换钱，用可复制的系统——劳动、资本、代码（无需许可）、媒体（无需许可）',
      '特定知识：你最大的竞争优势是那些对你来说像玩、对别人来说像工作的事',
      '欲望 = 不快乐契约：每一个欲望都是一份"得不到就不快乐"的合同',
    ],
    heuristics: [
      '纠结即否定：如果你犹豫不决，答案就是不；真正好的机会不会让你犹豫',
      '欲望审计：焦虑时审计你的欲望——"这个欲望真的是我的，还是被社会植入的？"',
      '日历测试：如果你的日历被别人填满，你还没有真正的自由',
    ],
  );

  // ─── 风险与不确定性 ───
  static const risk = Persona(
    id: 'risk',
    lensLabel: '风险与不确定性',
    coreHints: ['黑天鹅', '脆弱', '反脆弱', '尾部风险', '波动'],
    triggerHints: [
      '风险', '不确定性', '稳健', '危机', '最坏情况', '万一', '概率',
      'risk', 'uncertainty', 'black swan', 'fragile', 'robust', 'volatility', 'crisis',
    ],
    antiHints: [
      '今天吃什么', '帮我写', '翻译一下',
    ],
    mentalModels: [
      '非对称风险思维：永远先评估下行成本，而非期望值；灭绝风险不论概率多小都不可接受',
      '反脆弱偏好：不要抵抗混沌，从中获益——脆弱（被波动伤害）、稳健（不受影响）、反脆弱（从波动中获益）',
      'Lindy 效应过滤器：非易朽品存在越久，预期存续时间越长；时间是终极质量过滤器',
    ],
    heuristics: [
      '杠铃策略：90% 极度保守 + 10% 极度激进；中间地带最危险',
      '遍历性检验：如果一个策略重复一万次哪怕只导致一次毁灭，也避开它——你只有一条命',
      '框架重置：不回答坏问题，挑战问题本身的前提',
    ],
  );

  // ─── 创业与创造 ───
  static const startup = Persona(
    id: 'startup',
    lensLabel: '创业与创造',
    coreHints: ['创业', '融资', 'MVP', '创始人', '产品市场契合'],
    triggerHints: [
      '用户', '增长', '项目', '想法', '创意', '验证', '种子轮', '天使', 'pivot',
      'startup', 'founder', 'growth', 'funding', 'raise', 'seed', 'invest',
    ],
    antiHints: [
      '股价', '基金定投', '学习效率', '怎么学',
    ],
    mentalModels: [
      '写作 = 思考：写作不是在传达已有想法，而是在生成想法；写不清楚就是没想清楚',
      '品味是认知工具：品味是可训练的判断力，不是主观偏好；在信息不完整时做更好的决策',
      '迭代式发现：好东西不是提前设计出来的，是做出来的，然后识别出那个有效的模式',
    ],
    heuristics: [
      '做人们想要的东西：不是你觉得酷的或投资人想投的',
      '做不规模化的事：早期拥抱手工、劳动密集型的方法启动飞轮',
      'Default Alive 还是 Default Dead：永远知道四个数字——当前支出、营收、增长率、现金',
    ],
  );

  // ─── 组织与增长 ───
  static const org = Persona(
    id: 'org',
    lensLabel: '组织与增长',
    coreHints: ['团队', '组织', '管理', '招聘', '竞争'],
    triggerHints: [
      '增长', '扩张', '效率', '信息', '人才', '文化', '制度', '延迟满足',
      'team', 'organization', 'management', 'growth', 'competition', 'scale',
    ],
    antiHints: [
      '个人成长', '自学', '怎么写代码', '投资',
    ],
    mentalModels: [
      '延迟满足是认知边界：你能延迟满足的深度决定了你的认知层次',
      '投影到高维：所有复杂问题都是高维简单问题的投影，不要在表面优化，挖到根',
      'Context not Control：组织变大时信息自然失真；解法是传递上下文（让所有人看到全貌），而非收紧控制',
    ],
    heuristics: [
      '先小验证再押大注：内涵段子 → 头条 → 抖音 → TikTok',
      '以十年为期：短期声誉损失不值得在意',
      '觉得好的事再往后延迟一下：提高标准，创造缓冲',
    ],
  );

  // ─── AI 与技术 ───
  static const tech = Persona(
    id: 'tech',
    lensLabel: 'AI 与技术',
    coreHints: ['AI', 'LLM', '模型', '神经网络', '深度学习'],
    triggerHints: [
      '人工智能', '机器学习', '训练', '幻觉', '大模型', '推理', 'transformer',
      'AI', 'machine learning', 'deep learning', 'neural', 'model', 'tech',
    ],
    antiHints: [
      '产品设计', 'UI优化', '怎么写产品需求',
    ],
    mentalModels: [
      '软件 X.0：编程只发生过两次根本性变革，我们正处于第三次——1.0(显式代码)→2.0(神经网络权重=代码)→3.0(英语即编程语言)',
      'LLM = 召唤的幽灵：LLM 是从互联网数据中召唤的人类思维随机模拟；幻觉不是 bug 而是本质',
      'Jagged Intelligence：LLM 能力分布是锯齿状的——某些维度超人类，某些维度犯人类不会犯的错误',
    ],
    heuristics: [
      '从零构建验证：我能在 200 行代码内重建核心吗？不能就是没真懂',
      'imo 标记主张：用"个人认为"标记主观判断，清楚分开已验证和推断',
      '先看数据再训练：第一步永远不是碰模型代码，而是仔细检查数据集',
    ],
  );

  // ── 检测 ──

  /// 混合检测：关键词初筛，高置信度直接返回，模糊交由 LLM 判决。
  ///
  /// 返回 [ScoredPersona] 列表。
  /// - [LensConfidence.direct] — top1 分 > top2 分 ×2，可直接用
  /// - [LensConfidence.llm] — 分差小或有歧义，需 LLM 从候选里选
  /// - [LensConfidence.none] — 未匹配任何透镜
  static List<ScoredPersona> detectHybrid(String input) {
    final lower = input.toLowerCase();

    // 1. 关键词打分
    final scores = <Persona, int>{};
    for (final p in all) {
      int antiPenalty = 0;
      for (final a in p.antiHints) {
        if (lower.contains(a.toLowerCase())) antiPenalty += 2;
      }
      if (antiPenalty >= 4) continue; // 强排除：≥2 个 antiHints 命中则跳过此透镜

      int score = 0;
      for (final c in p.coreHints) {
        if (lower.contains(c.toLowerCase())) score += 3;
      }
      for (final t in p.triggerHints) {
        if (lower.contains(t.toLowerCase())) score++;
      }
      score -= antiPenalty;
      if (score > 0) scores[p] = score;
    }

    if (scores.isEmpty) return const [];

    final sorted = scores.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final top1 = sorted.first.value;
    final hasSecond = sorted.length > 1;
    final top2 = hasSecond ? sorted[1].value : 0;

    // 2. 判定置信度
    final List<ScoredPersona> result;
    if (top1 >= 3 && (top1 > top2 * 2 || !hasSecond)) {
      // 快速通道：top1 高分段且碾压第二名
      result = [
        ScoredPersona(
            persona: sorted.first.key,
            score: top1,
            confidence: LensConfidence.direct),
      ];
      if (hasSecond) {
        result.add(ScoredPersona(
            persona: sorted[1].key,
            score: top2,
            confidence: LensConfidence.direct));
      }
    } else if (top1 > 0) {
      // 模糊：分数接近，或分数低但无更好的 → 返回所有候选，等 LLM 判
      result = sorted
          .take(3)
          .map((e) => ScoredPersona(
              persona: e.key, score: e.value, confidence: LensConfidence.llm))
          .toList();
    } else {
      result = const [];
    }

    return result;
  }

  /// 旧 API：直接按关键词返回 top 2（向后兼容）
  static List<Persona> detect(String input) {
    final hybrid = detectHybrid(input);
    if (hybrid.isEmpty) return const [];
    return hybrid.take(2).map((s) => s.persona).toList();
  }

  /// 构建注入系统提示词的透镜段落。
  /// 最多取前 2 个 persona，共 12 条内容。
  static String buildLensPrompt(List<Persona> personas) {
    if (personas.isEmpty) return '';
    final buf = StringBuffer();
    buf.writeln('\n参考以下视角分析问题：');
    int count = 0;
    for (final p in personas.take(2)) {
      for (final m in p.mentalModels) {
        if (count >= 12) break;
        buf.writeln('- $m');
        count++;
      }
      for (final h in p.heuristics) {
        if (count >= 12) break;
        buf.writeln('- $h');
        count++;
      }
    }
    return buf.toString();
  }
}

class Persona {

  const Persona({
    required this.id,
    required this.lensLabel,
    required this.mentalModels, required this.heuristics, this.coreHints = const [],
    this.triggerHints = const [],
    this.antiHints = const [],
  });
  final String id;
  final String lensLabel;
  final List<String> coreHints;     // 权重 ×3，高特异性关键词
  final List<String> triggerHints;  // 权重 ×1，一般关键词
  final List<String> antiHints;     // 排除词，命中扣 2 分
  final List<String> mentalModels;
  final List<String> heuristics;
}
