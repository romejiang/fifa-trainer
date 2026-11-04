#!/usr/bin/env python3
"""``tools/lint_core_purity.py`` 的反例自测：脏样例必须变红，干净样例不许误报。

反例优先。一个只会对干净树点头的 lint，和一行 ``true`` 没有区别；所以这里的
每一条硬规则都有一条独立的 canary 证明「它真的会响」，另外又有一份干净 canary
证明「注释、文档字符串、错误消息里提到这些词不会把人逼到删规则」。

用例矩阵：

1. 干净 canary：五个硬 token 全写在 ``##`` / ``#`` / 双引号 / 单引号 / 三引号 /
   raw string 里，另有合法标识符 ``InputSource`` / ``NodeState`` / ``NodePath``
   与小写 JSON path ``deadzone`` —— 0 命中、rc=0。
2. 五条硬规则各有牙齿，``push_error(`` 也算 ``logging``。
3. 九条扩展规则各有牙齿。
4. 退出码三档：干净 0、脏 1、空目录 2、不存在的路径 2。
5. 文档与规则表同源：``--list-rules`` 的每个 id 都必须出现在 ``mobile/docs/CORE.md``。
6. ``--list-rules`` 稳定：14 行，前五行顺序固定。

所有用例都在 ``tempfile.mkdtemp()`` 里搭临时目录，跑完立刻删除；不碰真实
``mobile/src/core``。
"""

from __future__ import annotations

import contextlib
import io
import shutil
import sys
import tempfile
from pathlib import Path
from typing import List, Tuple

sys.path.insert(0, str(Path(__file__).resolve().parent))

import lint_core_purity
from lint_core_purity import repo_root, scan_text, strip_code

PASS = 0
FAIL = 0

HARD_RULE_IDS = [
    "input_singleton",
    "time_singleton",
    "node_type",
    "fileaccess_io",
    "logging",
]

# 五个硬 token 全部只出现在「提到」的语境里：文档字符串、行注释、四种字符串。
# 末尾的合法标识符用来证明词边界与大小写敏感——它们在代码里，而不是字符串里。
CLEAN_SAMPLE = '''\
class_name CleanCanary
extends RefCounted

## 文档字符串：为什么不能用 Input. / Time. / Node / FileAccess / print(。
## 第二行：Input.get_joy_axis() 与 Time.get_ticks_usec() 都只是被提到。
# 行注释：Node.new()、FileAccess.open()、print("x") 都不该命中。
const NOTE := "Input. Time. Node FileAccess print( 全在双引号里"
const SINGLE := 'Input. Time. Node FileAccess print( 全在单引号里'
const TRIPLE := """
Input. Time. Node FileAccess print(
"""
const RAW := r"Input. Time. Node FileAccess print("

var source := InputSource.new()
var state := NodeState.new()
var path := NodePath("res://x")
var deadzone := _input.deadzone


static func identity(value: int) -> int:
	return value
'''


def check(label: str, ok: bool, extra: str = "") -> None:
    global PASS, FAIL
    if ok:
        PASS += 1
        print(f"  \033[32m✓\033[0m {label}" + (f"  ({extra})" if extra else ""))
    else:
        FAIL += 1
        print(f"  \033[31m✗\033[0m {label}" + (f"  ({extra})" if extra else ""))


def _rules(text: str) -> List[str]:
    return [rule for _, rule, _ in scan_text(text)]


def _run_main(args: List[str]) -> Tuple[int, str, str]:
    """调用 lint 的 main()，把 stdout / stderr 收进字符串（不起子进程）。"""
    out, err = io.StringIO(), io.StringIO()
    with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
        rc = lint_core_purity.main(args)
    return rc, out.getvalue(), err.getvalue()


def _write(tmp: str, name: str, text: str) -> Path:
    path = Path(tmp) / name
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8")
    return path


def test_clean_canary() -> None:
    """① 注释与字符串里的同样 token 必须 0 命中。"""
    hits = scan_text(CLEAN_SAMPLE)
    check("干净 canary 零命中", hits == [], str(hits))
    check("strip_code 保留行数", strip_code(CLEAN_SAMPLE).count("\n") == CLEAN_SAMPLE.count("\n"))
    check("strip_code 不保留字符串内容", "Input." not in strip_code(CLEAN_SAMPLE))

    tmp = tempfile.mkdtemp(prefix="fifa-lint-")
    try:
        _write(tmp, "clean.gd", CLEAN_SAMPLE)
        rc, out, err = _run_main([tmp])
        check("干净目录退出 0", rc == 0, f"实际 {rc} / {err.strip()}")
        check("干净目录打印 LINT_OK files=1", "LINT_OK files=1" in out, out.strip())
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


