#!/usr/bin/env python3
"""Замер качества перевода моделей через OpenRouter (B5/B1).

Без внешних зависимостей. Три команды:

  list-models --grep gemini     модели OpenRouter с ценой и модальностями
  run  ...                      прогнать модели по тестовым предложениям
  report --results FILE         пересчитать метрики по сохранённым ответам

Что это измеряет: расхождение с профессиональным переводом (chrF++). Это
НЕ «качество вообще»: хороший перевод другими словами получит меньше. Поэтому
у каждой цифры есть доверительный интервал, а отличия внутри интервала
считаются шумом. Подробности и ограничения — в bench/README.md.

Ключ: переменная окружения OPENROUTER_API_KEY (в файлах и логах не хранится).
"""
from __future__ import annotations

import argparse
import json
import math
import os
import random
import re
import statistics
import sys
import time
import urllib.error
import urllib.request
from collections import Counter
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

ROOT = Path(__file__).resolve().parent
REPO = ROOT.parent
API = "https://openrouter.ai/api/v1"

# --- Языки: код пары -> (код в NTREX, код во FLORES, имя языка для промпта) ---
LANGS = {
    "he": ("heb", "heb_Hebr", "иврит"),
    "ru": ("rus", "rus_Cyrl", "русский"),
    "en": ("eng", "eng_Latn", "английский"),
    "ar": ("arb", "arb_Arab", "арабский"),
}


# ----------------------------------------------------------------------------
# chrF++ (собственная реализация, близка к sacreBLEU, но не идентична)
# ----------------------------------------------------------------------------
def _ngrams(tokens: list[str], n: int) -> Counter:
    return Counter(tuple(tokens[i : i + n]) for i in range(len(tokens) - n + 1))


def chrf(hyp: str, ref: str, char_order: int = 6, word_order: int = 2, beta: float = 2.0) -> float:
    """chrF++ по одному сегменту, 0..100. Усреднение точности и полноты по
    всем порядкам n-грамм (символьные 1..6 без пробелов, словные 1..2)."""
    if not hyp.strip() or not ref.strip():
        return 100.0 if hyp.strip() == ref.strip() else 0.0
    hyp_chars, ref_chars = list(re.sub(r"\s+", "", hyp)), list(re.sub(r"\s+", "", ref))
    hyp_words, ref_words = hyp.split(), ref.split()
    precisions, recalls = [], []
    for tokens_h, tokens_r, orders in (
        (hyp_chars, ref_chars, range(1, char_order + 1)),
        (hyp_words, ref_words, range(1, word_order + 1)),
    ):
        for n in orders:
            h, r = _ngrams(tokens_h, n), _ngrams(tokens_r, n)
            h_total, r_total = sum(h.values()), sum(r.values())
            if h_total == 0 or r_total == 0:
                continue
            overlap = sum((h & r).values())
            precisions.append(overlap / h_total)
            recalls.append(overlap / r_total)
    if not precisions:
        return 0.0
    p, r = sum(precisions) / len(precisions), sum(recalls) / len(recalls)
    if p + r == 0:
        return 0.0
    return 100.0 * (1 + beta**2) * p * r / (beta**2 * p + r)


# ----------------------------------------------------------------------------
# Данные
# ----------------------------------------------------------------------------
def read_lines(path: Path) -> list[str]:
    return path.read_text(encoding="utf-8").splitlines()


def load_corpus(corpus: str, data_dir: Path, langs: list[str]) -> dict[str, list[str]]:
    """Параллельные строки по языкам (индекс i — одно и то же предложение)."""
    result: dict[str, list[str]] = {}
    for lang in langs:
        ntrex_code, flores_code, _ = LANGS[lang]
        if corpus == "ntrex":
            name = "newstest2019-src.eng.txt" if lang == "en" else f"newstest2019-ref.{ntrex_code}.txt"
            path = data_dir / "ntrex" / name
        elif corpus == "flores":
            path = data_dir / "flores200_dataset" / "devtest" / f"{flores_code}.devtest"
        else:
            raise SystemExit(f"неизвестный корпус: {corpus}")
        if not path.exists():
            raise SystemExit(f"нет файла {path} — см. bench/README.md, раздел «Данные»")
        result[lang] = read_lines(path)
    sizes = {len(v) for v in result.values()}
    if len(sizes) != 1:
        raise SystemExit(f"корпусы разной длины: { {k: len(v) for k, v in result.items()} } — выравнивание ненадёжно")
    return result


