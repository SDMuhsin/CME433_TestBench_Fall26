"""Fixed locations inside the repository."""
from pathlib import Path

T65 = Path(__file__).resolve().parents[1]          # src_gan_tsmc65/
ROOT = T65.parent                                   # repository root
RTL = T65 / 'rtl'
MODEL = T65 / 'model' / 'fmnist'                    # int8 Fashion-MNIST generator + CSRs
CLASSIFIER = T65 / 'classifier'
BUILD = ROOT / 'build' / 'gan65'                    # all generated outputs (git-ignored)


def model_dir(width=8):
    """Quantised generator of a datapath width: model/fmnist (INT8), model/fmnist_w16 (INT16)."""
    return MODEL if int(width) == 8 else T65 / 'model' / f'fmnist_w{int(width)}'


if __name__ == '__main__':                          # python3 -m src_gan_tsmc65.common.paths --model-dir W
    import sys
    if len(sys.argv) != 3 or sys.argv[1] != '--model-dir' or not model_dir(sys.argv[2]).is_dir():
        raise SystemExit('usage: --model-dir <existing width>')
    print(model_dir(sys.argv[2]))
