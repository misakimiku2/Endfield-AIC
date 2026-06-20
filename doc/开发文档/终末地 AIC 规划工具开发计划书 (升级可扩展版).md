# **《明日方舟：终末地》AIC 工业规划工具开发计划书**

本计划书旨在为《明日方舟：终末地》玩家社区开发一款高颜值、高性能、跨平台的自动化工业（AIC）系统规划与模拟工具。

技术框架确定采用 **Flutter (基于 CanvasKit 渲染)**，以实现网页端（Web）、移动端（Android）及桌面端（Windows）的高效多端共用。

本版本计划书特别针对**游戏持续运营、多版本内容迭代、自定义物料与配方扩展性**进行了深度的架构设计。

## **一、 核心开发目标（Core Objectives）**

### **1\. 视觉目标：像素级复刻原版美学**

* 坚决摒弃生硬、高饱和度的传统“工业 EDA 软件”配色与圆角。  
* 全面复刻游戏原版的扁平、硬朗、全直角、带有淡雅投影（Drop Shadow）的高级极简工业风。

### **2\. 性能目标：大规模蓝图不掉帧**

* 在画布上摆放超过 **500 个设备**，**1000 条传送带**时：  
  * **PC 网页端**：帧率稳定在 60 FPS 以上（利用 CanvasKit 硬件加速）。  
  * **安卓中端机型**：拖动、缩放画布无任何延迟或卡顿，界面无锯齿。

### **3\. 系统目标：完美的原子解耦**

* 图形与业务逻辑彻底分离。机器的图标由程序根据参数实时“拼装”出来，而不依赖美术一张张去切图。  
* **高动态扩展性**：支持不重新编译、打包应用的情况下，通过导入/导出 JSON、或者在内置的 UI 面板中，自由创建和修改【原料】、【中间合成物】、【最终成品】和【机器合成配方】。

## **二、 核心可扩展性架构设计（Data-Driven Architecture）**

为了保证在游戏后续更新中不改动任何核心代码，我们将整个系统的逻辑建立在三个彼此独立的**本地 JSON 数据库**之上：

┌────────────────────────┐      ┌────────────────────────┐  
│     物料数据库          │      │     机器数据库          │  
│   (items\_db.json)      │      │  (buildings\_db.json)   │  
└───────────┬────────────┘      └───────────┬────────────┘  
            │                               │  
            └───────────────┬───────────────┘  
                            ▼  
                ┌───────────────────────┐  
                │       合成配方         │  
                │   (recipes\_db.json)   │  
                └───────────────────────┘

### **1\. 动态物料定义（Items Definition）**

所有物料被分为三个一级分类，且属性支持无限扩展。

* **原料**（Raw Materials）：如矿物（源石矿、铁矿）、植物（特种农作物）、液体（工业用水）。  
* **中间合成物**（Intermediates）：如粗加工产物（源石粉末）、精密器件。  
* **最终合成物**（Final Products）：如高阶电池、高端工业成品。

### **2\. 动态合成表（Recipe Engine）**

合成表将物料进行输入和输出的关联。支持多输入、多输出、以及速率（Rate）定义。

配方引擎可以动态绑定到任何兼容的生产设备上。

## **三、 数据结构规范（JSON Specification）**

以下为系统运行时读取的核心配置文件规范。更新游戏版本时，只需给对应 JSON 追加数据即可。

### **1\. 物料库配置文件 (items\_db.json)**

{  
  "version": "1.0.0",  
  "items": {  
    "raw\_ore": {  
      "id": "raw\_ore",  
      "name": "源石粗矿",  
      "category": "raw",          // raw (原料) / intermediate (中间物) / final (最终物)  
      "sub\_type": "mineral",      // mineral (矿物) / plant (植物) / liquid (液体)  
      "color": "\#FFAA00",         // 前端传送带上代表该物料的粒子/线段颜色  
      "icon\_svg": "raw\_ore\_symbol"// 对应引用的矢量图标ID  
    },  
    "ore\_powder": {  
      "id": "ore\_powder",  
      "name": "源石粉末",  
      "category": "intermediate",  
      "sub\_type": "mineral",  
      "color": "\#D1D1D1",  
      "icon\_svg": "powder\_symbol"  
    },  
    "power\_cell": {  
      "id": "power\_cell",  
      "name": "集成能量电池",  
      "category": "final",  
      "sub\_type": "machinery",  
      "color": "\#00FF66",  
      "icon\_svg": "cell\_symbol"  
    }  
  }  
}

