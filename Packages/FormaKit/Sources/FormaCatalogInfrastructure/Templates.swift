import FormaDomain
import FormaGeometry
import FormaLocalization
import Foundation

public enum DiagramTemplate: String, CaseIterable, Identifiable, Sendable {
    case architecture, flowchart, mindmap, panelBoard, stateChart, orgChart, kanban, swot, umlClass, umlUseCase,
        umlComponent, erDiagram, c4Context, blank
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .architecture: "系统架构"
        case .flowchart: "业务流程"
        case .mindmap: "思维导图"
        case .panelBoard: "多 Panel 工作页"
        case .umlClass: "UML 类图"
        case .umlUseCase: "UML 用例图"
        case .umlComponent: "UML 组件图"
        case .erDiagram: "实体关系图"
        case .c4Context: "C4 系统上下文"
        case .stateChart: "状态图"
        case .orgChart: "组织架构"
        case .kanban: "任务看板"
        case .swot: "SWOT 分析"
        case .blank: "空白画布"
        }
    }
    public var subtitle: String {
        switch self {
        case .architecture: "让系统之间的关系一目了然"
        case .flowchart: "从一个清晰的流程开始"
        case .mindmap: "给每一个想法留出空间"
        case .panelBoard: "在同一页面组织多个独立分区"
        case .umlClass: "类、接口、属性、操作与类型化关系"
        case .umlUseCase: "参与者、系统边界与业务用例"
        case .umlComponent: "划分组件及服务之间的依赖"
        case .erDiagram: "实体、字段与关系基数"
        case .c4Context: "聚焦用户、系统及外部依赖"
        case .stateChart: "从初始到终止的状态流转"
        case .orgChart: "清晰的层级汇报关系"
        case .kanban: "按阶段组织任务卡片"
        case .swot: "四象限梳理优势与风险"
        case .blank: "自由组织你的下一次灵感"
        }
    }
    public var symbol: String {
        switch self {
        case .architecture: "square.stack.3d.up"
        case .flowchart: "arrow.triangle.branch"
        case .mindmap: "point.3.connected.trianglepath.dotted"
        case .panelBoard: "rectangle.split.2x1"
        case .umlClass: "rectangle.split.3x1"
        case .umlUseCase: "figure.stand"
        case .umlComponent: "shippingbox"
        case .erDiagram: "externaldrive"
        case .c4Context: "network"
        case .stateChart: "arrow.triangle.2.circlepath"
        case .orgChart: "building.2"
        case .kanban: "rectangle.split.3x1"
        case .swot: "square.split.2x2"
        case .blank: "plus"
        }
    }
    public var category: String {
        [.umlClass, .umlUseCase, .umlComponent, .erDiagram, .c4Context, .stateChart].contains(self) ? "企业建模" : "基础与规划"
    }
    public func makeDiagram(language: AppLanguage = .simplifiedChinese) -> Diagram {
        var nodes: [DiagramNode] = []
        var edges: [DiagramEdge] = []
        var panels: [DiagramPanel] = []
        func panel(
            _ title: String, _ x: Double, _ y: Double, _ width: Double, _ height: Double, _ color: DiagramColor = .blue
        ) -> UUID {
            let p = DiagramPanel(title: title, frame: Rect(x: x, y: y, width: width, height: height), color: color)
            panels.append(p)
            return p.id
        }
        func node(
            _ title: String, _ x: Double, _ y: Double, _ color: DiagramColor = .blue, _ kind: ShapeKind = .rounded,
            width: Double = 176, height: Double = 76, in panelID: UUID? = nil, attributes: [String]? = nil,
            operations: [String]? = nil, stereotype: String? = nil
        ) -> UUID {
            let n = DiagramNode(
                title: title, kind: kind, frame: Rect(x: x, y: y, width: width, height: height), color: color,
                panelID: panelID, attributes: attributes, operations: operations, stereotype: stereotype)
            nodes.append(n)
            return n.id
        }
        func link(_ a: UUID, _ b: UUID, _ label: String = "", _ relation: UMLRelation? = nil) {
            edges.append(DiagramEdge(source: a, target: b, label: label, relation: relation))
        }
        switch self {
        case .blank: break
        case .architecture:
            _ = node("产品系统架构", 0, -90, .neutral, .text, width: 380, height: 44)
            let client = node("客户端\nWeb · iOS · macOS", 0, 130)
            let gateway = node("API 网关\n认证 · 路由 · 限流", 270, 130, .violet)
            let account = node("用户服务\n身份与权限", 540, 0)
            let order = node("订单服务\n核心业务逻辑", 540, 130, .violet)
            let notify = node("消息服务\n事件与通知", 540, 260, .peach)
            let db = node("数据存储\nPostgreSQL", 810, 65, .mint, .database)
            let queue = node("事件队列\n异步任务", 810, 260, .peach, .component)
            link(client, gateway, "HTTPS")
            link(gateway, account)
            link(gateway, order)
            link(gateway, notify)
            link(account, db)
            link(order, db)
            link(notify, queue)
        case .flowchart:
            let a = node("开始", 240, 0, .mint, .ellipse)
            let b = node("提交申请", 240, 140)
            let c = node("审核通过？", 250, 280, .violet, .diamond, width: 156, height: 108)
            let d = node("执行并通知", 240, 450)
            let e = node("补充材料", 510, 300, .peach)
            let f = node("完成", 240, 600, .mint, .ellipse)
            link(a, b)
            link(b, c)
            link(c, d, "通过")
            link(c, e, "退回")
            link(e, b)
            link(d, f)
        case .mindmap:
            let a = node("下一件好产品", 320, 200, .violet, width: 200, height: 90)
            let b = node("发现需求", 0, 70)
            let c = node("定义体验", 0, 320, .mint)
            let d = node("构建原型", 650, 70, .peach)
            let e = node("验证与迭代", 650, 320, .rose)
            link(a, b)
            link(a, c)
            link(a, d)
            link(a, e)
        case .panelBoard:
            let a = panel("01 · 产品发现", 0, 0, 420, 420)
            let b = panel("02 · 解决方案", 500, 0, 420, 420, .violet)
            let c = panel("03 · 交付与验证", 1000, 0, 420, 420, .mint)
            let n1 = node("用户研究", 122, 90, in: a)
            let n2 = node("明确需求", 122, 260, .mint, in: a)
            let n3 = node("交互与原型", 622, 90, .violet, in: b)
            let n4 = node("技术设计", 622, 260, in: b)
            let n5 = node("开发与验证", 1122, 90, .mint, in: c)
            let n6 = node("发布与复盘", 1122, 260, .peach, in: c)
            link(n1, n2)
            link(n2, n3)
            link(n3, n4)
            link(n4, n5)
            link(n5, n6)
        case .umlClass:
            let p = panel("订单领域 · 类与接口", 0, 0, 1080, 640, .violet)
            let customer = node(
                "Customer", 32, 80, .blue, .umlClass, width: 240, height: 200, in: p,
                attributes: ["- id: UUID", "- name: String"], operations: ["+ placeOrder(): Order"])
            let order = node(
                "Order", 416, 80, .violet, .umlClass, width: 240, height: 200, in: p,
                attributes: ["- id: UUID", "- total: Decimal"], operations: ["+ confirm(): void", "+ cancel(): void"])
            let item = node(
                "OrderItem", 800, 80, .mint, .umlClass, width: 240, height: 200, in: p,
                attributes: ["- quantity: Int", "- price: Decimal"], operations: ["+ subtotal(): Decimal"])
            let payment = node(
                "PaymentGateway", 416, 400, .peach, .umlInterface, width: 240, height: 200, in: p, attributes: [],
                operations: ["+ charge(amount): Bool"])
            let card = node(
                "CardPayment", 800, 400, .rose, .umlClass, width: 240, height: 200, in: p,
                attributes: ["- token: String"], operations: ["+ charge(amount): Bool"])
            link(customer, order, "1 拥有 0..*", .association)
            link(order, item, "1 包含 1..*", .composition)
            link(order, payment, "使用", .dependency)
            link(card, payment, "", .realization)
        case .umlUseCase:
            let p = panel("订单管理系统", 220, 0, 700, 460, .violet)
            let user = node("顾客", 0, 130, .neutral, .umlActor, width: 110, height: 160)
            let admin = node("管理员", 1030, 130, .neutral, .umlActor, width: 110, height: 160)
            let a = node("创建订单", 280, 90, .blue, .umlUseCase, width: 200, height: 90, in: p)
            let b = node("处理支付", 640, 90, .mint, .umlUseCase, width: 200, height: 90, in: p)
            let c = node("查询订单", 280, 300, .violet, .umlUseCase, width: 200, height: 90, in: p)
            let d = node("审核退款", 640, 300, .peach, .umlUseCase, width: 200, height: 90, in: p)
            link(user, a, "", .association)
            link(user, c, "", .association)
            link(a, b, "«include»", .dependency)
            link(admin, d, "", .association)
        case .umlComponent:
            let front = panel("客户端", 0, 0, 320, 380)
            let back = panel("服务端", 420, 0, 640, 380, .violet)
            let a = node("Web Application", 60, 140, .blue, .component, width: 200, in: front)
            let b = node("API Gateway", 460, 140, .violet, .component, width: 200, in: back)
            let c = node("Order Service", 800, 80, .mint, .component, width: 200, in: back)
            let d = node("Event Bus", 800, 240, .peach, .component, width: 200, in: back)
            link(a, b, "REST", .dependency)
            link(b, c, "调用", .dependency)
            link(c, d, "发布事件", .dependency)
        case .erDiagram:
            let a = node(
                "customers", 0, 0, .blue, .umlClass, width: 260, height: 220,
                attributes: ["PK id: UUID", "name: VARCHAR", "email: VARCHAR UNIQUE"], operations: [],
                stereotype: "entity")
            let b = node(
                "orders", 430, 0, .violet, .umlClass, width: 260, height: 220,
                attributes: ["PK id: UUID", "FK customer_id: UUID", "total: DECIMAL"], operations: [],
                stereotype: "entity")
            let c = node(
                "order_items", 860, 0, .mint, .umlClass, width: 260, height: 220,
                attributes: ["PK id: UUID", "FK order_id: UUID", "quantity: INTEGER"], operations: [],
                stereotype: "entity")
            link(a, b, "1 : N", .association)
            link(b, c, "1 : N", .association)
        case .c4Context:
            let p = panel("系统上下文", 200, 0, 680, 520, .violet)
            let actor = node("业务用户", 0, 170, .neutral, .umlActor, width: 110, height: 160)
            let core = node("«Software System»\n订单平台\n管理交易与履约", 400, 100, .violet, width: 280, height: 110, in: p)
            let pay = node("«External System»\n支付服务", 400, 350, .peach, width: 280, height: 90, in: p)
            let mail = node("«External System»\n邮件服务", 1020, 100, .mint, width: 240, height: 100)
            link(actor, core, "使用 HTTPS")
            link(core, pay, "发起扣款")
            link(core, mail, "发送通知")
        case .stateChart:
            _ = node("订单状态机", 0, -90, .neutral, .text, width: 320, height: 44)
            let s0 = node("初始", 20, 120, .mint, .ellipse, width: 72, height: 72)
            let s1 = node("待支付", 180, 120)
            let s2 = node("已支付", 400, 120, .violet)
            let s3 = node("配送中", 620, 120)
            let s4 = node("已完成", 620, 280, .mint)
            let s5 = node("已取消", 300, 300, .peach)
            link(s0, s1, "创建")
            link(s1, s2, "支付成功")
            link(s2, s3, "发货")
            link(s3, s4, "签收")
            link(s1, s5, "超时/取消")
        case .orgChart:
            let ceo = node("首席执行官", 360, 0, .violet, width: 200)
            let cto = node("技术总监", 100, 180, .blue)
            let coo = node("运营总监", 360, 180, .mint)
            let cfo = node("财务总监", 620, 180, .peach)
            let rd = node("研发团队", 100, 360, .blue)
            let cs = node("客服团队", 360, 360, .mint)
            let fn = node("财务团队", 620, 360, .peach)
            link(ceo, cto)
            link(ceo, coo)
            link(ceo, cfo)
            link(cto, rd)
            link(coo, cs)
            link(cfo, fn)
        case .kanban:
            let p1 = panel("待办", 0, 0, 240, 420, .blue)
            let p2 = panel("进行中", 280, 0, 240, 420, .violet)
            let p3 = panel("已交付", 560, 0, 240, 420, .mint)
            _ = node("调研竞品", 32, 90, .blue, in: p1)
            _ = node("梳理需求", 32, 220, .blue, in: p1)
            _ = node("原型设计", 312, 90, .violet, in: p2)
            _ = node("接口联调", 592, 90, .mint, in: p3)
            _ = node("上线发布", 592, 220, .peach, in: p3)
        case .swot:
            let qs = panel("优势 S", 0, 0, 360, 220, .mint)
            let qw = panel("劣势 W", 400, 0, 360, 220, .peach)
            let qo = panel("机会 O", 0, 260, 360, 220, .blue)
            let qt = panel("威胁 T", 400, 260, 360, 220, .rose)
            _ = node("核心团队稳定", 30, 50, .mint, in: qs)
            _ = node("资金充足", 30, 140, .mint, in: qs)
            _ = node("品牌知名度低", 430, 50, .peach, in: qw)
            _ = node("依赖单一渠道", 430, 140, .peach, in: qw)
            _ = node("新兴市场增长", 30, 300, .blue, in: qo)
            _ = node("政策扶持", 30, 390, .blue, in: qo)
            _ = node("竞争加剧", 430, 300, .rose, in: qt)
            _ = node("进入壁垒高", 430, 390, .rose, in: qt)
        }
        for i in nodes.indices { nodes[i].title = Localization.text(nodes[i].title, language: language) }
        for i in panels.indices { panels[i].title = Localization.text(panels[i].title, language: language) }
        for i in edges.indices { edges[i].label = Localization.text(edges[i].label, language: language) }
        return Diagram(
            title: Localization.text(self == .blank ? "未命名图表" : title, language: language), nodes: nodes, edges: edges,
            panels: panels)
    }
}
