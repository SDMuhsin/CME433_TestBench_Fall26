`timescale 1ns / 1ps

// ============================================================================
// fp16_seq -- stream decoder / layer sequencer of dla_fp16_chip
// (G300 generator 64 -> 256 -> 256 -> 784, ReLU / ReLU / Tanh, FP16).
//
// Stream (bytes after START; every FP16 word MSB byte first), 567,968 B:
//   z[0..63]
//   L0: 256 x { b[r], W0[r][0..63]  }
//   L2: 256 x { b[r], W2[r][0..255] }
//   L4: 784 x { b[r], W4[r][0..255] }
// Weights are consumed straight out of the 4-byte skid FIFO: each completed
// weight word is issued to fp16_lane together with x[k], read from the
// source activation pair (the pair address is k whenever the pair is not
// being written, so Q = x[k] one clock after k changes).
//
// Activation pairs (256 x 16 b each = 2 x 256x8 macros), pixel buffer 1024x8:
//   L0: src P0 (z, k 0..63) -> h0 into P1
//   L2: src P1              -> h2 into P0 (z dead)
//   L4: src P0              -> pixel r into PIX[r]
// Per neuron: bias word -> lane ld_bias (lane idle), K weight words -> issue
// (interval >= 2 clk enforced by lane can_issue), then D_FIN waits for the
// lane to drain and the epilogue of the previous neuron to be written back,
// and pulses epi_go.  The epilogue of neuron r overlaps the stream of neuron
// r+1 (it writes the destination pair, never the source pair).  At a layer
// boundary D_DRAIN waits for the last write-back before the next layer reads.
//
// HRDY (host ready): high when no image is in flight (before START / after
// DONE); while streaming, high iff the FIFO holds <= 1 byte; after the last
// stream byte it stays low until DONE (as dla_e2e_chip).
// ============================================================================
module fp16_seq (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        soft_rst,
    input  wire        start_cmd,
    input  wire [7:0]  st_byte,
    input  wire        st_valid,
    input  wire        err_cmd_in,

    // MAC lane
    output reg         lane_issue,
    output reg  [15:0] lane_w,
    output reg  [15:0] lane_x,
    output reg         lane_ld_bias,
    output reg  [15:0] lane_bias,
    input  wire        lane_can_issue,
    input  wire        lane_idle,
    output wire        lane_clear,

    // epilogue
    output reg         epi_go,
    output reg         epi_tanh,
    input  wire        epi_busy,
    input  wire        epi_done,
    input  wire [15:0] epi_y,
    input  wire [7:0]  epi_pix,

    // activation pairs P0 / P1
    output wire [7:0]  act_addr0,
    output wire [7:0]  act_addr1,
    output reg  [1:0]  act_we,
    output reg  [15:0] act_wdata,
    input  wire [15:0] act_rdata0,
    input  wire [15:0] act_rdata1,

    // pixel buffer write port
    output reg         pix_we,
    output reg  [9:0]  pix_waddr,
    output reg  [7:0]  pix_wdata,

    // status
    output reg         armed,
    output reg         done,
    output wire        hrdy,
    output reg         err_cmd,
    output reg         err_ovf,
    output reg  [1:0]  layer,
    output reg  [9:0]  neuron,
    output reg  [19:0] byte_cnt
);
    localparam [19:0] TOTAL_BYTES = 20'd567968;

    // ---------------------------------------------------------------- FIFO
    reg [7:0] fifo [0:3];
    reg [1:0] f_wp, f_rp;
    reg [2:0] f_cnt;
    wire      f_empty  = (f_cnt == 3'd0);
    wire      f_full   = (f_cnt == 3'd4);
    wire [7:0] f_head  = fifo[f_rp];
    wire      all_rcvd = (byte_cnt == TOTAL_BYTES);

    // ---------------------------------------------------------------- decoder
    localparam [3:0] D_IDLE = 4'd0, D_ZHI = 4'd1, D_ZLO = 4'd2, D_BHI = 4'd3,
                     D_BLO = 4'd4, D_WHI = 4'd5, D_WLO = 4'd6, D_FIN = 4'd7,
                     D_DRAIN = 4'd8, D_END = 4'd9;
    reg [3:0] dstate;
    reg [7:0] hi;
    reg [7:0] dk;
    reg [7:0] act_waddr;
    reg [1:0] ep_layer;
    reg [9:0] ep_nrn;

    wire [7:0] k_last   = (layer == 2'd0) ? 8'd63 : 8'd255;
    wire [9:0] nrn_last = (layer == 2'd2) ? 10'd783 : 10'd255;
    wire [15:0] x_src   = (layer == 2'd1) ? act_rdata1 : act_rdata0;

    // pair address = write address while written, else the current k
    assign act_addr0 = act_we[0] ? act_waddr : dk;
    assign act_addr1 = act_we[1] ? act_waddr : dk;

    // epilogue / write-back fully idle
    wire epi_quiet = !epi_go && !epi_busy && !epi_done && (act_we == 2'b00) && !pix_we;

    wire seq_clr = start_cmd | soft_rst;
    assign lane_clear = seq_clr;

    wire pop = armed && !f_empty &&
               ((dstate == D_ZHI) || (dstate == D_ZLO) || (dstate == D_BHI) || (dstate == D_WHI) ||
                (dstate == D_BLO && lane_idle) ||
                (dstate == D_WLO && lane_can_issue));

    assign hrdy = !armed || (!all_rcvd && (f_cnt <= 3'd1));

    wire fifo_push = st_valid && armed && !seq_clr && !all_rcvd && !(f_full && !pop);
    always @(posedge clk) begin
        if (fifo_push) fifo[f_wp] <= st_byte;
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            f_wp <= 2'd0; f_rp <= 2'd0; f_cnt <= 3'd0;
            dstate <= D_IDLE; hi <= 8'h00; dk <= 8'd0;
            lane_issue <= 1'b0; lane_w <= 16'h0; lane_x <= 16'h0;
            lane_ld_bias <= 1'b0; lane_bias <= 16'h0;
            epi_go <= 1'b0; epi_tanh <= 1'b0; ep_layer <= 2'd0; ep_nrn <= 10'd0;
            act_we <= 2'b00; act_waddr <= 8'd0; act_wdata <= 16'h0;
            pix_we <= 1'b0; pix_waddr <= 10'd0; pix_wdata <= 8'h00;
            armed <= 1'b0; done <= 1'b0; err_cmd <= 1'b0; err_ovf <= 1'b0;
            layer <= 2'd0; neuron <= 10'd0; byte_cnt <= 20'd0;
        end else begin
            lane_issue   <= 1'b0;
            lane_ld_bias <= 1'b0;
            epi_go       <= 1'b0;
            act_we       <= 2'b00;
            pix_we       <= 1'b0;

            if (err_cmd_in) err_cmd <= 1'b1;

            if (seq_clr) begin
                f_wp <= 2'd0; f_rp <= 2'd0; f_cnt <= 3'd0;
                dstate  <= start_cmd ? D_ZHI : D_IDLE;
                armed   <= start_cmd;
                done    <= 1'b0;
                err_cmd <= 1'b0;
                err_ovf <= 1'b0;
                dk <= 8'd0; layer <= 2'd0; neuron <= 10'd0; byte_cnt <= 20'd0;
            end else begin
                // ---------------- FIFO ----------------
                if (st_valid && armed) begin
                    if (all_rcvd || (f_full && !pop)) begin
                        err_ovf <= 1'b1;
                    end else begin
                        f_wp     <= f_wp + 2'd1;
                        byte_cnt <= byte_cnt + 20'd1;
                    end
                end
                if (pop) f_rp <= f_rp + 2'd1;
                f_cnt <= f_cnt + (fifo_push ? 3'd1 : 3'd0) - (pop ? 3'd1 : 3'd0);

                // ---------------- epilogue write-back ----------------
                if (epi_done) begin
                    if (ep_layer == 2'd2) begin
                        pix_we    <= 1'b1;
                        pix_waddr <= ep_nrn;
                        pix_wdata <= epi_pix;
                    end else begin
                        act_we    <= (ep_layer == 2'd0) ? 2'b10 : 2'b01;
                        act_waddr <= ep_nrn[7:0];
                        act_wdata <= epi_y;
                    end
                end

                // ---------------- stream decoder ----------------
                case (dstate)
                    D_ZHI: if (pop) begin hi <= f_head; dstate <= D_ZLO; end
                    D_ZLO: if (pop) begin
                        act_we    <= 2'b01;                  // z -> P0[k]
                        act_waddr <= dk;
                        act_wdata <= {hi, f_head};
                        dk        <= dk + 8'd1;
                        dstate    <= (dk == 8'd63) ? D_BHI : D_ZHI;
                        if (dk == 8'd63) dk <= 8'd0;
                    end
                    D_BHI: if (pop) begin hi <= f_head; dstate <= D_BLO; end
                    D_BLO: if (pop) begin
                        lane_ld_bias <= 1'b1;
                        lane_bias    <= {hi, f_head};
                        dstate       <= D_WHI;
                    end
                    D_WHI: if (pop) begin hi <= f_head; dstate <= D_WLO; end
                    D_WLO: if (pop) begin
                        lane_issue <= 1'b1;
                        lane_w     <= {hi, f_head};
                        lane_x     <= x_src;                 // = x[dk]
                        if (dk == k_last) begin
                            dk     <= 8'd0;
                            dstate <= D_FIN;
                        end else begin
                            dk     <= dk + 8'd1;
                            dstate <= D_WHI;
                        end
                    end
                    D_FIN: if (lane_idle && !lane_issue && epi_quiet) begin
                        epi_go   <= 1'b1;
                        epi_tanh <= (layer == 2'd2);
                        ep_layer <= layer;
                        ep_nrn   <= neuron;
                        if (neuron == nrn_last) begin
                            neuron <= 10'd0;
                            dstate <= (layer == 2'd2) ? D_END : D_DRAIN;
                        end else begin
                            neuron <= neuron + 10'd1;
                            dstate <= D_BHI;
                        end
                    end
                    D_DRAIN: if (epi_quiet) begin
                        layer  <= layer + 2'd1;
                        dstate <= D_BHI;
                    end
                    D_END: if (epi_quiet) begin
                        done   <= 1'b1;
                        armed  <= 1'b0;
                        dstate <= D_IDLE;
                    end
                    default: ;
                endcase
            end
        end
    end
endmodule