def sample_indices(parallel: dict[str, list[str]], n: int, seed: int, min_chars: int = 20, max_chars: int = 300) -> list[int]:
    """Детерминированная выборка; берём только предложения подходящей длины
    во всех языках сразу."""
    size = len(next(iter(parallel.values())))
    ok = [
        i for i in range(size)
        if all(min_chars <= len(parallel[lang][i].strip()) <= max_chars for lang in parallel)
    ]
    random.Random(seed).shuffle(ok)
    return sorted(ok[:n])


def load_app_prompt() -> str:
    """Системный промпт приложения — ровно тот, что уходит модели, чтобы
    замер отражал реальное поведение, а не абстрактную способность."""
    source = (REPO / "LLMTranslateKit/Sources/Prompting/PromptBuilder.swift").read_text(encoding="utf-8")
    match = re.search(r'defaultTextSystemPrompt = """\n(.*?)\n\s*"""', source, re.S)
    if not match:
        raise SystemExit("не нашёл defaultTextSystemPrompt в PromptBuilder.swift")
    lines = match.group(1).split("\n")
    indent = min(len(l) - len(l.lstrip()) for l in lines if l.strip())
    return "\n".join(l[indent:] for l in lines)


def render_prompt(template: str, target_name: str) -> str:
    return template.replace("{targetLanguage}", target_name).replace("{glossarySection}", "").rstrip()


# ----------------------------------------------------------------------------
# OpenRouter
# ----------------------------------------------------------------------------
def api_key() -> str:
    key = os.environ.get("OPENROUTER_API_KEY", "").strip()
    if not key:
        raise SystemExit("задайте OPENROUTER_API_KEY в окружении (ключ нигде не сохраняется)")
    return key


def http_json(url: str, payload: dict | None = None, key: str | None = None, timeout: int = 120) -> dict:
    headers = {"Content-Type": "application/json"}
    if key:
        headers["Authorization"] = f"Bearer {key}"
    data = json.dumps(payload).encode() if payload is not None else None
    request = urllib.request.Request(url, data=data, headers=headers)
    last_error: Exception | None = None
    for attempt in range(7):
        pause = min(30, 2 ** attempt)
        try:
            with urllib.request.urlopen(request, timeout=timeout) as response:
                return json.loads(response.read())
        except urllib.error.HTTPError as error:
            last_error = error
            if error.code not in (408, 429, 500, 502, 503, 504):
                raise
            retry_after = error.headers.get("Retry-After") if error.headers else None
            if retry_after and retry_after.isdigit():
                pause = min(60, max(pause, int(retry_after)))
        except (urllib.error.URLError, TimeoutError) as error:
            last_error = error
        time.sleep(pause)
    raise RuntimeError(f"запрос не удался: {last_error}")


def check_key(key: str) -> str:
    """Проверка ключа без трат: запрос метаданных ключа. Печатает только форму
    ключа (длина, префикс), не значение. Возвращает описание или бросает SystemExit."""
    shape = f"длина {len(key)}, префикс «{key[:6]}»" + (", есть пробелы/переводы строк по краям!" if key != key.strip() else "")
    try:
        data = http_json(f"{API}/key", key=key.strip(), timeout=30)
    except urllib.error.HTTPError as error:
        raise SystemExit(f"OpenRouter отклонил ключ (HTTP {error.code}); форма ключа: {shape}. "
                         "Ожидается префикс «sk-or-» и длина около 70 символов.")
    info = data.get("data", {})
    limit = info.get("limit")
    remaining = info.get("limit_remaining")
    return f"ключ принят ({shape}); лимит: {limit if limit is not None else 'нет'}, осталось: {remaining if remaining is not None else '—'}"


def fetch_models() -> dict[str, dict]:
    data = http_json(f"{API}/models")
    return {m["id"]: m for m in data.get("data", [])}


