`timescale 1ns / 1ps

// ============================================================================
// e2e_host_qspi -- quad-capable serial host interface of dla_e2e_chip.
//
// Successor of dla_serial_bridge (which stays untouched for dla_engine_chip):
// same synchronizer style -- SCLK, CS_N and IO[3:0] are async pad inputs,
// double-flopped into `clk` and SCLK is rising-edge detected (no second clock
// domain).  SPI mode 0, MSB first.  The command byte is always 1-bit on IO0.
//
//   0x02 WR_CSR   : addr[7:0] (1b), data bytes (1b), auto-increment
//   0x0B RD_CSR   : addr[7:0] (1b), 8 dummy SCLK, data on IO1, auto-increment
//   0x31 START    : (nothing) -> start pulse to e2e_seq
//   0x32 STREAM_Q : stream bytes until CS_N rises; 2 SCLK/byte on IO[3:0]
//                   (high nibble first) when quad_en=1, else 8 SCLK/byte on IO0
//   0x6B RD_PIX_Q : addr[15:0] quad (4 SCLK), 4 dummy SCLK, data quad 2 SCLK/byte
//   0x03 RD_PIX   : addr[15:0] (1b), 8 dummy SCLK, data on IO1
//   0x10 DBG_WR_A : addr[15:0] (1b) then data bytes (1b), auto-increment
//   0x11 DBG_WR_B : same, B buffer
//   0x12 DBG_START: k_last[7:0] (1b) -> raw DLA start
//   0x13 DBG_RD_C : byte addr[15:0] (1b), 8 dummy, data on IO1 (C word a[5:2],
//                   byte a[1:0] little endian, byte 3 = sign extension)
//   other         : err_cmd pulse, rest of frame ignored
//
// Read data: the chip presents the first data bit/nibble after the last dummy
// SCLK rising edge and advances on every following rising edge, so the host
// samples just BEFORE each rising edge (as with dla_serial_bridge READ_C).
// The output update lags the pad edge by ~3 clk (2FF sync + register), hence
// read phases require SCLK <= clk/8; write/stream phases work at clk/4.
//
// Generic read port: rd_src selects the source (0 none, 1 CSR, 2 pixel, 3 C)
// for the whole read command, h_addr is the (auto-incremented) address.
// rd_req pulses for one cycle with h_addr stable; rd_data must be valid on
// the following cycle (1-clk SRAM/C-bank latency), where it is captured and
// h_addr increments.
// ============================================================================
module e2e_host_qspi (
    input  wire        clk,
    input  wire        rst_n,

    // pads (async)
    input  wire        sclk_pad,
    input  wire        cs_n_pad,
    input  wire [3:0]  io_in,
    output wire [3:0]  io_out,
    output wire [3:0]  io_oe,

    input  wire        quad_en,

    // address register (CSR / pixel / debug)
    output reg  [15:0] h_addr,

    // CSR write
    output reg         csr_we,
    output reg  [7:0]  csr_wdata,

    // generic read
    output reg  [1:0]  rd_src,
    output reg         rd_req,
    input  wire [7:0]  rd_data,

    // sequencer
    output reg         seq_start,
    output reg  [7:0]  st_byte,
    output reg         st_valid,

    // raw DLA debug access
    output reg         dbg_wr_en,
    output reg         dbg_wr_sel,
    output reg  [7:0]  dbg_wr_data,
    output reg         dbg_start,
    output reg  [7:0]  dbg_k_last,

    output reg         err_cmd
);
    localparam [7:0] C_WR_CSR = 8'h02, C_RD_CSR = 8'h0B, C_START = 8'h31,
                     C_STREAM = 8'h32, C_RD_PIXQ = 8'h6B, C_RD_PIX = 8'h03,
                     C_DBG_WRA = 8'h10, C_DBG_WRB = 8'h11, C_DBG_START = 8'h12,
                     C_DBG_RDC = 8'h13;

    localparam [1:0] SRC_NONE = 2'd0, SRC_CSR = 2'd1, SRC_PIX = 2'd2, SRC_C = 2'd3;

    localparam [2:0] S_CMD = 3'd0, S_ADDR = 3'd1, S_WDATA = 3'd2, S_STREAM = 3'd3,
                     S_DUMMY = 3'd4, S_RDATA = 3'd5, S_IGNORE = 3'd6;

    // ---- double-flop synchronizers ----
    reg [1:0] sclk_sync, cs_n_sync;
    reg [3:0] io_s1, io_s2;
    reg       sclk_prev;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sclk_sync <= 2'b00;
            cs_n_sync <= 2'b11;
            io_s1     <= 4'h0;
            io_s2     <= 4'h0;
            sclk_prev <= 1'b0;
        end else begin
            sclk_sync <= {sclk_sync[0], sclk_pad};
            cs_n_sync <= {cs_n_sync[0], cs_n_pad};
            io_s1     <= io_in;
            io_s2     <= io_s1;
            sclk_prev <= sclk_sync[1];
        end
    end
    wire cs_n_s = cs_n_sync[1];
    wire rise   = sclk_sync[1] & ~sclk_prev;

    reg [2:0] state;
    reg [7:0] cmd;
    reg       quad;          // receive phase mode
    reg [2:0] bcnt;          // bits (or nibbles) received in the current byte
    reg [7:0] rx_sh;
    reg       abytes;        // address bytes remaining - 1 (0 -> last)
    reg [3:0] dcnt;          // dummy SCLKs remaining
    reg [7:0] tx_sh;
    reg       tx_quad;
    reg [2:0] tx_cnt;
    reg [7:0] rd_buf;
    reg       rd_pend;

    wire       rx_done = rise && (quad ? (bcnt == 3'd1) : (bcnt == 3'd7));
    wire [7:0] rx_byte = quad ? {rx_sh[3:0], io_s2} : {rx_sh[6:0], io_s2[0]};

    wire _unused = rx_sh[7];   // MSB is shifted out by the 1-bit byte assembly

    assign io_out = tx_quad ? tx_sh[7:4] : {2'b00, tx_sh[7], 1'b0};
    assign io_oe  = (!cs_n_s && state == S_RDATA) ? (tx_quad ? 4'hF : 4'b0010) : 4'h0;

    wire is_write_cmd = (cmd == C_WR_CSR) || (cmd == C_DBG_WRA) || (cmd == C_DBG_WRB);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state      <= S_CMD;
            cmd        <= 8'h00;
            quad       <= 1'b0;
            bcnt       <= 3'd0;
            rx_sh      <= 8'h00;
            abytes     <= 1'b0;
            dcnt       <= 4'd0;
            tx_sh      <= 8'h00;
            tx_quad    <= 1'b0;
            tx_cnt     <= 3'd0;
            rd_buf     <= 8'h00;
            rd_pend    <= 1'b0;
            h_addr     <= 16'h0000;
            csr_we     <= 1'b0;
            csr_wdata  <= 8'h00;
            rd_src     <= SRC_NONE;
            rd_req     <= 1'b0;
            seq_start  <= 1'b0;
            st_byte    <= 8'h00;
            st_valid   <= 1'b0;
            dbg_wr_en  <= 1'b0;
            dbg_wr_sel <= 1'b0;
            dbg_wr_data<= 8'h00;
            dbg_start  <= 1'b0;
            dbg_k_last <= 8'hFF;
            err_cmd    <= 1'b0;
        end else begin
            // single-cycle pulses
            csr_we    <= 1'b0;
            rd_req    <= 1'b0;
            seq_start <= 1'b0;
            st_valid  <= 1'b0;
            dbg_wr_en <= 1'b0;
            dbg_start <= 1'b0;
            err_cmd   <= 1'b0;

            // read data capture, one cycle after the request; then auto-increment
            rd_pend <= rd_req;
            if (rd_pend) begin
                rd_buf <= rd_data;
                h_addr <= h_addr + 16'd1;
            end

            // auto-increment after a write action (pulse issued last cycle)
            if (csr_we || dbg_wr_en) h_addr <= h_addr + 16'd1;

            if (cs_n_s) begin
                state   <= S_CMD;
                quad    <= 1'b0;
                bcnt    <= 3'd0;
                tx_quad <= 1'b0;
                rd_src  <= SRC_NONE;
            end else begin
                if (rise && (state == S_CMD || state == S_ADDR || state == S_WDATA || state == S_STREAM)) begin
                    rx_sh <= rx_byte;
                    bcnt  <= rx_done ? 3'd0 : bcnt + 3'd1;
                end

                case (state)
                    S_CMD: if (rx_done) begin
                        cmd    <= rx_byte;
                        h_addr <= 16'h0000;
                        case (rx_byte)
                            C_WR_CSR, C_RD_CSR: begin
                                abytes <= 1'b0;
                                state  <= S_ADDR;
                            end
                            C_RD_PIX, C_DBG_WRA, C_DBG_WRB, C_DBG_RDC: begin
                                abytes <= 1'b1;
                                state  <= S_ADDR;
                            end
                            C_RD_PIXQ: begin
                                abytes <= 1'b1;
                                quad   <= 1'b1;
                                state  <= S_ADDR;
                            end
                            C_DBG_START: state <= S_WDATA;
                            C_START: begin
                                seq_start <= 1'b1;
                                state     <= S_IGNORE;
                            end
                            C_STREAM: begin
                                quad  <= quad_en;
                                state <= S_STREAM;
                            end
                            default: begin
                                err_cmd <= 1'b1;
                                state   <= S_IGNORE;
                            end
                        endcase
                    end

                    S_ADDR: if (rx_done) begin
                        h_addr <= {h_addr[7:0], rx_byte};
                        abytes <= 1'b0;
                        if (!abytes) begin
                            if (is_write_cmd) begin
                                quad  <= 1'b0;
                                state <= S_WDATA;
                            end else begin
                                // first read fetch; the dummy phase hides its latency
                                rd_src  <= (cmd == C_RD_CSR) ? SRC_CSR :
                                           (cmd == C_DBG_RDC) ? SRC_C : SRC_PIX;
                                rd_req  <= 1'b1;
                                tx_quad <= (cmd == C_RD_PIXQ);
                                dcnt    <= (cmd == C_RD_PIXQ) ? 4'd4 : 4'd8;
                                state   <= S_DUMMY;
                            end
                        end
                    end

                    S_WDATA: if (rx_done) begin
                        case (cmd)
                            C_WR_CSR: begin
                                csr_we    <= 1'b1;
                                csr_wdata <= rx_byte;
                            end
                            C_DBG_WRA, C_DBG_WRB: begin
                                dbg_wr_en   <= 1'b1;
                                dbg_wr_sel  <= (cmd == C_DBG_WRB);
                                dbg_wr_data <= rx_byte;
                            end
                            default: begin   // C_DBG_START
                                dbg_start  <= 1'b1;
                                dbg_k_last <= rx_byte;
                                state      <= S_IGNORE;
                            end
                        endcase
                    end

                    S_STREAM: if (rx_done) begin
                        st_byte  <= rx_byte;
                        st_valid <= 1'b1;
                    end

                    S_DUMMY: if (rise) begin
                        dcnt <= dcnt - 4'd1;
                        if (dcnt == 4'd1) begin
                            tx_sh  <= rd_buf;
                            tx_cnt <= 3'd0;
                            rd_req <= 1'b1;
                            state  <= S_RDATA;
                        end
                    end

                    S_RDATA: if (rise) begin
                        if (tx_quad ? (tx_cnt == 3'd1) : (tx_cnt == 3'd7)) begin
                            tx_sh  <= rd_buf;
                            tx_cnt <= 3'd0;
                            rd_req <= 1'b1;
                        end else begin
                            tx_sh  <= tx_quad ? {tx_sh[3:0], 4'h0} : {tx_sh[6:0], 1'b0};
                            tx_cnt <= tx_cnt + 3'd1;
                        end
                    end

                    default: ;   // S_IGNORE: wait for CS_N high
                endcase
            end
        end
    end

endmodule
