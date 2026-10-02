import tempfile
import unittest
from pathlib import Path

import bench


class ChrfTests(unittest.TestCase):
    def test_identical_is_100(self):
        self.assertAlmostEqual(bench.chrf("Привет, мир!", "Привет, мир!"), 100.0, places=6)

    def test_disjoint_is_zero(self):
        self.assertEqual(bench.chrf("aaaa bbbb", "xxxx yyyy"), 0.0)

    def test_closer_translation_scores_higher(self):
        ref = "Просмотр данных карты"
        self.assertGreater(bench.chrf("Просмотр данных карты", ref), bench.chrf("Просмотр сведений о карте", ref))
        self.assertGreater(bench.chrf("Просмотр сведений о карте", ref), bench.chrf("Заказ новой карты", ref))

    def test_empty_hypothesis_is_zero_unless_both_empty(self):
        self.assertEqual(bench.chrf("", "текст"), 0.0)
        self.assertEqual(bench.chrf("", ""), 100.0)

    def test_whitespace_differences_do_not_matter_for_chars(self):
        self.assertGreater(bench.chrf("карта  счёта", "карта счёта"), 95.0)


class BootstrapTests(unittest.TestCase):
    def test_ci_contains_mean_and_is_deterministic(self):
        values = [10.0, 20.0, 30.0, 40.0, 50.0]
        low, high = bench.bootstrap_ci(values)
        self.assertLessEqual(low, 30.0)
        self.assertGreaterEqual(high, 30.0)
        self.assertEqual((low, high), bench.bootstrap_ci(values))

    def test_paired_diff_clear_gap_excludes_zero(self):
        a = [80.0 + i % 3 for i in range(60)]
        b = [60.0 + i % 3 for i in range(60)]
        mean, low, high = bench.paired_diff_ci(a, b)
        self.assertGreater(low, 0)
        self.assertAlmostEqual(mean, 20.0, places=6)

    def test_paired_diff_noise_includes_zero(self):
        a = [50.0 + (i % 5) for i in range(40)]
        b = [50.0 + ((i + 2) % 5) for i in range(40)]
        _, low, high = bench.paired_diff_ci(a, b)
        self.assertLessEqual(low, 0)
        self.assertGreaterEqual(high, 0)


class DataTests(unittest.TestCase):
    def make_corpus(self, root: Path, he_count: int = 50, ru_count: int = 50) -> None:
        folder = root / "ntrex"
        folder.mkdir()
        (folder / "newstest2019-ref.heb.txt").write_text("".join(f"שורה מספר {i} באורך סביר מאוד\n" for i in range(he_count)))
        (folder / "newstest2019-ref.rus.txt").write_text("".join(f"Строка номер {i} достаточной длины\n" for i in range(ru_count)))

    def test_load_and_sample_deterministic(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            self.make_corpus(root)
            parallel = bench.load_corpus("ntrex", root, ["he", "ru"])
            self.assertEqual(len(parallel["he"]), 50)
            first = bench.sample_indices(parallel, 10, seed=1)
            self.assertEqual(first, bench.sample_indices(parallel, 10, seed=1))
            self.assertEqual(len(first), 10)
            self.assertNotEqual(first, bench.sample_indices(parallel, 10, seed=2))

    def test_misaligned_corpora_are_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            self.make_corpus(root, he_count=50, ru_count=49)
            with self.assertRaises(SystemExit):
                bench.load_corpus("ntrex", root, ["he", "ru"])

    def test_sampling_skips_too_short_or_too_long(self):
        parallel = {"he": ["קצר", "x" * 400, "שורה באורך סביר לגמרי"], "ru": ["коротко", "y" * 400, "строка нормальной длины"]}
        self.assertEqual(bench.sample_indices(parallel, 5, seed=1), [2])

    def test_missing_file_gives_readable_error(self):
        with tempfile.TemporaryDirectory() as tmp:
            with self.assertRaises(SystemExit) as ctx:
                bench.load_corpus("ntrex", Path(tmp), ["he", "ru"])
            self.assertIn("README", str(ctx.exception))


class PromptTests(unittest.TestCase):
    def test_app_prompt_is_loaded_and_rendered(self):
        prompt = bench.render_prompt(bench.load_app_prompt(), "русский")
        self.assertIn("русский", prompt)
        self.assertNotIn("{targetLanguage}", prompt)
        self.assertNotIn("{glossarySection}", prompt)
        self.assertIn("Выводи ТОЛЬКО перевод", prompt)


class SummaryTests(unittest.TestCase):
    def row(self, model, index, chrf, ok=True, pair="he-ru"):
        return {"pair": pair, "model": model, "index": index, "chrf": chrf if ok else 0.0,
                "output": "x" if ok else "", "error": None if ok else "HTTP 429", "latency": 1.0,
                "prompt_tokens": 1, "completion_tokens": 1}

    def test_failures_are_not_counted_as_zero_quality(self):
        rows = [self.row("a", i, 50.0) for i in range(10)]
        rows += [self.row("b", i, 50.0, ok=(i >= 1)) for i in range(10)]  # 1 сбой из 10
        text = bench.summarize(rows)
        self.assertIn("50.0", text)
        self.assertNotIn("хуже", text)

    def test_model_with_mostly_failures_is_not_evaluated(self):
        rows = [self.row("a", i, 50.0) for i in range(10)]
        rows += [self.row("b", i, 90.0, ok=(i < 3)) for i in range(10)]
        text = bench.summarize(rows)
        self.assertIn("не оценивается", text)
        self.assertIn("3/10", text)

    def test_paired_comparison_uses_common_sentences_only(self):
        rows = [self.row("a", i, 60.0) for i in range(30)]
        rows += [self.row("b", i, 40.0, ok=(i % 10 != 0)) for i in range(30)]
        self.assertIn("хуже на 20.0", bench.summarize(rows))


if __name__ == "__main__":
    unittest.main()
