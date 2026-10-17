# Tool environment for the gan65 flow on the server (tcsh). The caller sets GAN65 (the
# src_gan_tsmc65 directory of the repository clone). The kit and tool setup are shared with
# the INT8 65 nm flow: MQ65 points at src_int8_tsmc65, whose git-ignored site config
# (site/site.tcl, site/site.csh) and generic helpers (libraries, summary, SDC) are reused.
setenv MQ65 $GAN65:h/src_int8_tsmc65
source $MQ65/syn/common/env.csh