def test_hard_rules_have_teeth() -> None:
    """② 五条硬规则各自变红；push_error( 也归 logging。"""
    hard_cases = {
        "input_singleton": "func f() -> void:\n\tInput.get_joy_axis(0, 0)\n",
        "time_singleton": "func f() -> void:\n\tTime.get_ticks_usec()\n",
        "node_type": "func f() -> void:\n\tNode.new()\n",
        "fileaccess_io": "func f() -> void:\n\tvar f := FileAccess.open(\"user://x\", 1)\n",
        "logging": "func f() -> void:\n\tprint(\"x\")\n",
    }
    check("Input. → input_singleton",
          _rules(hard_cases["input_singleton"]) == ["input_singleton"],
          str(_rules(hard_cases["input_singleton"])))
    check("Time. → time_singleton",
          _rules(hard_cases["time_singleton"]) == ["time_singleton"],
          str(_rules(hard_cases["time_singleton"])))
    check("Node → node_type",
          _rules(hard_cases["node_type"]) == ["node_type"],
          str(_rules(hard_cases["node_type"])))
    check("FileAccess → fileaccess_io",
          _rules(hard_cases["fileaccess_io"]) == ["fileaccess_io"],
          str(_rules(hard_cases["fileaccess_io"])))
    check("print( → logging",
          _rules(hard_cases["logging"]) == ["logging"],
          str(_rules(hard_cases["logging"])))
    check("push_error( → logging",
          _rules("func f() -> void:\n\tpush_error(\"x\")\n") == ["logging"],
          str(_rules("func f() -> void:\n\tpush_error(\"x\")\n")))
    check("printerr( → logging",
          _rules("func f() -> void:\n\tprinterr(\"x\")\n") == ["logging"],
          str(_rules("func f() -> void:\n\tprinterr(\"x\")\n")))


def test_extended_rules_have_teeth() -> None:
    """③ 九条扩展规则各自变红。"""
    cases = {
        "os_singleton": "func f() -> String:\n\treturn OS.get_name()\n",
        "engine_singleton": "func f() -> bool:\n\treturn Engine.is_editor_hint()\n",
        "display_server": "func f() -> void:\n\tDisplayServer.window_set_mode(0)\n",
        "tree_access": "func f() -> void:\n\tget_tree().quit()\n",
        "scene_tree_type": "extends SceneTree\n",
        "resource_loader": "func f() -> void:\n\tResourceLoader.load(\"res://x\")\n",
        "resource_type": "func f() -> Resource:\n\treturn null\n",
        "tool_annotation": "@tool\nextends RefCounted\n",
        "outer_layer_dep": "const X := preload(\"res://src/app/config_store.gd\")\n",
    }
    check("OS. → os_singleton", _rules(cases["os_singleton"]) == ["os_singleton"],
          str(_rules(cases["os_singleton"])))
    check("Engine. → engine_singleton", _rules(cases["engine_singleton"]) == ["engine_singleton"],
          str(_rules(cases["engine_singleton"])))
    check("DisplayServer → display_server", _rules(cases["display_server"]) == ["display_server"],
          str(_rules(cases["display_server"])))
    check("get_tree( → tree_access", _rules(cases["tree_access"]) == ["tree_access"],
          str(_rules(cases["tree_access"])))
    check("SceneTree → scene_tree_type", _rules(cases["scene_tree_type"]) == ["scene_tree_type"],
          str(_rules(cases["scene_tree_type"])))
    check("ResourceLoader → resource_loader", _rules(cases["resource_loader"]) == ["resource_loader"],
          str(_rules(cases["resource_loader"])))
    check("Resource → resource_type", _rules(cases["resource_type"]) == ["resource_type"],
          str(_rules(cases["resource_type"])))
    check("@tool → tool_annotation", _rules(cases["tool_annotation"]) == ["tool_annotation"],
          str(_rules(cases["tool_annotation"])))
    check("preload(res://src/app → outer_layer_dep",
          _rules(cases["outer_layer_dep"]) == ["outer_layer_dep"],
          str(_rules(cases["outer_layer_dep"])))
    check("preload(res://src/core) 不算反向依赖",
          _rules("const X := preload(\"res://src/core/geometry.gd\")\n") == [])
    check("注释里的 preload(res://src/app 不算命中",
          _rules("# 不要写 preload(\"res://src/app/config_store.gd\")\n") == [])


