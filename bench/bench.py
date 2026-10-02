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


def summarize(rows: list[dict], models_info: dict[str, dict] | None = None) -> str:
    """Таблица по (пара, модель). Качество считается только по удавшимся
    ответам (сбой — это недоступность, а не плохой перевод); сравнение с
    лидером — на предложениях, удавшихся у обеих моделей. Модель, у которой
    удалось меньше 80% запросов, не оценивается."""
    out: list[str] = []
    for pair in sorted({r["pair"] for r in rows}):
        by_model: dict[str, list[dict]] = {}
        for r in rows:
            if r["pair"] == pair:
                by_model.setdefault(r["model"], []).append(r)
        total = max(len(rs) for rs in by_model.values())
        ok_scores = {m: {r["index"]: r["chrf"] for r in rs if is_ok(r)} for m, rs in by_model.items()}
        rate = {m: len(ok_scores[m]) / max(len(by_model[m]), 1) for m in by_model}
        evaluable = [m for m in by_model if rate[m] >= MIN_SUCCESS_RATE]
        ranked = sorted(evaluable, key=lambda m: -statistics.fmean(ok_scores[m].values())) + \
            sorted((m for m in by_model if m not in evaluable), key=lambda m: -rate[m])
        best = ranked[0] if evaluable else None
        out.append(f"\n### {pair}  (предложений: {total})\n")
        out.append("| Модель | chrF++ | 95% ДИ | vs лидер | удачных | задержка, с | $/1000 предл. |")
        out.append("|---|---|---|---|---|---|---|")
        for m in ranked:
            rs = by_model[m]
            ok_count = len(ok_scores[m])
            if m not in evaluable:
                mean_text, ci_text, verdict = "—", "—", "не оценивается (сбои)"
            else:
                values = list(ok_scores[m].values())
                mean_text = f"{statistics.fmean(values):.1f}"
                low, high = bootstrap_ci(values)
                ci_text = f"{low:.1f}–{high:.1f}"
                if m == best:
                    verdict = "лидер"
                else:
                    common = sorted(set(ok_scores[best]) & set(ok_scores[m]))
                    diff, low_diff, _ = paired_diff_ci([ok_scores[best][i] for i in common], [ok_scores[m][i] for i in common])
                    # значимо, только если весь интервал разницы выше нуля
                    verdict = f"хуже на {diff:.1f}" if low_diff > 0 else "≈ лучшая (в шуме)"
            latency_values = [r["latency"] for r in rs if is_ok(r)] or [r["latency"] for r in rs]
            cost = cost_per_1000(rs, (models_info or {}).get(m))
            out.append(
                f"| `{m}` | {mean_text} | {ci_text} | {verdict} | {ok_count}/{len(rs)} | "
                f"{statistics.median(latency_values):.1f} | {cost} |"
            )
    return "\n".join(out)


def cost_per_1000(rows: list[dict], info: dict | None) -> str:
    if not info:
        return "—"
    pricing = info.get("pricing") or {}
    try:
        price_in, price_out = float(pricing["prompt"]), float(pricing["completion"])
    except (KeyError, TypeError, ValueError):
        return "—"
    spent = sum((r["prompt_tokens"] or 0) * price_in + (r["completion_tokens"] or 0) * price_out for r in rows)
    return f"{spent / max(len(rows), 1) * 1000:.3f}"


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


def cmd_report(args: argparse.Namespace) -> None:
    rows = [
        json.loads(l)
        for path in args.results
        for l in Path(path).read_text(encoding="utf-8").splitlines() if l.strip()
    ]
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

    p = sub.add_parser("report")
    p.add_argument("--results", required=True, nargs="+", help="один или несколько jsonl (объединяются)")
    p.set_defaults(func=cmd_report)

    args = parser.parse_args()
    args.func(args)


if __name__ == "__main__":
    main()
