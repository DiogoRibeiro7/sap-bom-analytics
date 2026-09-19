"""Property-based tests for BOM quantity propagation and cycle invariants."""

from __future__ import annotations

from decimal import Decimal

from hypothesis import given
from hypothesis import strategies as st

from sap_bom_analytics.bom_math import (
    BomQuantityStep,
    cumulative_quantity,
    edge_factor,
    would_create_cycle,
)

_positive = st.integers(min_value=1, max_value=10_000).map(Decimal)
_non_negative = st.integers(min_value=0, max_value=10_000).map(Decimal)


@st.composite
def bom_steps(draw: st.DrawFn) -> BomQuantityStep:
    """Generate one valid BOM quantity step."""
    return BomQuantityStep(
        quantity=draw(_non_negative),
        base_quantity=draw(_positive),
    )


@given(st.lists(bom_steps(), min_size=0, max_size=12))
def test_cumulative_quantity_is_product_of_edge_factors(
    steps: list[BomQuantityStep],
) -> None:
    """Recursive propagation must equal the product of edge ratios."""
    expected = Decimal(1)
    for step in steps:
        expected *= step.quantity / step.base_quantity

    assert cumulative_quantity(steps) == expected


@given(st.lists(bom_steps(), min_size=0, max_size=8), st.lists(bom_steps(), min_size=0, max_size=8))
def test_path_concatenation_is_multiplicative(
    left: list[BomQuantityStep],
    right: list[BomQuantityStep],
) -> None:
    """Splitting and rejoining a BOM path must preserve cumulative quantity."""
    assert cumulative_quantity(left + right) == (
        cumulative_quantity(left) * cumulative_quantity(right)
    )


@given(bom_steps(), _positive)
def test_edge_factor_is_invariant_to_common_scale(
    step: BomQuantityStep,
    scale: Decimal,
) -> None:
    """Scaling quantity and base quantity together must not change the ratio."""
    scaled = BomQuantityStep(
        quantity=step.quantity * scale,
        base_quantity=step.base_quantity * scale,
    )
    assert edge_factor(scaled) == edge_factor(step)


@given(
    st.lists(st.integers(min_value=1, max_value=100_000), unique=True, max_size=20),
    st.integers(min_value=1, max_value=100_000),
)
def test_cycle_detection_is_exact(path_values: list[int], next_material_id: int) -> None:
    """Cycle detection is equivalent to membership in the current material path."""
    path = tuple(path_values)
    assert would_create_cycle(path, next_material_id) is (next_material_id in path)
