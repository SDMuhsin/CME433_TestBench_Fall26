"""Python model of a multiplier variant for emulating the chip (golden/model.py `mul`):
  width 8  : the exhaustive 256 x 256 product table of the variant's RTL (mul_table.py)
  width 16 : mb:<design> -> the design's numpy model (approx/mulbench.py, RTL == model is checked
             by approx/mulbench_check); other 16-bit variants have no model (None)
exact -> None (the golden model's own exact product)."""
import numpy as np

from .mul_table import mul8_table


def mul_model(variant, width, work):
    if variant == 'exact':
        return None
    if width == 8:
        return mul8_table(variant, work)
    if variant.startswith('mb:'):
        from ..approx.mulbench import designs
        products = designs(width)[variant[3:]].model.products

        def mul(a, b):                                # the models flatten; keep the operand shape
            a, b = np.broadcast_arrays(np.asarray(a, np.int64), np.asarray(b, np.int64))
            return np.asarray(products(a.ravel(), b.ravel()), np.int64).reshape(a.shape)
        return mul
    return None