def translate(model: str, system: str, text: str, key: str, max_tokens: int = 2048, no_reasoning: bool = False) -> dict:
    started = time.time()
    try:
        payload = {
            "model": model,
            "messages": [{"role": "system", "content": system}, {"role": "user", "content": text}],
            "temperature": 0,
            "max_tokens": max_tokens,
        }
        if no_reasoning:
            payload["reasoning"] = {"enabled": False}  # единый параметр OpenRouter
        data = http_json(f"{API}/chat/completions", payload, key=key)
        message = (data.get("choices") or [{}])[0].get("message", {})
        usage = data.get("usage") or {}
        return {
            "output": (message.get("content") or "").strip(),
            "latency": round(time.time() - started, 3),
            "prompt_tokens": usage.get("prompt_tokens"),
            "completion_tokens": usage.get("completion_tokens"),
            "error": None,
        }
    except Exception as error:  # сеть, лимиты, отказ модели — записываем и идём дальше
        return {"output": "", "latency": round(time.time() - started, 3), "prompt_tokens": None,
                "completion_tokens": None, "error": str(error)[:300]}


# ----------------------------------------------------------------------------
# Метрики
# ----------------------------------------------------------------------------
def bootstrap_ci(values: list[float], resamples: int = 1000, seed: int = 0) -> tuple[float, float]:
    if len(values) < 2:
        return (values[0], values[0]) if values else (0.0, 0.0)
    rng = random.Random(seed)
    means = sorted(statistics.fmean(rng.choices(values, k=len(values))) for _ in range(resamples))
    return means[int(0.025 * resamples)], means[int(0.975 * resamples) - 1]


def paired_diff_ci(a: list[float], b: list[float], resamples: int = 1000, seed: int = 0) -> tuple[float, float, float]:
    diffs = [x - y for x, y in zip(a, b)]
    low, high = bootstrap_ci(diffs, resamples, seed)
    return statistics.fmean(diffs), low, high


MIN_SUCCESS_RATE = 0.8


def is_ok(row: dict) -> bool:
    return bool(row["output"]) and not row["error"]


def load_rows(paths: list[str]) -> list[dict]:
    """Строки результатов из нескольких файлов. Одна и та же тройка
    (пара, модель, предложение) в нескольких файлах — побеждает более
    поздний файл в списке (так дозапрос упавших и перепрогон заменяют старое)."""
    merged: dict[tuple, dict] = {}
    for path in paths:
        for line in Path(path).read_text(encoding="utf-8").splitlines():
            if line.strip():
                row = json.loads(line)
                merged[(row["pair"], row["model"], row["index"])] = row
    return list(merged.values())


def analyze(rows: list[dict], models_info: dict[str, dict] | None = None) -> dict:
    """Статистика по (пара, модель). Качество считается только по удавшимся
    ответам (сбой — недоступность, а не плохой перевод); сравнение с лидером —
    на предложениях, удавшихся у обеих моделей. Модель, у которой удалось
    меньше 80% запросов, не оценивается (`excluded`)."""
    result: dict[str, dict] = {}
    for pair in sorted({r["pair"] for r in rows}):
        by_model: dict[str, list[dict]] = {}
        for r in rows:
            if r["pair"] == pair:
                by_model.setdefault(r["model"], []).append(r)
        ok_scores = {m: {r["index"]: r["chrf"] for r in rs if is_ok(r)} for m, rs in by_model.items()}
        rate = {m: len(ok_scores[m]) / max(len(by_model[m]), 1) for m in by_model}
        evaluable = [m for m in by_model if rate[m] >= MIN_SUCCESS_RATE]
        leader = max(evaluable, key=lambda m: statistics.fmean(ok_scores[m].values())) if evaluable else None
        models: dict[str, dict] = {}
        for m, rs in by_model.items():
            entry: dict = {"rows": len(rs), "ok": len(ok_scores[m]), "verdict": "excluded", "chrf": None,
                           "ci_low": None, "ci_high": None, "diff": 0.0}
            latency_values = [r["latency"] for r in rs if is_ok(r)] or [r["latency"] for r in rs]
            entry["latency"] = statistics.median(latency_values)
            entry["cost_per_1000"] = cost_per_1000_value(rs, (models_info or {}).get(m))
            if m in evaluable:
                values = list(ok_scores[m].values())
                entry["chrf"] = statistics.fmean(values)
                entry["ci_low"], entry["ci_high"] = bootstrap_ci(values)
                if m == leader:
                    entry["verdict"] = "leader"
                else:
                    common = sorted(set(ok_scores[leader]) & set(ok_scores[m]))
                    diff, low_diff, _ = paired_diff_ci([ok_scores[leader][i] for i in common], [ok_scores[m][i] for i in common])
                    entry["diff"] = diff
                    # значимо хуже, только если весь интервал разницы выше нуля
                    entry["verdict"] = "worse" if low_diff > 0 else "noise"
            models[m] = entry
        result[pair] = {"total": max(len(rs) for rs in by_model.values()), "leader": leader, "models": models}
    return result


