// sram_sdf.v -- SDF-GLS copy of gf180mcu_ocd_ip_sram__sram256x8m8wm1/gf180mcu_ocd_ip_sram__sram256x8m8wm1.v
// (vendor file sha256 5b6a3033d4b36147..., Open Circuit Design rev 0.0).  Changes, all in the
// specify block (behaviour, notifier handling and path structure unchanged):
//  1. specparams: the vendor values are the 5 V fd_ip_sram ones ("needs to be revised for the 3.3V
//     version"): Tcyc 55.6 ns and Tckh/Tckl 25 ns would flag every cycle of the 40 ns / 50 % clock,
//     ta = 45 ns exceeds the period.  They are replaced by the 3.3 V Liberty (tt_025C_3v30) values;
//     the SDF overrides every one of them per instance and corner anyway (checks/sdf_coverage.py checks).
//  2. CEN setup/hold: the vendor checks are qualified by cen_flag (= operational & CEN low) at the
//     clock edge.  A CEN FALLING within the hold window after an edge where CEN was high (an access
//     starting too early) or RISING within the setup window before an edge (an access ending too
//     late) is then never checked -- exactly the SRAM CEN hold paths that needed repair in this
//     design.  The Liberty/STA checks CEN unconditionally, so here they are qualified only by
//     cen_fell (memory operational, i.e. after the first CEN 1->0 since time 0).
//  3. the internal read/write strobe delay Tdly (100 ps) was a specparam used in procedural code,
//     which CVC rejects ("variable Tdly not declared"); it is the localparam TDLY = 100 here.
//  4. the violation-message block polls the notifiers at negedge clk_dly instead of waiting on
//     them (CVC compiled-code crash, see the comment at the block).  Notifier effects unchanged.
//  5. +define+MQ_TCHK_PROBE (margin-probe runs only) disables the notifier effects.
//  6. all inputs are copied by continuous assigns into *_d nets used by the behaviour (CVC MIPD
//     issue, see note 6 at the declarations).
// Writes keep Q ("Hold previous data", specs/2_truth_table.csv); the src/rtl/mem behavioural model
// reloads Q with the old word on a write.  The SDF GLS therefore also checks that the design never
// uses Q after a write cycle.
/*
 *
 * Copyright 2025 Open Circuit Design, LLC
 * Licensed under the Apache License, Version 2.0 (the "License");
 * Based on work done by the GlobalFoundries PDK Authors.
 * Original copyright notice is below.
 *
 * Currently, this is a copy of gf180mcu_fd_ip_sram__sram256x8m8wm1.
 * Timing (in the "specify" blocks) needs to be revised for the
 * 3.3V version.
 *
 * Project:             018 3.3V SRAM
 * Author:              Open Circuit Design, LLC
 * Data Created:        November 18, 2025
 * Revision:		0.0
 *
 * Description:         gf180mcu_ocd_ip_sram__sram256x8m8wm1 Simulation Model
 */

/*
 * $Id: $
 * Copyright 2022 GlobalFoundries PDK Authors
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http:www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 *
 * Project:             018 5VGREEN SRAM
 * Author:              GlobalFoundries PDK Authors
 * Data Created:        05-06-2014
 * Revision:		0.0	
 *
 * Description:         gf180mcu_ocd_ip_sram__sram256x8m8wm1 Simulation Model
 */

`timescale 1 ps / 1 ps

module gf180mcu_ocd_ip_sram__sram256x8m8wm1 (
`ifdef USE_POWER_PINS
	VDD,
	VSS,
