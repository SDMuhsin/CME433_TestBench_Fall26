"""Shared fixtures: every legal (canonical) FP16 bit pattern."""
import numpy as np
import pytest

from src.golden.arith.fp import canon16, value


@pytest.fixture(scope='session')
def legal16():
    """-> (bits, float64 values) of all canonical FP16 codes."""
    b = np.arange(65536, dtype=np.uint32).astype(np.uint16)
    b = b[canon16(b) == b]
    return b, value(b).astype(np.float64)