def render(analysis: dict) -> str:
    out: list[str] = []
    verdict_text = {"leader": "лидер", "noise": "≈ лучшая (в шуме)", "excluded": "не оценивается (сбои)"}
    for pair, data in analysis.items():
        out.append(f"\n### {pair}  (предложений: {data['total']})\n")
        out.append("| Модель | chrF++ | 95% ДИ | vs лидер | удачных | задержка, с | $/1000 предл. |")
        out.append("|---|---|---|---|---|---|---|")
        order = sorted(
            data["models"].items(),
            key=lambda kv: (kv[1]["chrf"] is None, -(kv[1]["chrf"] or 0), -kv[1]["ok"]),
        )
        for m, e in order:
            verdict = f"хуже на {e['diff']:.1f}" if e["verdict"] == "worse" else verdict_text[e["verdict"]]
            mean_text = "—" if e["chrf"] is None else f"{e['chrf']:.1f}"
            ci_text = "—" if e["chrf"] is None else f"{e['ci_low']:.1f}–{e['ci_high']:.1f}"
            cost = "—" if e["cost_per_1000"] is None else f"{e['cost_per_1000']:.3f}"
            out.append(f"| `{m}` | {mean_text} | {ci_text} | {verdict} | {e['ok']}/{e['rows']} | {e['latency']:.1f} | {cost} |")
    return "\n".join(out)


def summarize(rows: list[dict], models_info: dict[str, dict] | None = None) -> str:
    return render(analyze(rows, models_info))


def cost_per_1000_value(rows: list[dict], info: dict | None) -> float | None:
    if not info:
        return None
    pricing = info.get("pricing") or {}
    try:
        price_in, price_out = float(pricing["prompt"]), float(pricing["completion"])
    except (KeyError, TypeError, ValueError):
        return None
    spent = sum((r["prompt_tokens"] or 0) * price_in + (r["completion_tokens"] or 0) * price_out for r in rows)
    return spent / max(len(rows), 1) * 1000


# ----------------------------------------------------------------------------
# Команды
# ----------------------------------------------------------------------------
def cmd_list_models(args: argparse.Namespace) -> None:
    models = fetch_models()
    rows = []
    for model_id, m in models.items():
        if args.grep and args.grep.lower() not in model_id.lower():
            continue
        pricing = m.get("pricing") or {}
        try:
            price = f"{float(pricing['prompt']) * 1e6:.2f} / {float(pricing['completion']) * 1e6:.2f}"
        except (KeyError, TypeError, ValueError):
            price = "?"
        images = "image" in ((m.get("architecture") or {}).get("input_modalities") or [])
        rows.append((model_id, price, "img" if images else "", m.get("context_length")))
    for model_id, price, images, context in sorted(rows):
        print(f"{model_id:55} ${price:>14} /1M in/out  {images:4} ctx={context}")
    print(f"\nвсего: {len(rows)}", file=sys.stderr)


def cmd_check_key(args: argparse.Namespace) -> None:
    print(check_key(api_key()))


def cmd_run(args: argparse.Namespace) -> None:
    key = api_key()
    print(check_key(key), file=sys.stderr)  # отказ ключа — сразу, а не после 330 запросов
    models = [l.strip() for l in Path(args.models).read_text().splitlines() if l.strip() and not l.startswith("#")]
    src, dst = args.pair.split("-")
    parallel = load_corpus(args.corpus, Path(args.data_dir), [src, dst])
    indices = sample_indices(parallel, args.n, args.seed)
    system = render_prompt(load_app_prompt(), LANGS[dst][2])
    catalog = fetch_models()
    unknown = [m for m in models if m not in catalog]
    if unknown:
        raise SystemExit(f"нет в каталоге OpenRouter: {unknown} (см. list-models)")

    jobs = [(m, i) for m in models for i in indices]
    print(f"{args.corpus} {args.pair}: {len(indices)} предложений × {len(models)} моделей = {len(jobs)} запросов", file=sys.stderr)

    def work(job: tuple[str, int]) -> dict:
        model, index = job
        result = translate(model, system, parallel[src][index].strip(), key, args.max_tokens, args.no_reasoning)
        reference = parallel[dst][index].strip()
        return {
            "corpus": args.corpus, "pair": args.pair, "model": model, "index": index,
            "source": parallel[src][index].strip(), "reference": reference, **result,
            "chrf": chrf(result["output"], reference) if result["output"] else 0.0,
        }

    with ThreadPoolExecutor(max_workers=args.workers) as pool:
        rows = []
        for n, row in enumerate(pool.map(work, jobs), 1):
            rows.append(row)
            if n % 20 == 0:
                print(f"  {n}/{len(jobs)}", file=sys.stderr)

    out = Path(args.out or ROOT / "results" / f"{args.corpus}-{args.pair}-{int(time.time())}.jsonl")
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text("\n".join(json.dumps(r, ensure_ascii=False) for r in rows) + "\n", encoding="utf-8")
    print(f"сохранено: {out}", file=sys.stderr)
    print(summarize(rows, catalog))


