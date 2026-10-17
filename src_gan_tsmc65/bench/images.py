"""Image dumps: int8 chip pixels -> uint8, .npy arrays and PNG grids."""
import numpy as np
from PIL import Image


def to_u8(pix_i8):
    """int8 pixel (pu - 128, as read back from the chip) -> uint8 grey level pu."""
    return (np.asarray(pix_i8, np.int64) + 128).astype(np.uint8)


def save_grid(path, u8, cols=16, scale=2, pad=2):
    """Write images u8 [N, 784] as a cols-wide grid PNG."""
    n = len(u8)
    rows = (n + cols - 1) // cols
    cell = 28 + pad
    canvas = np.full((rows * cell + pad, cols * cell + pad), 64, np.uint8)
    for i, im in enumerate(u8):
        r, c = divmod(i, cols)
        canvas[pad + r * cell:pad + r * cell + 28, pad + c * cell:pad + c * cell + 28] = im.reshape(28, 28)
    Image.fromarray(canvas).resize((canvas.shape[1] * scale, canvas.shape[0] * scale), Image.NEAREST).save(path)
