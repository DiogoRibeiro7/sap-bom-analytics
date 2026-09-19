"""Reference mathematics for Bill of Materials quantity propagation."""

from __future__ import annotations

from collections.abc import Iterable
from dataclasses import dataclass
from decimal import Decimal


@dataclass(frozen=True, slots=True)
class BomQuantityStep:
    """One BOM edge expressed as component quantity per parent base quantity."""

    quantity: Decimal
    base_quantity: Decimal

    def __post_init__(self) -> None:
        """Validate mathematically meaningful BOM quantities."""
        if self.quantity < 0:
            raise ValueError("quantity must be non-negative")
        if self.base_quantity <= 0:
            raise ValueError("base_quantity must be positive")


def edge_factor(step: BomQuantityStep) -> Decimal:
    """Return the multiplicative quantity contribution of one BOM edge."""
    if not isinstance(step, BomQuantityStep):
        raise TypeError("step must be a BomQuantityStep")
    return step.quantity / step.base_quantity


def cumulative_quantity(steps: Iterable[BomQuantityStep]) -> Decimal:
    """Return cumulative quantity across a sequence of BOM edges."""
    result = Decimal(1)
    for step in steps:
        result *= edge_factor(step)
    return result


def would_create_cycle(path: tuple[int, ...], next_material_id: int) -> bool:
    """Return whether appending a material would create a cycle in a BOM path."""
    if not isinstance(path, tuple) or not all(isinstance(value, int) for value in path):
        raise TypeError("path must be a tuple of integers")
    if not isinstance(next_material_id, int) or isinstance(next_material_id, bool):
        raise TypeError("next_material_id must be an int")
    return next_material_id in path
