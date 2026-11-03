"""FIFA / EA FC 花式动作搓招实时监测与震动反馈引擎。

模块划分：
    geometry      —— 角度 / 向量工具
    config        —— skills_config.json 的解析与默认配置
    input_source  —— 手柄状态读取（SDL 映射表驱动的协议无关布局）
    rumble        —— 多后端震动引擎（非阻塞）
    detectors     —— arc / sequence 两类动作识别器
    engine        —— 250Hz 采样主循环
"""

__version__ = "1.0.0"