`endif
	CLK,
	CEN,
	GWEN,
	WEN,
	A,
	D,
	Q
);

input           CLK;
input           CEN;    //Chip Enable Negative
input           GWEN;   //Global Write Enable Negative
input   [7:0]  	WEN;    //Write Enable Negative
input   [7:0]   A;
input   [7:0]  	D;
output	[7:0]	Q;
`ifdef USE_POWER_PINS
inout		VDD;
inout		VSS;
`endif

// note 6: every input reaches the behaviour through a continuous assign (CLK_d, CEN_d, ... A_d):
// CVC applies the SDF INTERCONNECT (MIPD) of a port to gates and continuous assigns but not to
// procedural event controls / reads, so the vendor `always @(posedge CLK)` fired at the undelayed
// edge and the CLK->Q path delay was lost.  (`buf b_a [7:0] (A_d, A)` instance arrays are NOT
// usable: with MIPDs on the bits CVC drove A_d[5] wrong in SRAM 9 -- silent wrong reads.)
// The specify block (checks, paths) still uses the ports.
wire       CLK_d, CEN_d, GWEN_d;
wire [7:0] WEN_d, A_d, D_d;
assign CLK_d = CLK;
assign CEN_d = CEN;
assign GWEN_d = GWEN;
assign WEN_d = WEN;
assign A_d = A;
assign D_d = D;

reg	[7:0]	mem[255:0];
reg	[7:0]	qo_reg;

wire		cen_flag;
wire		write_flag;
wire		read_flag;

reg             ntf_Tcyc;	//notifier for clock period/low/high pulse
reg             ntf_Tckh;
reg             ntf_Tckl;

reg		ntf_tcs;	//notifier for setup time
reg		ntf_tas;
reg		ntf_tds;
reg		ntf_tws;
reg		ntf_twis;

reg             ntf_tch;	//notifier for hold time
reg             ntf_tah;
reg             ntf_tdh;
reg             ntf_twh;
reg             ntf_twih;

wire		no_st_viol;	//no setup violation
wire		no_hd_viol;	//no hold violation
wire		no_ck_viol;	//no clock related violation

reg             clk_dly;        //for read/write
reg             write_flag_dly; //for write invalidation
reg             read_flag_dly;  //for read invalidation
reg             cen_dly;
reg             cen_fell;       //detect CEN 1 -> 0 transition
reg             cen_not_rst;    //detect CEN is not reset initially

wire    [7:0]  we;       	//inversion of WEN
wire    [7:0]  cd2;
wire    [7:0]  cd4;
wire    [7:0]  cd5;
reg    	[7:0]  cdx;

reg	[7:0]	marked_a;

integer         i;

assign Q = qo_reg;

//---- for debugging
wire    [7:0]  mem_0;
wire	[7:0]  mem_1;
wire	[7:0]  mem_2;
wire	[7:0]  mem_3;
assign mem_0 = mem[0];
assign mem_1 = mem[1];
assign mem_2 = mem[2];
assign mem_3 = mem[3];

always @(CEN_d) cen_dly = #100 CEN_d;

always @(CEN_d or cen_dly) begin
  if (!CEN_d & cen_dly) cen_fell = 1'b1;
end

always @(posedge CLK_d) begin
  if (!CEN_d & !cen_fell & !cen_not_rst) cen_not_rst = 1;
end

always @(posedge cen_not_rst) begin
  $display("-------- WARNING: CEN is not reset, memory is not operational ---------");
  $display("-------- @Time %0t: scope = %m", $realtime, " ---------");
end

always @(posedge cen_fell) begin
  $display("-------- MESSAGE: CEN is just reset, memory is operational ---------");
  $display("-------- @Time %0t: scope = %m", $realtime, " ---------");
end

assign cen_flag   =  cen_fell & !CEN_d;
assign write_flag =  cen_fell & !CEN_d & !GWEN_d & !(&WEN_d);
assign read_flag  =  cen_fell & !CEN_d &  GWEN_d;

localparam TDLY = 100;           // was the specparam Tdly (used outside specify, see note 3)
reg cen_flag_dly;
always @(cen_flag) cen_flag_dly = #100 cen_flag;

specify
  // Liberty tt_025C_3v30 (ps); overridden per instance by the SDF
  specparam Tcyc = 8560;
  specparam Tckh = 3287;
  specparam Tckl = 3891;

  specparam tcs  = 581;
  specparam tas  = 882;
  specparam tds  = 662;
  specparam tws  = 781;
  specparam twis = 331;

  specparam tch  = 1779;
  specparam tah  = 887;
  specparam tdh  = 938;
  specparam twh  = 1193;
  specparam twih = 1176;

  specparam ta   = 6874;

  specparam Tdly  = 100 : 100: 100;

//---- CLK period/pulse timing
  $period (negedge CLK, Tcyc, ntf_Tcyc);
  $width  (posedge CLK, Tckh, 0, ntf_Tckh);
  $width  (negedge CLK, Tckl, 0, ntf_Tckl);

//---- CEN setup/hold timing
  // unconditional once operational (vendor: &&& cen_flag / cen_flag_dly, see header note 2)
  $setup (negedge CEN, posedge CLK &&& cen_fell, tcs, ntf_tcs);
  $setup (posedge CEN, posedge CLK &&& cen_fell, tcs, ntf_tcs);

  $hold  (posedge CLK &&& cen_fell, posedge CEN, tch, ntf_tch);
  $hold  (posedge CLK &&& cen_fell, negedge CEN, tch, ntf_tch);

//---- GWEN setup/hold timing
  $setup (negedge GWEN,  posedge CLK &&& cen_flag, tws, ntf_tws);
  $setup (posedge GWEN,  posedge CLK &&& cen_flag, tws, ntf_tws);

  $hold  (posedge CLK &&& cen_flag, posedge GWEN, twh, ntf_twh);
  $hold  (posedge CLK &&& cen_flag, negedge GWEN, twh, ntf_twh);

//---- WEN[7:0] setup/hold timing
  $setup (negedge WEN[0],  posedge CLK &&& write_flag, twis, ntf_twis);
  $setup (negedge WEN[1],  posedge CLK &&& write_flag, twis, ntf_twis);
  $setup (negedge WEN[2],  posedge CLK &&& write_flag, twis, ntf_twis);
  $setup (negedge WEN[3],  posedge CLK &&& write_flag, twis, ntf_twis);
  $setup (negedge WEN[4],  posedge CLK &&& write_flag, twis, ntf_twis);
  $setup (negedge WEN[5],  posedge CLK &&& write_flag, twis, ntf_twis);
  $setup (negedge WEN[6],  posedge CLK &&& write_flag, twis, ntf_twis);
  $setup (negedge WEN[7],  posedge CLK &&& write_flag, twis, ntf_twis);

  $setup (posedge WEN[0],  posedge CLK &&& write_flag, twis, ntf_twis);
  $setup (posedge WEN[1],  posedge CLK &&& write_flag, twis, ntf_twis);
  $setup (posedge WEN[2],  posedge CLK &&& write_flag, twis, ntf_twis);
  $setup (posedge WEN[3],  posedge CLK &&& write_flag, twis, ntf_twis);
  $setup (posedge WEN[4],  posedge CLK &&& write_flag, twis, ntf_twis);
  $setup (posedge WEN[5],  posedge CLK &&& write_flag, twis, ntf_twis);
  $setup (posedge WEN[6],  posedge CLK &&& write_flag, twis, ntf_twis);
  $setup (posedge WEN[7],  posedge CLK &&& write_flag, twis, ntf_twis);

  $hold  (posedge CLK &&& write_flag, posedge WEN[0],  twih, ntf_twih);
  $hold  (posedge CLK &&& write_flag, posedge WEN[1],  twih, ntf_twih);
  $hold  (posedge CLK &&& write_flag, posedge WEN[2],  twih, ntf_twih);
  $hold  (posedge CLK &&& write_flag, posedge WEN[3],  twih, ntf_twih);
  $hold  (posedge CLK &&& write_flag, posedge WEN[4],  twih, ntf_twih);
  $hold  (posedge CLK &&& write_flag, posedge WEN[5],  twih, ntf_twih);
  $hold  (posedge CLK &&& write_flag, posedge WEN[6],  twih, ntf_twih);
  $hold  (posedge CLK &&& write_flag, posedge WEN[7],  twih, ntf_twih);

  $hold  (posedge CLK &&& write_flag, negedge WEN[0],  twih, ntf_twih);
  $hold  (posedge CLK &&& write_flag, negedge WEN[1],  twih, ntf_twih);
  $hold  (posedge CLK &&& write_flag, negedge WEN[2],  twih, ntf_twih);
  $hold  (posedge CLK &&& write_flag, negedge WEN[3],  twih, ntf_twih);
  $hold  (posedge CLK &&& write_flag, negedge WEN[4],  twih, ntf_twih);
  $hold  (posedge CLK &&& write_flag, negedge WEN[5],  twih, ntf_twih);
  $hold  (posedge CLK &&& write_flag, negedge WEN[6],  twih, ntf_twih);
  $hold  (posedge CLK &&& write_flag, negedge WEN[7],  twih, ntf_twih);

//---- A[7:0] setup/hold timing
  $setup (posedge A[0],  posedge CLK &&& cen_flag, tas, ntf_tas);
  $setup (posedge A[1],  posedge CLK &&& cen_flag, tas, ntf_tas);
  $setup (posedge A[2],  posedge CLK &&& cen_flag, tas, ntf_tas);
  $setup (posedge A[3],  posedge CLK &&& cen_flag, tas, ntf_tas);
  $setup (posedge A[4],  posedge CLK &&& cen_flag, tas, ntf_tas);
  $setup (posedge A[5],  posedge CLK &&& cen_flag, tas, ntf_tas);
  $setup (posedge A[6],  posedge CLK &&& cen_flag, tas, ntf_tas);
  $setup (posedge A[7],  posedge CLK &&& cen_flag, tas, ntf_tas);

  $setup (negedge A[0],  posedge CLK &&& cen_flag, tas, ntf_tas);
  $setup (negedge A[1],  posedge CLK &&& cen_flag, tas, ntf_tas);
  $setup (negedge A[2],  posedge CLK &&& cen_flag, tas, ntf_tas);
  $setup (negedge A[3],  posedge CLK &&& cen_flag, tas, ntf_tas);
  $setup (negedge A[4],  posedge CLK &&& cen_flag, tas, ntf_tas);
  $setup (negedge A[5],  posedge CLK &&& cen_flag, tas, ntf_tas);
  $setup (negedge A[6],  posedge CLK &&& cen_flag, tas, ntf_tas);
  $setup (negedge A[7],  posedge CLK &&& cen_flag, tas, ntf_tas);

  $hold  (posedge CLK &&& cen_flag, negedge A[0],  tah, ntf_tah);
  $hold  (posedge CLK &&& cen_flag, negedge A[1],  tah, ntf_tah);
  $hold  (posedge CLK &&& cen_flag, negedge A[2],  tah, ntf_tah);
  $hold  (posedge CLK &&& cen_flag, negedge A[3],  tah, ntf_tah);
  $hold  (posedge CLK &&& cen_flag, negedge A[4],  tah, ntf_tah);
  $hold  (posedge CLK &&& cen_flag, negedge A[5],  tah, ntf_tah);
  $hold  (posedge CLK &&& cen_flag, negedge A[6],  tah, ntf_tah);
  $hold  (posedge CLK &&& cen_flag, negedge A[7],  tah, ntf_tah);

  $hold  (posedge CLK &&& cen_flag, posedge A[0],  tah, ntf_tah);
  $hold  (posedge CLK &&& cen_flag, posedge A[1],  tah, ntf_tah);
  $hold  (posedge CLK &&& cen_flag, posedge A[2],  tah, ntf_tah);
  $hold  (posedge CLK &&& cen_flag, posedge A[3],  tah, ntf_tah);
  $hold  (posedge CLK &&& cen_flag, posedge A[4],  tah, ntf_tah);
  $hold  (posedge CLK &&& cen_flag, posedge A[5],  tah, ntf_tah);
  $hold  (posedge CLK &&& cen_flag, posedge A[6],  tah, ntf_tah);
  $hold  (posedge CLK &&& cen_flag, posedge A[7],  tah, ntf_tah);

//---- D[7:0] setup/hold timing
  $setup (posedge D[0],  posedge CLK &&& write_flag, tds, ntf_tds);
  $setup (posedge D[1],  posedge CLK &&& write_flag, tds, ntf_tds);
  $setup (posedge D[2],  posedge CLK &&& write_flag, tds, ntf_tds);
  $setup (posedge D[3],  posedge CLK &&& write_flag, tds, ntf_tds);
  $setup (posedge D[4],  posedge CLK &&& write_flag, tds, ntf_tds);
  $setup (posedge D[5],  posedge CLK &&& write_flag, tds, ntf_tds);
  $setup (posedge D[6],  posedge CLK &&& write_flag, tds, ntf_tds);
  $setup (posedge D[7],  posedge CLK &&& write_flag, tds, ntf_tds);

  $setup (negedge D[0],  posedge CLK &&& write_flag, tds, ntf_tds);
  $setup (negedge D[1],  posedge CLK &&& write_flag, tds, ntf_tds);
  $setup (negedge D[2],  posedge CLK &&& write_flag, tds, ntf_tds);
  $setup (negedge D[3],  posedge CLK &&& write_flag, tds, ntf_tds);
  $setup (negedge D[4],  posedge CLK &&& write_flag, tds, ntf_tds);
  $setup (negedge D[5],  posedge CLK &&& write_flag, tds, ntf_tds);
  $setup (negedge D[6],  posedge CLK &&& write_flag, tds, ntf_tds);
  $setup (negedge D[7],  posedge CLK &&& write_flag, tds, ntf_tds);

  $hold  (posedge CLK &&& write_flag, negedge D[0],  tdh, ntf_tdh);
  $hold  (posedge CLK &&& write_flag, negedge D[1],  tdh, ntf_tdh);
  $hold  (posedge CLK &&& write_flag, negedge D[2],  tdh, ntf_tdh);
  $hold  (posedge CLK &&& write_flag, negedge D[3],  tdh, ntf_tdh);
  $hold  (posedge CLK &&& write_flag, negedge D[4],  tdh, ntf_tdh);
  $hold  (posedge CLK &&& write_flag, negedge D[5],  tdh, ntf_tdh);
  $hold  (posedge CLK &&& write_flag, negedge D[6],  tdh, ntf_tdh);
  $hold  (posedge CLK &&& write_flag, negedge D[7],  tdh, ntf_tdh);

  $hold  (posedge CLK &&& write_flag, posedge D[0],  tdh, ntf_tdh);
  $hold  (posedge CLK &&& write_flag, posedge D[1],  tdh, ntf_tdh);
  $hold  (posedge CLK &&& write_flag, posedge D[2],  tdh, ntf_tdh);
  $hold  (posedge CLK &&& write_flag, posedge D[3],  tdh, ntf_tdh);
  $hold  (posedge CLK &&& write_flag, posedge D[4],  tdh, ntf_tdh);
  $hold  (posedge CLK &&& write_flag, posedge D[5],  tdh, ntf_tdh);
  $hold  (posedge CLK &&& write_flag, posedge D[6],  tdh, ntf_tdh);
  $hold  (posedge CLK &&& write_flag, posedge D[7],  tdh, ntf_tdh);

//---- Output delay
// rise transition:     0->1, z->1, Ta
// fall transition:     1->0, 1->z, Ta
// turn-off transition: 0->z, 1->z, Tcqx
//if (!CEN & GWEN) (posedge CLK => (Q : 8'bx)) = (Ta, Ta, Tcqx);
if ((CEN == 1'b0) && (GWEN == 1'b1)) (posedge CLK => (Q[0]  : 1'bx)) = (ta, ta);
if ((CEN == 1'b0) && (GWEN == 1'b1)) (posedge CLK => (Q[1]  : 1'bx)) = (ta, ta);
if ((CEN == 1'b0) && (GWEN == 1'b1)) (posedge CLK => (Q[2]  : 1'bx)) = (ta, ta);
if ((CEN == 1'b0) && (GWEN == 1'b1)) (posedge CLK => (Q[3]  : 1'bx)) = (ta, ta);
if ((CEN == 1'b0) && (GWEN == 1'b1)) (posedge CLK => (Q[4]  : 1'bx)) = (ta, ta);
if ((CEN == 1'b0) && (GWEN == 1'b1)) (posedge CLK => (Q[5]  : 1'bx)) = (ta, ta);
if ((CEN == 1'b0) && (GWEN == 1'b1)) (posedge CLK => (Q[6]  : 1'bx)) = (ta, ta);
if ((CEN == 1'b0) && (GWEN == 1'b1)) (posedge CLK => (Q[7]  : 1'bx)) = (ta, ta);
endspecify

`ifndef MQ_TCHK_PROBE
assign no_st_viol = ~(|{ntf_tcs, ntf_tas, ntf_tds, ntf_tws, ntf_twis});
assign no_hd_viol = ~(|{ntf_tch, ntf_tah, ntf_tdh, ntf_twh, ntf_twih});
assign no_ck_viol = ~(|{ntf_Tcyc, ntf_Tckh, ntf_Tckl});
`else   // margin-probe runs (note 5): violations are reported but do not corrupt the memory
assign no_st_viol = 1'b1;
assign no_hd_viol = 1'b1;
assign no_ck_viol = 1'b1;
`endif

