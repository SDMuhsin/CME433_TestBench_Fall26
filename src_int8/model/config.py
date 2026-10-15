"""Model hyper-parameters shared by training, QAT, export and the golden model."""
from dataclasses import asdict, dataclass

EPS = 2.0 ** -12  # RMSNorm epsilon; hardware: accumulator init 16 in Q.16


@dataclass(frozen=True)
class ModelConfig:
    vocab: int = 128
    d_model: int = 64
    n_layer: int = 2
    d_inner: int = 96
    d_state: int = 4
    dt_rank: int = 4

    @property
    def n_xproj(self):
        """x_proj outputs: dt_low (dt_rank), B (d_state), C (d_state)."""
        return self.dt_rank + 2 * self.d_state

    def to_dict(self):
        return asdict(self)