def cmd_retry(args: argparse.Namespace) -> None:
    """Переспросить только упавшие запросы и записать результат в тот же файл."""
    key = api_key()
    print(check_key(key), file=sys.stderr)
    template = load_app_prompt()
    for path in map(Path, args.results):
        rows = [json.loads(l) for l in path.read_text(encoding="utf-8").splitlines() if l.strip()]
        failed = [r for r in rows if not is_ok(r)]
        print(f"{path.name}: упавших {len(failed)} из {len(rows)}", file=sys.stderr)
        if not failed:
            continue

        def work(row: dict) -> dict:
            target_name = LANGS[row["pair"].split("-")[1]][2]
            result = translate(row["model"], render_prompt(template, target_name), row["source"], key,
                               args.max_tokens, args.no_reasoning)
            return {**row, **result, "chrf": chrf(result["output"], row["reference"]) if result["output"] else 0.0}

        with ThreadPoolExecutor(max_workers=args.workers) as pool:
            redone = list(pool.map(work, failed))
        replacements = {(r["model"], r["index"]): r for r in redone}
        rows = [replacements.get((r["model"], r["index"]), r) for r in rows]
        path.write_text("\n".join(json.dumps(r, ensure_ascii=False) for r in rows) + "\n", encoding="utf-8")
        still = sum(1 for r in rows if not is_ok(r))
        print(f"  после повтора упавших: {still}", file=sys.stderr)


# ----------------------------------------------------------------------------
# Рейтинг «лучше»: интегральный критерий (качество, цена, скорость)
# ----------------------------------------------------------------------------
WEIGHTS = {"quality": 0.5, "cost": 0.3, "speed": 0.2}
# Второй рейтинг — для сильной модели («Точнее»): качество важнее цены и скорости, и учитывается
# сырое отставание от лидера, а не только значимое/незначимое.
QUALITY_WEIGHTS = {"quality": 0.8, "cost": 0.1, "speed": 0.1}
QUALITY_FOCUS_SCALE = 6.0               # отставание в chrF-пунктах, при котором оценка качества падает до 0
COST_BEST, COST_WORST = 0.03, 3.0      # $ за 1000 предложений: ≤ лучшего → 1.0, ≥ худшего → 0.0 (логарифм)
LATENCY_BEST, LATENCY_WORST = 0.5, 10.0  # секунд на ответ
QUALITY_SCALE = 10.0                    # отставание в chrF-пунктах, при котором оценка качества падает до 0
METHOD_VERSION = 1


def _log_scale(value: float, best: float, worst: float) -> float:
    if value <= best:
        return 1.0
    if value >= worst:
        return 0.0
    return 1.0 - math.log10(value / best) / math.log10(worst / best)