always @(CLK_d) clk_dly        = #TDLY CLK_d;
always @(CLK_d) write_flag_dly = #200 write_flag;
always @(CLK_d) read_flag_dly  = #200 read_flag;

always @(posedge CLK_d) marked_a = A_d;

assign we  = ~WEN_d;
assign cd2 = mem[A_d] & WEN_d;	//set write bits to 0, others unchanged
assign cd4 = D_d & we;		//set write bits to 0/1, others = 0
assign cd5 = cd2 | cd4;		//memory content after write

always @(posedge CLK_d) cdx = {8{1'bx}} & we;    //latch cdx

always @(posedge clk_dly) begin
  if (write_flag) begin 	//write
    if (no_st_viol) begin 	//write, no viol
      mem[A_d] = cd5;
    end
    else begin                 	//write, with viol
      mem[A_d] = mem[A_d] ^ cdx;    //1^x = x
      qo_reg = qo_reg ^ cdx;
    end
  end //write
  else if (read_flag) begin     //read 
  // else if (read_flag_dly) begin     //read
    if (no_st_viol) begin 	//read, no viol
      qo_reg = mem[marked_a];
    end
    else begin                  //read, with viol
      qo_reg = 8'bx;
    end
  end //read
end

always @(negedge clk_dly) begin         	//invalidate write/read when hold/clk viol
  if (no_hd_viol == 0 | no_ck_viol == 0) begin
    if (write_flag_dly) begin
      if (ntf_twh) begin
        mem[marked_a] = mem[marked_a] ^ 8'bx; //GWEN can't be used to generate cdx
        qo_reg        = qo_reg ^ 8'bx;
      end
      else begin
        mem[marked_a] = mem[marked_a] ^ cdx;
        qo_reg        = qo_reg ^ cdx;
      end
    end
    else if (read_flag_dly) begin
      qo_reg = 8'bx;
    end

    #100;
    ntf_tch  = 0;
    ntf_tah  = 0;
    ntf_tdh  = 0;
    ntf_twh  = 0;
    ntf_twih = 0;

    ntf_Tcyc  = 0;
    ntf_Tckh  = 0;
    ntf_Tckl  = 0;
  end
  else begin
    #100;
    ntf_tch  = 0;
    ntf_tah  = 0;
    ntf_tdh  = 0;
    ntf_twh  = 0;
    ntf_twih = 0;

    ntf_Tcyc  = 0;
    ntf_Tckh  = 0;
    ntf_Tckl  = 0;
  end
end

// note 4: the vendor block here was `always @(posedge ntf_tcs or ... posedge ntf_Tckl)`; an event
// control on a timing-check notifier crashes CVC's compiled code (SIGSEGV in __asl_trigger_ectrl
// on the first violation).  The same messages are printed at the falling clk_dly edge instead,
// where the notifiers are still set (they are cleared #100 later).
always @(negedge clk_dly) begin
  if (cen_fell) begin
    if (ntf_tcs)  $display("---- ERROR: CEN setup violation! ----");
    if (ntf_tas)  $display("---- ERROR: A setup violation! ----");
    if (ntf_tds)  $display("---- ERROR: D setup violation! ----");
    if (ntf_tws)  $display("---- ERROR: GWEN setup violation! ----");
    if (ntf_twis) $display("---- ERROR: WEN setup violation! ----");

    if (ntf_tch)  $display("---- ERROR: CEN hold violation! ----");
    if (ntf_tah)  $display("---- ERROR: A hold violation! ----");
    if (ntf_tdh)  $display("---- ERROR: D hold violation! ----");
    if (ntf_twh)  $display("---- ERROR: GWEN hold violation! ----");
    if (ntf_twih) $display("---- ERROR: WEN hold violation! ----");

    if (ntf_Tcyc) $display("---- ERROR: CLK period violation! ----");
    if (ntf_Tckh) $display("---- ERROR: CLK pulse width high violation! ----");
    if (ntf_Tckl) $display("---- ERROR: CLK pulse width low violation! ----");
  end
end

always @(posedge cen_fell) begin	//reset fasle notifiers
  ntf_tcs  = 0;				//after CEN reset (CEN from 1 to 0)
  ntf_tas  = 0;
  ntf_tds  = 0;
  ntf_tws  = 0;
  ntf_twis = 0;

  ntf_tch  = 0;
  ntf_tah  = 0;
  ntf_tdh  = 0;
  ntf_twh  = 0;
  ntf_twih = 0;
end

always @(negedge clk_dly) begin	//reset setup/hold notifiers
  #100;
  ntf_tcs  = 0;
  ntf_tas  = 0;
  ntf_tds  = 0;
  ntf_tws  = 0;
  ntf_twis = 0;

  ntf_tch  = 0;
  ntf_tah  = 0;
  ntf_tdh  = 0;
  ntf_twh  = 0;
  ntf_twih = 0;
end

initial begin			//initialization
  ntf_Tcyc  = 0;
  ntf_Tckh  = 0;
  ntf_Tckl  = 0;

  ntf_tcs  = 0;
  ntf_tas  = 0;
  ntf_tds  = 0;
  ntf_tws  = 0;
  ntf_twis = 0;

  ntf_tch  = 0;
  ntf_tah  = 0;
  ntf_tdh  = 0;
  ntf_twh  = 0;
  ntf_twih = 0;

  marked_a = 8'd0;

  qo_reg         = 8'd0;
  clk_dly        = 0;
  write_flag_dly = 0;
  read_flag_dly  = 0;
  cen_dly	 = 0;
  cen_fell       = 0;
  cen_not_rst    = 0;

  for(i=0; i<256; i=i+1) begin
    mem[i] = 8'd0;
  end
end

endmodule
