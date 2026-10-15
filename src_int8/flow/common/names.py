"""Verilog/SDF/SAIF name helpers shared by the SDF GLS and power scripts."""
import re


def norm(name):
    """netlist/VCD identifier -> plain name (escaped `\\a.b[3] ` -> `a.b[3]`)"""
    name = name.strip()
    return name[1:].strip() if name.startswith("\\") else name


def legal_name(name):
    """escaped instance name -> plain identifier (the SDF GLS netlist copy and its SDF)"""
    return re.sub(r"\W", "_", name)


def saif_id(name):
    """SAIF identifier for OpenSTA: escape the bus brackets only ('.' is part of the flat names
    and is not the divider; escaping it breaks the instance lookup)"""
    return re.sub(r"([\[\]])", r"\\\1", name)