def score_model(pairs: dict[str, dict]) -> dict | None:
    """Оценка 0–100 по замерам модели в разных парах. `None`, если нигде не оценена."""
    usable = [p for p in pairs.values() if p["verdict"] != "excluded" and p["chrf"] is not None]
    if not usable:
        return None
    quality = statistics.fmean(
        1.0 if p["verdict"] in ("leader", "noise") else max(0.0, 1.0 - p["diff"] / QUALITY_SCALE) for p in usable
    )
    costs = [p["cost_per_1000"] for p in usable if p["cost_per_1000"] is not None]
    cost = statistics.fmean(costs) if costs else COST_WORST
    latency = statistics.fmean(p["latency"] for p in usable)
    cost_score = _log_scale(cost, COST_BEST, COST_WORST)
    speed_score = _log_scale(latency, LATENCY_BEST, LATENCY_WORST)
    total = WEIGHTS["quality"] * quality + WEIGHTS["cost"] * cost_score + WEIGHTS["speed"] * speed_score
    # без порога значимости: разница в 1–2 пункта chrF тоже что-то говорит, пусть и в пределах шума
    raw_quality = statistics.fmean(max(0.0, 1.0 - max(p["diff"], 0.0) / QUALITY_FOCUS_SCALE) for p in usable)
    quality_total = (QUALITY_WEIGHTS["quality"] * raw_quality + QUALITY_WEIGHTS["cost"] * cost_score
                     + QUALITY_WEIGHTS["speed"] * speed_score)
    return {
        "score": round(100 * total),
        "quality_score": round(100 * quality_total),
        "raw_quality": round(raw_quality, 3),
        "quality": round(quality, 3), "cost_score": round(cost_score, 3), "speed_score": round(speed_score, 3),
        "cost_per_1000": round(cost, 4), "latency": round(latency, 2),
        "sentences": min(p["ok"] for p in usable),
    }


def model_key(raw_id: str) -> str:
    """Тот же ключ, что `ModelRatings.key(for:)` в Swift (есть тест на совпадение)."""
    model = raw_id.lower()
    if ":" in model and model.rsplit(":", 1)[1] in {"free", "batch", "nitro", "floor", "extended", "online"}:
        model = model.rsplit(":", 1)[0]
    model = model.rsplit("/", 1)[-1]
    model = model.replace(".", "-")
    for pattern in (r"-20\d{6}$", r"-20\d{2}-\d{2}-\d{2}$"):
        model = re.sub(pattern, "", model)
    return model


def build_ratings(measurements: dict) -> list[dict]:
    rated = []
    for model, info in measurements["models"].items():
        scored = score_model(info["pairs"])
        if scored:
            rated.append({"name": model, "key": model_key(model), **scored,
                          "disable_reasoning": bool(info.get("reasoningOffRecommended"))})
    rated.sort(key=lambda r: (-r["score"], -r["quality_score"], r["name"]))
    return rated


def swift_source(measurements: dict, ratings: list[dict]) -> str:
    lines = [
        "// СГЕНЕРИРОВАНО: python3 bench/bench.py rank — не править вручную.",
        f"// Замер: {measurements['measuredAt']}, корпус {measurements['corpus']}, seed {measurements['seed']}; метод v{METHOD_VERSION}.",
        f"// Взвешенный = {WEIGHTS['quality']}·качество + {WEIGHTS['cost']}·цена + {WEIGHTS['speed']}·скорость;",
        f"// с упором на качество = {QUALITY_WEIGHTS['quality']}·качество + {QUALITY_WEIGHTS['cost']}·цена + {QUALITY_WEIGHTS['speed']}·скорость",
        f"// (качество по сырому отставанию от лидера: 1 − отставание/{QUALITY_FOCUS_SCALE:g} chrF);",
        f"// цена {COST_BEST}→1 … {COST_WORST}→0 $/1000 предл. (лог.), задержка {LATENCY_BEST}→1 … {LATENCY_WORST}→0 с (лог.),",
        f"// качество: 1 если не значимо хуже лидера, иначе 1 − отставание/{QUALITY_SCALE:g} chrF.",
        "// Пересмотр: docs/RATINGS.md.",
        "",
        "extension ModelRatings {",
        f'    public static let measuredAt = "{measurements["measuredAt"]}"',
        f"    public static let methodVersion = {METHOD_VERSION}",
        "    public static let entries: [ModelRating] = [",
    ]
    for r in ratings:
        reasoning = ", disableReasoningRecommended: true" if r["disable_reasoning"] else ""
        lines.append(
            f'        ModelRating(key: "{r["key"]}", name: "{r["name"]}", score: {r["score"]}, qualityScore: {r["quality_score"]}, sentences: {r["sentences"]}{reasoning}),'
        )
    lines += ["    ]", "}", ""]
    return "\n".join(lines)


