"""Float reference of the byte-level Mamba LM (tied embedding, pre-RMSNorm residual blocks)."""
import math

import torch
import torch.nn as nn
import torch.nn.functional as F

from ..config import EPS
from .scan import selective_scan


class RMSNorm(nn.Module):
    def __init__(self, d):
        super().__init__()
        self.weight = nn.Parameter(torch.ones(d))

    def forward(self, x):
        return x * torch.rsqrt(x.pow(2).mean(-1, keepdim=True) + EPS) * self.weight


class MambaBlock(nn.Module):
    """Pre-norm Mamba mixer with residual: x + out_proj(scan(silu(conv(in_x))) * silu(in_z))."""

    def __init__(self, cfg):
        super().__init__()
        E, N, R = cfg.d_inner, cfg.d_state, cfg.dt_rank
        self.cfg = cfg
        self.norm = RMSNorm(cfg.d_model)
        self.in_proj = nn.Linear(cfg.d_model, 2 * E, bias=False)
        self.conv_w = nn.Parameter(torch.empty(E, 2).uniform_(-0.5, 0.5))  # [:,0] prev, [:,1] cur
        self.conv_b = nn.Parameter(torch.zeros(E))
        self.x_proj = nn.Linear(E, cfg.n_xproj, bias=False)
        self.dt_proj = nn.Linear(R, E)
        self.A_log = nn.Parameter(torch.log(torch.arange(1, N + 1).float()).repeat(E, 1))
        self.D = nn.Parameter(torch.ones(E))
        self.out_proj = nn.Linear(E, cfg.d_model, bias=False)
        self._init_dt()

    def _init_dt(self, lo=1e-3, hi=1e-1):
        dt = torch.exp(torch.rand(self.cfg.d_inner) * (math.log(hi) - math.log(lo)) + math.log(lo))
        with torch.no_grad():
            self.dt_proj.bias.copy_(dt + torch.log(-torch.expm1(-dt)))  # inverse softplus
            nn.init.uniform_(self.dt_proj.weight, -self.cfg.dt_rank ** -0.5, self.cfg.dt_rank ** -0.5)

    def forward(self, x):
        R, N = self.cfg.dt_rank, self.cfg.d_state
        xi, z = self.in_proj(self.norm(x)).chunk(2, -1)
        prev = F.pad(xi, (0, 0, 1, 0))[:, :-1]
        u = F.silu(self.conv_b + self.conv_w[:, 0] * prev + self.conv_w[:, 1] * xi)
        dt_low, B, C = self.x_proj(u).split([R, N, N], -1)
        dt = F.softplus(self.dt_proj(dt_low))
        y = selective_scan(u, dt, -torch.exp(self.A_log), B, C) + self.D * u
        return x + self.out_proj(y * F.silu(z))


class MambaLM(nn.Module):
    def __init__(self, cfg):
        super().__init__()
        self.cfg = cfg
        self.embed = nn.Embedding(cfg.vocab, cfg.d_model)
        nn.init.normal_(self.embed.weight, std=0.1)
        self.blocks = nn.ModuleList(MambaBlock(cfg) for _ in range(cfg.n_layer))
        self.norm_f = RMSNorm(cfg.d_model)

    def forward(self, tokens):
        x = self.embed(tokens)
        for blk in self.blocks:
            x = blk(x)
        return self.norm_f(x) @ self.embed.weight.t()
