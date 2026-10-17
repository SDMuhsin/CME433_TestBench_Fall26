"""Small Fashion-MNIST CNN used to label generated images (weights: fmnist_cnn.npz)."""
from pathlib import Path

import numpy as np
import torch
from torch import nn

WEIGHTS = Path(__file__).resolve().parent / 'fmnist_cnn.npz'
CLASSES = ('T-shirt/top', 'Trouser', 'Pullover', 'Dress', 'Coat',
           'Sandal', 'Shirt', 'Sneaker', 'Bag', 'Ankle boot')


def make_net():
    """Input [N, 1, 28, 28] in [0, 1] (0 = background) -> logits [N, 10]."""
    return nn.Sequential(
        nn.Conv2d(1, 32, 3, padding=1), nn.ReLU(), nn.MaxPool2d(2),
        nn.Conv2d(32, 64, 3, padding=1), nn.ReLU(), nn.MaxPool2d(2),
        nn.Flatten(), nn.Dropout(0.3), nn.Linear(64 * 7 * 7, 128), nn.ReLU(), nn.Linear(128, 10))


def save(net, path=WEIGHTS):
    np.savez(path, **{k: v.detach().cpu().numpy() for k, v in net.state_dict().items()})


def load(path=WEIGHTS):
    net = make_net()
    with np.load(path) as f:
        net.load_state_dict({k: torch.from_numpy(f[k]) for k in f.files})
    return net.eval()


def predict(pixels_u8, net=None):
    """uint8 images [N, 784] (0..255) -> (labels [N], softmax probabilities [N, 10])."""
    net = net or load()
    x = torch.from_numpy(np.asarray(pixels_u8, np.float32).reshape(-1, 1, 28, 28) / 255.0)
    with torch.no_grad():
        p = torch.softmax(net(x), 1).numpy()
    return p.argmax(1), p
