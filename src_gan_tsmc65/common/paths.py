"""Fixed locations inside the repository."""
from pathlib import Path

T65 = Path(__file__).resolve().parents[1]          # src_gan_tsmc65/
ROOT = T65.parent                                   # repository root
RTL = T65 / 'rtl'
MODEL = T65 / 'model' / 'fmnist'                    # int8 Fashion-MNIST generator + CSRs
CLASSIFIER = T65 / 'classifier'
BUILD = ROOT / 'build' / 'gan65'                    # all generated outputs (git-ignored)
