`timescale 1ns / 1ps

// ============================================================================
// mb_host_qspi -- quad-capable serial host interface (protocol of
// rtl/e2e_host_qspi.v without the INT8 debug commands).  SPI mode 0, MSB
// first; the command byte is always 1-bit on IO0.
//
//   0x02 WR_CSR   : addr[7:0] (1b), data bytes (1b), auto-increment
//   0x0B RD_CSR   : addr[7:0] (1b), 8 dummy SCLK, data on IO1, auto-increment
//   0x31 START    : start pulse (one token step)
//   0x32 STREAM_Q : stream bytes until CS_N rises; 2 SCLK/byte on IO[3:0]
//                   (high nibble first) when quad_en = 1, else 8 SCLK/byte on IO0
//   0x6B RD_MEM_Q : addr[15:0] quad (4 SCLK), 4 dummy SCLK, data quad 2 SCLK/byte
//   0x03 RD_MEM   : addr[15:0] (1b), 8 dummy SCLK, data on IO1
//   other         : err_cmd pulse, rest of the frame ignored
//
// Read data: the first bit/nibble is presented after the last dummy SCLK
// rising edge and advances on every following rising edge; the host samples
// just before each rising edge.  The output lags the pad edge by ~3 clk, so
// read phases need SCLK <= clk/8; write/stream phases work at clk/4.
// rd_req pulses with h_addr stable; rd_data is captured one clk later and
// h_addr then increments.  rd_mem selects the memory (else CSR) source.
// ============================================================================
module mb_host_qspi (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        sclk_pad,
    input  wire        cs_n_pad,
    input  wire [3:0]  io_in,
    output wire [3:0]  io_out,
    output wire [3:0]  io_oe,
    input  wire        quad_en,
    output reg  [15:0] h_addr,
    output reg         csr_we,
    output reg  [7:0]  csr_wdata,
    output reg         rd_mem,
    output reg         rd_req,
    input  wire [7:0]  rd_data,
    output reg         seq_start,
    output reg  [7:0]  st_byte,
    output reg         st_valid,
    output reg         err_cmd
);
    localparam [7:0] C_WR_CSR = 8'h02, C_RD_CSR = 8'h0B, C_START = 8'h31,
                     C_STREAM = 8'h32, C_RD_MEMQ = 8'h6B, C_RD_MEM = 8'h03;
    localparam [2:0] S_CMD = 3'd0, S_ADDR = 3'd1, S_WDATA = 3'd2, S_STREAM = 3'd3,
                     S_DUMMY = 3'd4, S_RDATA = 3'd5, S_IGNORE = 3'd6;

    wire       rise, cs_n;
    wire [3:0] io_s;
    mb_pad_sync u_sync (.clk(clk), .rst_n(rst_n), .sclk_pad(sclk_pad), .cs_n_pad(cs_n_pad),
                        .io_pad(io_in), .rise(rise), .cs_n(cs_n), .io(io_s));

    reg [2:0] state;
    reg [7:0] cmd;
    reg       quad;          // receive phase mode
    reg [2:0] bcnt;          // bits (or nibbles) received in the current byte
    reg [6:0] rx_sh;
    reg       abytes;        // address bytes remaining - 1 (0 -> last)
    reg [3:0] dcnt;          // dummy SCLKs remaining
    reg [7:0] tx_sh;
    reg       tx_quad;
    reg [2:0] tx_cnt;
    reg [7:0] rd_buf;
    reg       rd_pend;

    wire       rx_done = rise && (quad ? (bcnt == 3'd1) : (bcnt == 3'd7));
    wire [7:0] rx_byte = quad ? {rx_sh[3:0], io_s} : {rx_sh[6:0], io_s[0]};
    wire       tx_last = tx_quad ? (tx_cnt == 3'd1) : (tx_cnt == 3'd7);

    assign io_out = tx_quad ? tx_sh[7:4] : {2'b00, tx_sh[7], 1'b0};
    assign io_oe  = (!cs_n && state == S_RDATA) ? (tx_quad ? 4'hF : 4'b0010) : 4'h0;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= S_CMD; cmd <= 8'h00; quad <= 1'b0; bcnt <= 3'd0; rx_sh <= 7'h00;
            abytes <= 1'b0; dcnt <= 4'd0; tx_sh <= 8'h00; tx_quad <= 1'b0; tx_cnt <= 3'd0;
            rd_buf <= 8'h00; rd_pend <= 1'b0; h_addr <= 16'h0000;
            csr_we <= 1'b0; csr_wdata <= 8'h00; rd_mem <= 1'b0; rd_req <= 1'b0;
            seq_start <= 1'b0; st_byte <= 8'h00; st_valid <= 1'b0; err_cmd <= 1'b0;
        end else begin
            csr_we <= 1'b0; rd_req <= 1'b0; seq_start <= 1'b0; st_valid <= 1'b0; err_cmd <= 1'b0;

            // read data capture one cycle after the request, then auto-increment
            rd_pend <= rd_req;
            if (rd_pend) begin
                rd_buf <= rd_data;
                h_addr <= h_addr + 16'd1;
            end
            if (csr_we) h_addr <= h_addr + 16'd1;

            if (cs_n) begin
                state <= S_CMD; quad <= 1'b0; bcnt <= 3'd0; tx_quad <= 1'b0;
            end else begin
                if (rise && (state == S_CMD || state == S_ADDR || state == S_WDATA ||
                             state == S_STREAM)) begin
                    rx_sh <= rx_byte[6:0];
                    bcnt  <= rx_done ? 3'd0 : bcnt + 3'd1;
                end

                case (state)
                    S_CMD: if (rx_done) begin
                        cmd    <= rx_byte;
                        h_addr <= 16'h0000;
                        case (rx_byte)
                            C_WR_CSR, C_RD_CSR: begin abytes <= 1'b0; state <= S_ADDR; end
                            C_RD_MEM:           begin abytes <= 1'b1; state <= S_ADDR; end
                            C_RD_MEMQ: begin abytes <= 1'b1; quad <= 1'b1; state <= S_ADDR; end
                            C_START:   begin seq_start <= 1'b1; state <= S_IGNORE; end
                            C_STREAM:  begin quad <= quad_en; state <= S_STREAM; end
                            default:   begin err_cmd <= 1'b1; state <= S_IGNORE; end
                        endcase
                    end

                    S_ADDR: if (rx_done) begin
                        h_addr <= {h_addr[7:0], rx_byte};
                        abytes <= 1'b0;
                        if (!abytes) begin
                            if (cmd == C_WR_CSR) begin
                                quad  <= 1'b0;
                                state <= S_WDATA;
                            end else begin
                                // first read fetch; the dummy phase hides its latency
                                rd_mem  <= (cmd != C_RD_CSR);
                                rd_req  <= 1'b1;
                                tx_quad <= (cmd == C_RD_MEMQ);
                                dcnt    <= (cmd == C_RD_MEMQ) ? 4'd4 : 4'd8;
                                state   <= S_DUMMY;
                            end
                        end
                    end

                    S_WDATA: if (rx_done) begin
                        csr_we    <= 1'b1;
                        csr_wdata <= rx_byte;
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
                        if (tx_last) begin
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