def test_exit_codes() -> None:
    """④ 0 / 1 / 2 三档必须分得清，「什么都没扫到」不是「干净」。"""
    tmp = tempfile.mkdtemp(prefix="fifa-lint-")
    try:
        clean_dir = Path(tmp) / "clean"
        dirty_dir = Path(tmp) / "dirty"
        empty_dir = Path(tmp) / "empty"
        empty_dir.mkdir(parents=True)
        _write(str(clean_dir), "ok.gd", CLEAN_SAMPLE)
        _write(str(dirty_dir), "bad.gd", "func f() -> void:\n\tInput.get_joy_axis(0, 0)\n")

        rc, out, _ = _run_main([str(clean_dir)])
        check("干净目录 rc=0", rc == 0, f"实际 {rc}")
        check("干净目录输出 LINT_OK files=1", "LINT_OK files=1" in out, out.strip())

        rc, out, _ = _run_main([str(dirty_dir)])
        check("脏目录 rc=1", rc == 1, f"实际 {rc}")
        check("脏目录输出含规则名与行号",
              "input_singleton" in out and ":2:" in out, out.strip())

        rc, _, err = _run_main([str(empty_dir)])
        check("空目录 rc=2", rc == 2, f"实际 {rc}")
        check("空目录打印 LINT_INVALID", "LINT_INVALID" in err, err.strip())

        rc, _, err = _run_main([str(Path(tmp) / "nope")])
        check("不存在的路径 rc=2", rc == 2, f"实际 {rc}")
        check("不存在的路径打印 LINT_INVALID", "LINT_INVALID" in err, err.strip())
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


def test_hits_point_at_real_lines() -> None:
    """⑤ 行号与片段必须能直接拿去改代码。"""
    text = "extends RefCounted\n\nfunc f() -> void:\n\tInput.get_joy_axis(0, 0)\n"
    hits = scan_text(text)
    check("命中行号指向真实行 4", bool(hits) and hits[0][0] == 4, str(hits))
    check("命中片段是可读 token Input.", bool(hits) and hits[0][2] == "Input.", str(hits))


def test_doc_and_rules_are_locked() -> None:
    """⑥ 文档必须列出全部规则 id，并保留 LINT_OK 与退出码 2 的契约。"""
    doc_path = repo_root() / "mobile" / "docs" / "CORE.md"
    check("CORE.md 存在", doc_path.is_file(), str(doc_path))
    if not doc_path.is_file():
        return
    text = doc_path.read_text(encoding="utf-8")
    for rule, _ in lint_core_purity.RULES:
        check(f"CORE.md 列出规则 {rule}", rule in text)
    check("CORE.md 说明 LINT_OK 正向哨兵", "LINT_OK" in text)
    check("CORE.md 说明退出码 2", "退出码 2" in text)
    check("CORE.md 说明 FileAccess 不是例外", "FileAccess" in text)


def test_list_rules_is_stable() -> None:
    """⑦ --list-rules 是文档互锁的接口，行数与顺序都不能漂。"""
    rc, out, _ = _run_main(["--list-rules"])
    lines = out.strip().split("\n")
    check("--list-rules 退出 0", rc == 0, f"实际 {rc}")
    check("--list-rules 输出 14 行", len(lines) == 14, f"实际 {len(lines)}")
    check("前五行是 INFRA-03 硬规则且顺序固定",
          lines[:5] == HARD_RULE_IDS, " / ".join(lines[:5]))


def main() -> int:
    print("═" * 62)
    print("  架构边界 lint —— 扫描器反例自测")
    print("═" * 62)

    test_clean_canary()
    test_hard_rules_have_teeth()
    test_extended_rules_have_teeth()
    test_exit_codes()
    test_hits_point_at_real_lines()
    test_doc_and_rules_are_locked()
    test_list_rules_is_stable()

    print("\n" + "═" * 62)
    print(f"  通过 {PASS} 项，失败 {FAIL} 项")
    print("═" * 62)
    return 1 if FAIL else 0


if __name__ == "__main__":
    raise SystemExit(main())
