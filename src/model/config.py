"""Model hyper-parameters shared by training, export and the golden model."""
from dataclasses import asdict, dataclass

EPS = 2.0 ** -12  # RMSNorm epsilon; hardware: acc init 2^-6, then the mean scale 2^-6


@dataclass(frozen=True)
class ModelConfig:
    vocab: int = 128
    d_model: int = 64
    n_layer: int = 2
    d_inner: int = 64
    d_state: int = 4
    dt_rank: int = 4

    @property
    def n_xproj(self):
        """x_proj outputs: dt_low (dt_rank), B (d_state), C (d_state)."""
        return self.dt_rank + 2 * self.d_state

    def to_dict(self):
        return asdict(self)
