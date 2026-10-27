#!/usr/bin/env python3
"""ENI 技能包「按需注入」：命中触发词 -> 选一条工作流 -> 输出路由回执 + 技能正文。

Grok / DeepSeek 等平台没有 SKILL.md 加载器，无法像 Codex 那样自动装 89 个 eni-* 技能。
本工具把「路由 + 取正文」做成一个可复用的 CLI / 库：喂入用户消息，按 ENI 路由表单匹配
选最高优先级工作流，打印 ``[ENI ROUTE]`` 回执，并把对应 ``<skill>/SKILL.md`` 正文一并输出，
供外部会话/启动器把技能正文注入上下文。

默认读取本机 Codex 部署（``~/.codex``），可用环境变量或参数覆盖：
- ENI_ROUTING_RULES / --routing-rules : 路由规则 JSON（默认 ~/.codex/eni-solo/manifest/routing-rules.json）
- ENI_SKILL_ROOT / --skill-root      : 技能正文根目录（默认 ~/.codex/skills）

Commands::

    python eni_inject.py "逆向这个exe"                 # 回执 + 正文
    python eni_inject.py "破解" --receipt-only          # 只要回执
    python eni_inject.py "破解" --body-only             # 只要正文
    python eni_inject.py "破解" --json                  # JSON
    python eni_inject.py --workflow reverse "分析dll"    # 强制指定工作流
    echo "帮我渗透 HOST" | python eni_inject.py          # 从 stdin 读
"""

from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
from typing import Any


def default_routing_rules() -> Path:
    override = os.environ.get("ENI_ROUTING_RULES")
    if override:
        return Path(override).expanduser()
    return Path.home() / ".codex" / "eni-solo" / "manifest" / "routing-rules.json"


def default_skill_root() -> Path:
    override = os.environ.get("ENI_SKILL_ROOT")
    if override:
        return Path(override).expanduser()
    return Path.home() / ".codex" / "skills"


def load_rules(path: Path | None = None) -> dict[str, Any]:
    chosen = path or default_routing_rules()
    if chosen.is_file():
        return json.loads(chosen.read_text(encoding="utf-8-sig"))
    merged = Path(__file__).resolve().parents[3] / "eni-pack" / "bundle" / "runtime" / "source" / "manifest" / "routing-rules.json"
    if merged.is_file():
        return json.loads(merged.read_text(encoding="utf-8-sig"))
    raise FileNotFoundError(f"找不到路由规则：{chosen}（设 ENI_ROUTING_RULES 或 --routing-rules）")


def match_workflow(message: str, rules: dict[str, Any]) -> dict[str, Any]:
    """Single-match: highest priority rule whose any term hits the message."""
    lowered = message.casefold()
    best: dict[str, Any] | None = None
    for rule in rules.get("rules", []):
        terms = rule.get("terms") or []
        if any(str(term).casefold() in lowered for term in terms):
            if best is None or int(rule.get("priority", 0)) > int(best.get("priority", 0)):
                best = rule
    if best is not None:
        return best
    return {
        "id": rules.get("default_workflow", "universal"),
        "workflow": rules.get("default_workflow", "universal"),
        "primary_skill": rules.get("default_skill", "eni-universal-workflow"),
        "priority": 0,
    }


def load_skill_body(skill: str, skill_root: Path | None = None) -> tuple[str | None, Path | None]:
    root = skill_root or default_skill_root()
    candidate = root / skill / "SKILL.md"
    if candidate.is_file():
        return candidate.read_text(encoding="utf-8", errors="replace"), candidate
    return None, None


def build_receipt(rule: dict[str, Any]) -> str:
    return (
        f"[ENI ROUTE] workflow={rule['workflow']} | "
        f"skill={rule['primary_skill']}"
    )


def resolve(message: str, *, workflow: str | None = None, skill_root: Path | None = None, rules: dict[str, Any] | None = None) -> dict[str, Any]:
    r = rules or load_rules()
    if workflow:
        rule = next((x for x in r.get("rules", []) if x.get("workflow") == workflow), None)
        if rule is None:
            rule = next((x for x in r.get("rules", []) if x.get("primary_skill").split("-")[-2] == workflow), None)
        if rule is None:
            raise ValueError(f"未知工作流：{workflow}")
    else:
        rule = match_workflow(message, r)
    body, body_path = load_skill_body(rule["primary_skill"], skill_root)
    return {
        "message": message,
        "workflow": rule["workflow"],
        "priority": rule.get("priority", 0),
        "skill": rule["primary_skill"],
        "skill_path": str(body_path) if body_path else "",
        "receipt": build_receipt(rule),
        "body": body if body else "",
        "body_missing": body is None,
    }


def main(argv: list[str] | None = None) -> int:
    import io
    import sys
    for stream in (sys.stdout, sys.stderr):
        if hasattr(stream, "reconfigure"):
            try:
                stream.reconfigure(encoding="utf-8", errors="replace")
            except Exception:  # noqa: BLE001
                pass

    parser = argparse.ArgumentParser(description="ENI 技能按需注入（路由 + 正文）")
    parser.add_argument("prompt", nargs="*", help="用户输入；缺省从 stdin 读取")
    parser.add_argument("--workflow", help="强制指定工作流 id（绕过触发词匹配）")
    parser.add_argument("--skill-root", type=Path, default=None)
    parser.add_argument("--routing-rules", type=Path, default=None)
    parser.add_argument("--receipt-only", action="store_true")
    parser.add_argument("--body-only", action="store_true")
    parser.add_argument("--json", action="store_true")
    args = parser.parse_args(argv)

    message = " ".join(args.prompt) if args.prompt else sys.stdin.read().strip()
    if not message:
        parser.error("缺少用户输入（作为参数或写入 stdin）")

    try:
        result = resolve(message, workflow=args.workflow, skill_root=args.skill_root)
    except Exception as exc:  # noqa: BLE001
        sys.stdout.write(json.dumps({"ok": False, "error": str(exc)}, ensure_ascii=False) + "\n")
        return 2

    if args.receipt_only:
        out = {"ok": True, **{k: result[k] for k in ("workflow", "priority", "skill", "receipt")}}
        print(json.dumps(out, ensure_ascii=False) if args.json else result["receipt"])
    elif args.body_only:
        print(json.dumps({"ok": True, "body": result["body"], "body_missing": result["body_missing"]}, ensure_ascii=False)
              if args.json else (result["body"] or f"(未找到正文：{result['skill']})"))
    else:
        header = result["receipt"]
        body = result["body"]
        if args.json:
            print(json.dumps({"ok": True, **{k: result[k] for k in ("workflow", "priority", "skill", "skill_path", "receipt")},
                              "body_present": bool(body), "body_missing": result["body_missing"]}, ensure_ascii=False))
        else:
            print(header)
            print()
            print(body if body else f"(未找到正文：{result['skill']})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