def cmd_export_measurements(args: argparse.Namespace) -> None:
    """Сводка замеров в файл, который лежит в git: по нему рейтинг пересобирается
    без сырых ответов и без самих корпусов (лицензия)."""
    rows = load_rows(args.results)
    for r in rows:
        r["chrf"] = chrf(r["output"], r["reference"]) if r["output"] else 0.0
    catalog = fetch_models()
    analysis = analyze(rows, catalog)
    models: dict[str, dict] = {}
    for pair, data in analysis.items():
        for model, e in data["models"].items():
            entry = models.setdefault(model, {"pairs": {}})
            entry["pairs"][pair] = {k: (round(v, 4) if isinstance(v, float) else v) for k, v in e.items()}
            if model in (args.reasoning_off or []):
                entry["reasoningOffRecommended"] = True
    measured = max(Path(p).stat().st_mtime for p in args.results)
    out = {
        "measuredAt": time.strftime("%Y-%m-%d", time.localtime(measured)),
        "corpus": rows[0]["corpus"], "seed": args.seed, "models": models,
    }
    Path(args.out).write_text(json.dumps(out, ensure_ascii=False, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(f"записано: {args.out} ({len(models)} моделей)", file=sys.stderr)


def cmd_rank(args: argparse.Namespace) -> None:
    measurements = json.loads(Path(args.measurements).read_text(encoding="utf-8"))
    ratings = build_ratings(measurements)
    for i, r in enumerate(ratings, 1):
        print(f"{i:2}. {r['score']:3} / кач. {r['quality_score']:3}  {r['name']:42} качество {r['quality']:.2f}  цена {r['cost_score']:.2f} "
              f"(${r['cost_per_1000']}/1000)  скорость {r['speed_score']:.2f} ({r['latency']}с)  n={r['sentences']}")
    if args.swift:
        Path(args.swift).write_text(swift_source(measurements, ratings), encoding="utf-8")
        print(f"записано: {args.swift}", file=sys.stderr)


def cmd_report(args: argparse.Namespace) -> None:
    rows = load_rows(args.results)
    for r in rows:  # пересчёт: метрику можно улучшить, не гоняя модели заново
        r["chrf"] = chrf(r["output"], r["reference"]) if r["output"] else 0.0
    try:
        catalog = fetch_models()
    except Exception:
        catalog = None
    print(summarize(rows, catalog))


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest="command", required=True)

    p = sub.add_parser("list-models")
    p.add_argument("--grep", default="")
    p.set_defaults(func=cmd_list_models)

    p = sub.add_parser("check-key", help="проверить ключ без трат")
    p.set_defaults(func=cmd_check_key)

    p = sub.add_parser("run")
    p.add_argument("--models", required=True, help="файл: по одному id модели OpenRouter в строке")
    p.add_argument("--pair", default="he-ru", help="источник-цель: he-ru, en-ru, ar-ru …")
    p.add_argument("--corpus", choices=["ntrex", "flores"], default="ntrex")
    p.add_argument("--n", type=int, default=100)
    p.add_argument("--seed", type=int, default=1)
    p.add_argument("--workers", type=int, default=4)
    p.add_argument("--no-reasoning", action="store_true", help="попросить OpenRouter отключить размышление (если модель позволяет)")
    p.add_argument("--max-tokens", type=int, default=2048, help="как в приложении (textMaxOutputTokens)")
    p.add_argument("--data-dir", default=str(ROOT / "data"))
    p.add_argument("--out")
    p.set_defaults(func=cmd_run)

    p = sub.add_parser("retry", help="переспросить только упавшие запросы в файлах результатов")
    p.add_argument("--results", required=True, nargs="+")
    p.add_argument("--workers", type=int, default=2)
    p.add_argument("--max-tokens", type=int, default=2048)
    p.add_argument("--no-reasoning", action="store_true")
    p.set_defaults(func=cmd_retry)

    p = sub.add_parser("export-measurements", help="сводка замеров в measurements.json (для git)")
    p.add_argument("--results", required=True, nargs="+", help="порядок важен: более поздний файл заменяет ранний")
    p.add_argument("--out", default=str(ROOT / "measurements.json"))
    p.add_argument("--seed", type=int, default=1)
    p.add_argument("--reasoning-off", nargs="*", default=[], help="модели, замеренные с отключённым размышлением")
    p.set_defaults(func=cmd_export_measurements)

    p = sub.add_parser("rank", help="рейтинг «лучше» из measurements.json; --swift пишет данные для приложения")
    p.add_argument("--measurements", default=str(ROOT / "measurements.json"))
    p.add_argument("--swift")
    p.set_defaults(func=cmd_rank)

    p = sub.add_parser("report")
    p.add_argument("--results", required=True, nargs="+", help="один или несколько jsonl (объединяются)")
    p.set_defaults(func=cmd_report)

    args = parser.parse_args()
    args.func(args)


if __name__ == "__main__":
    main()