### **2\. 合成配方配置文件 (recipes\_db.json)**

合成不与机器锁死，而是一个独立的“节点规则”。一个机器只要满足“分类限制”，就可以动态载入并运行此配方。

{  
  "version": "1.0.0",  
  "recipes": {  
    "ore\_shredding": {  
      "id": "ore\_shredding",  
      "name": "粗矿粉碎",  
      "allowed\_buildings": \["shredder\_3x3"\], // 允许哪些设备运行此配方  
      "process\_time\_seconds": 1.0,           // 加工标准周期时间  
      "inputs": \[  
        {"item\_id": "raw\_ore", "amount": 1}   // 输入：1个源石粗矿  
      \],  
      "outputs": \[  
        {"item\_id": "ore\_powder", "amount": 2} // 输出：2个源石粉末  
      \]  
    }  
  }  
}

## **四、 开发路线大纲（Development Outline）**

配合“骨架先行、资产后置”的敏捷原则，路线大纲重构为以下阶段：

\[阶段一：Canvas 交互骨架搭建\] (无限网格 / 缩放平移 / 占位符拖拽)  
             ↓  
\[阶段二：积木组装定位引擎\] (接口与隔条的相对坐标计算 / 旋转矩阵变换)  
             ↓  
\[阶段三：物料与配方数据注入\] (JSON 驱动 / 动态加载配方 / 逻辑端口映射)  
             ↓  
\[阶段四：精准矢量资产替换\] (Inkscape 纯直角 SVG / 状态颜色变换)  
             ↓  
\[阶段五：仿真 Tick 生产模拟\] (一维队列传送带 / 缓冲区堵塞算法)  
             ↓  
\[阶段六：多端打包与自定义配置面板\] (IndexedDB 动态保存 / 免费静态托管)

### **阶段一：Canvas 交互骨架搭建**

* **目标**：实现流畅无阻的沙盒操作环境，奠定跨平台底座。  
* **关键任务**：  
  1. 设定 \#E4E4E4 灰底与 \#b0b0b0（50%透明度）的 ![][image1] 无限网格线。  
  2. 支持 PC 鼠标滚轮/中键、移动端双指手势的平移与缩放。  
  3. 实现纯色色块占位符的拖拽、网格高精度吸附、基础碰撞检测（防重叠）。

### **阶段二：积木组装定位引擎**

* **目标**：实现无需切图的设备图标动态装配。  
* **关键任务**：  
  1. 建立机器的主框体（上下粗、左右细）渲染逻辑。  
  2. 实现程序在 Y=0 和 Y=Bottom 边缘，根据相对坐标动态绘制接口方框、箭头和隔离小长方形（早期使用线条占位）。  
  3. 编写旋转计算：设备旋转时，整体框架跟随旋转，而内部的逻辑方向箭头进行“反向抵抗”保持朝向不变。

### **阶段三：物料与配方数据注入**

* **目标**：实现数据和网格模型的深度绑定。  
* **关键任务**：  
  1. 读取本地 JSON 配置文件。  
  2. 实现点击组件弹出属性面板：可自由选择当前设备运行哪一个兼容的配方（例如：粉碎机载入“粗矿粉碎”）。  
  3. 根据配方定义，自动激活机器的对应端口（哪些是进料、哪些是出料）。

### **阶段四：精准矢量资产替换**

* **目标**：将占位符替换为游戏原版质感的美术素材。  
* **关键任务**：  
  1. 导入 Inkscape 中雕琢出来的标准矢量 SVG 原子路径（机身、隔离条、箭头、接头）。  
  2. 启用 **离屏重绘缓存（Offscreen Picture Caching）**：把拼好的复杂 SVG 缓存在内存，缩放拖动时作为一整张位图硬件加速渲染，确保数百台设备同屏依然满帧。  
  3. 实现端口状态指示：例如管线连通时，接口和箭头的 SVG 属性变为代表激活的黄色或蓝色。

### **阶段五：仿真 Tick 生产模拟**

