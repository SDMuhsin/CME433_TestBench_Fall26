"""Image-quality metrics of RTL output against a reference, on the uint8 pixel scale (0..255)."""
import numpy as np


def psnr(mse):
    return float('inf') if mse == 0 else float(10 * np.log10(255.0 ** 2 / mse))


def compare(got, ref):
    """got, ref: uint8-valued int arrays [N, 784] -> dict of match / error statistics."""
    d = got.astype(np.int64) - ref.astype(np.int64)
    per_img_mse = (d ** 2).mean(1)
    per_img_psnr = np.array([psnr(m) for m in per_img_mse])
    return dict(
        images=int(len(got)),
        bitexact_images=int((d == 0).all(1).sum()),
        pixels_match=int((d == 0).sum()),
        pixels=int(d.size),
        mae=float(np.abs(d).mean()),
        max_abs=int(np.abs(d).max()),
        psnr_db=psnr(float((d ** 2).mean())),                 # over all pixels of all images
        psnr_min_db=float(per_img_psnr.min()),                # worst single image
        psnr_median_db=float(np.median(per_img_psnr)),
    )
