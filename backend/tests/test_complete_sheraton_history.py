import importlib.util
from datetime import date
from pathlib import Path
import unittest


def load():
    path=Path(__file__).resolve().parents[1]/'scripts/complete_sheraton_history.py'
    assert path.exists(), 'Incremental history loader missing'
    spec=importlib.util.spec_from_file_location('complete_fixture',path)
    module=importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def test_existing_closed_days_are_preserved_and_missing_dates_are_completed():
    module=load()
    assert module.missing_days(date(2026,11,13),date(2026,11,16),{date(2026,11,13),date(2026,11,15)}) == [date(2026,11,14),date(2026,11,16)]


def test_complete_range_is_idempotent():
    module=load()
    assert module.missing_days(date(2026,11,15),date(2026,11,15),{date(2026,11,15)}) == []


def test_only_proven_demo_closed_dates_can_be_revised():
    module=load()
    fixtures=[dict(fecha=date(2026,11,11),demoproof=True,cobros=0),
              dict(fecha=date(2026,11,12),demoproof=True,cobros=2),
              dict(fecha=date(2026,11,13),demoproof=False,cobros=0),
              dict(fecha=date(2026,9,26),demoproof=True,cobros=0)]
    assert module.revisable_days(fixtures)==[date(2026,11,11),date(2026,11,12)]


def test_rotation_covers_every_presentation_weekly_without_duplicate_existing_sales():
    module=load()
    from datetime import timedelta
    menu=[dict(id_presentacion=i) for i in range(1,193)]
    monday=date(2026,11,2)
    batches=[module.rotating_menu(menu,monday+timedelta(days=i),set()) for i in range(7)]
    assert sorted(m['id_presentacion'] for batch in batches for m in batch)==list(range(1,193))
    assert all(27<=len(batch)<=28 for batch in batches)
    assert module.rotating_menu(menu,monday,{m['id_presentacion'] for m in batches[0]})==[]


def load_tests(loader, tests, pattern):
    return unittest.TestSuite(unittest.FunctionTestCase(f) for f in (
        test_existing_closed_days_are_preserved_and_missing_dates_are_completed,
        test_complete_range_is_idempotent,
        test_only_proven_demo_closed_dates_can_be_revised,
        test_rotation_covers_every_presentation_weekly_without_duplicate_existing_sales))
