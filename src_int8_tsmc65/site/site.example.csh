# Site tool environment template (tcsh). Copy to site/site.csh (git-ignored) and fill in.
# Sourced by syn/common/env.csh: set up Synopsys DC, PrimeTime / PrimePower, VCS and
# Formality, and point MQ65_KIT at the root of the standard-cell kit.
source <TOOL_SETUP_SCRIPT_DC>
source <TOOL_SETUP_SCRIPT_PT>
source <TOOL_SETUP_SCRIPT_VCS>
source <TOOL_SETUP_SCRIPT_FM>
setenv MQ65_KIT <STDCELL_KIT_ROOT>
setenv MQ65_VLOG <STDCELL_VERILOG_MODELS>      # cell simulation models (gate-level simulation)