* **目标**：流水线动起来，模拟真正的工业传输。  
* **关键任务**：  
  1. 建立全局 Ticks 定时器，脱离物理秒表，保证离线与高倍速计算。  
  2. 一维队列（Queue）传送带流动：只更新传送带两端状态，实现成千上万矿石粒子不卡顿的滚动效果。  
  3. 进出缓冲区（Buffer Limit 50）与设备堵塞（Blocked State）逻辑。

### **阶段六：多端打包与自定义配置面板**

* **目标**：让玩家能自定义物料并发布。  
* **关键任务**：  
  1. 提供图形化 UI 编辑器：在不碰代码的情况下，玩家可以直接添加新源矿、新成品和新配方。  
  2. 数据本地化：使用 IndexedDB 进行沙盒备份与导出蓝图码。  
  3. 构建 Web 静态应用，一键 0 成本发布部署。

## **五、 开发路线规划（How We Start）**

1\. 【交互骨架就位】(已完成) \-\> 跑通 Flutter Canvas 的网格绘制、双端缩放手势、以及占位块的拖动吸附。  
         ↓  
2\. 【积木引擎编写】(当前进行中) \-\> 让机器能通过代码参数在边缘画出对应的接口方框、箭头和隔离条。  
         ↓  
3\. 【JSON 规则映射】 \-\> 导入 items 和 recipes 数据，点击机器能切换生产配方，自动定义进出料端口。  
         ↓  
4\. 【Inkscape 图标替换】 \-\> 将精致的 SVG 原子导入 Flutter Canvas，完成“旧貌换新颜”。  
         ↓  
5\. 【Tick 仿真跑通】 \-\> 让传送带连通设备，矿石粒子真正跑起来，验证堵塞逻辑。  


[image1]: <data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAACgAAAAXCAYAAAB50g0VAAAC3klEQVR4Xu2VTUhUURTHZ3CCoiKjpiHn486MkEVBwQQSbYKyIBCkcFObIKgWbnLT506iD4wCa2NCtAiFgmidRCBE6KIWSSuJQoKIDEIXGVa//7x7685Ns4HMCP/w577zcc85957z3ovFFrCABfxHyGQyS4wxB2A3PJdOpzOhj498Pt+C36VQPycg0Qb4jKSnVFgul2vlebC+vn5N6Ctgy+M/wnIrtP1xqAiSPVdxiPFUKrUUuR9OUGgp9C+VSouw9cCvf6VAijhBsve6RU+3k+Qn1Xbf19pa8b0MR+e8wGKxuIJET+AQrV0l2rbWhL6CbW03y3rWV36BPNcWCgXDAZo5WBp5MdwhWXGdnzqAX4r9a0WbLyGfQFfjZk+3pyKvwzOwCw4TfIsL6gKj70TfaAOFBR5H99ZErR9kvQcPUuB51gnYhltch0R3H3lcvvCxDsR6x8rj2Pt0YLWrZDd/gftsLgW5iPzCf5OR98N22c00BQpevM7Yjy7IvwNOYW9yvioU3Qjs1uERD/HcUzFWXsDhurq61Z6+2UQ3cVSyWgduaCQkz1ag5trXZ7PZTeg/wLuICac30aGV/zTsdfG/g8SbMXyEj5LJ5DKn9wpUAQnkCzw3Onu1BTp/OIRtpWeKI181UQf3evoIdlh1zTMWaD9DA+heOyK/kR1OSsbvmN03W4EDDQ0Nyz2T2n9We2D/TzcIEhh6TXAyr8Byi0O4hFXc4Db4CV5DjHt6tbgL/+0mGoEO314GxiYM7xTcqqZ9SXxIj30U3o55Ab0Cb2rwpdMq2ebYaF2VYw+6py4Hz21wSkW7eGXYz4eu+SUBjuhESs5gb61wBPrL4NOHfdJELRbHwhbDh/CBif7r+ksN0r518iHubhMV4va3e38vpxsj1q6K5LzFWQK1KIA2VBh/E0GLazS/9iNd2bb5wkwz+E+A26/NRS/XZ9Yrv/plzgso7LCJZq7MXPTtrA39qsE33MQBV5gjp5QAAAAASUVORK5CYII=>