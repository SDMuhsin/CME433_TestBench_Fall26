`timescale 1ns / 1ps

// ============================================================================
// e2e_seq -- layer/tile sequencer of dla_e2e_chip (G300 generator,
// 64 -> 256 -> 256 -> 784, ReLU/ReLU/Tanh, N=4 output neurons per DLA run).
//
// Stream layout (bytes, after START):
//   zq[0..63]
//   L0: 64 tiles  x { b[4t..4t+3], W0 rows 4t..4t+3 (64 B each)  }
//   L2: 64 tiles  x { 4 b, 4 x 256 W }
//   L4: 196 tiles x { 4 b, 4 x 256 W }                 total 283,984 B
//
// Buffer plan (dla_engine_top B bank, 4 columns x 256):
//   L0 : input col0 (zq, k 0..63)  -> h0 into col1
//   L2 : input col1 (h0)           -> h2 into col0 (zq dead)
//   L4 : input col0 (h2)           -> pixel p<768 into col(1+p/256)[p%256],
//                                     p>=768 into the 16-byte FF tail stash
//
// Per tile: the stream decoder pops the 4-byte skid FIFO, writes the 4 biases
// into a double buffer and the 4 weight rows into A (only while the DLA is
// idle), then -- once the previous tile's requant has finished -- pulses
// `dla_start` with k_last = in_dim-1.  On the DLA's wb_done the requant FSM
// reads C[r][col_in] for r = 0..3, runs e2e_requant and writes the int8
// result into B / the stash.  Requant B-writes have priority over stream
// A-writes on the shared write port; both only happen while the DLA is idle.
//
// HRDY (host ready): high when no image is in flight (before START / after
// DONE); while streaming, high iff the FIFO holds <= 1 byte, which leaves room
// for >= 2 bytes already in flight on the host side when HRDY falls.  After the
// last stream byte it stays low until DONE.
//
// Raw debug access (dbg_*) is honoured only while no image is in flight.
// ============================================================================
module e2e_seq (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        soft_rst,       // CTRL[0], level: holds the sequencer idle

    // host
    input  wire        start_cmd,
    input  wire [7:0]  st_byte,
    input  wire        st_valid,
    input  wire        err_cmd_in,

    // requant constants
    input  wire [31:0] ma0, mb0, ma2, mb2, mw4, mb4,

    // raw debug access
    input  wire        dbg_wr_en,
    input  wire        dbg_wr_sel,
    input  wire [9:0]  dbg_wr_addr,
    input  wire [7:0]  dbg_wr_data,
    input  wire        dbg_start,
    input  wire [7:0]  dbg_k_last,
    input  wire        dbg_rd_en,
    input  wire [3:0]  dbg_rd_addr,

    // dla_engine_top
    output reg         dla_start,
    output reg  [7:0]  dla_k_last,
    output reg         dla_wr_en,
    output reg         dla_wr_sel,
    output reg  [9:0]  dla_wr_addr,
    output reg  [7:0]  dla_wr_data,
    output wire        dla_rd_en,
    output wire [3:0]  dla_rd_addr,
    input  wire [23:0] dla_rd_data,
    input  wire        dla_wb_done,
    output reg         dla_active,     // a DLA run (compute + C writeback) is in flight

    // pixel tail stash read
    input  wire [3:0]  stash_rd_addr,
    output wire [7:0]  stash_rd_data,

    // status
    output reg         armed,          // image in flight
    output reg         done,
    output wire        hrdy,
    output reg         err_cmd,
    output reg         err_ovf,
    output reg  [1:0]  layer,
    output reg  [7:0]  tile,
    output reg  [18:0] byte_cnt
);
    localparam [18:0] TOTAL_BYTES = 19'd283984;

    // ---------------------------------------------------------------- FIFO
    reg [7:0] fifo [0:3];
    reg [1:0] f_wp, f_rp;
    reg [2:0] f_cnt;
    wire      f_empty = (f_cnt == 3'd0);
    wire      f_full  = (f_cnt == 3'd4);
    wire [7:0] f_head = fifo[f_rp];
    wire      all_rcvd = (byte_cnt == TOTAL_BYTES);

    // ---------------------------------------------------------- decoder
    localparam [2:0] D_IDLE = 3'd0, D_Z = 3'd1, D_BIAS = 3'd2, D_W = 3'd3,
                     D_WS = 3'd4, D_END = 3'd5;
    reg [2:0] dstate;
    reg [1:0] drow;
    reg [7:0] dk;
    reg       wpar;                    // bias buffer being filled
    reg [7:0] bias_buf [0:7];          // {par, row}

    wire [7:0] k_last_cur = (layer == 2'd0) ? 8'd63 : 8'd255;
    wire [7:0] tile_last  = (layer == 2'd2) ? 8'd195 : 8'd63;

    // ---------------------------------------------------------- requant FSM
    localparam [2:0] R_IDLE = 3'd0, R_PEND = 3'd1, R_RDC = 3'd2, R_LAT = 3'd3,
                     R_WAIT = 3'd4, R_WR = 3'd5;
    reg [2:0] rstate;
    reg [1:0] rrow;
    reg [1:0] rq_layer;
    reg [7:0] rq_tile;
    reg       rq_par;
    reg [7:0] rq_res;
    reg [7:0] stash [0:15];

    wire       rq_busy_tile = (rstate != R_IDLE);
    wire       rq_wr        = (rstate == R_WR);
    wire [1:0] rq_col_in    = (rq_layer == 2'd1) ? 2'd1 : 2'd0;
    wire [9:0] rq_n         = {rq_tile, rrow};              // neuron / pixel index
    wire       rq_to_stash  = (rq_layer == 2'd2) && (rq_n >= 10'd768);
    wire [1:0] rq_pix_col   = rq_n[9:8] + 2'd1;
    wire [9:0] rq_b_addr    = (rq_layer == 2'd0) ? {rq_n[7:0], 2'd1} :
                              (rq_layer == 2'd1) ? {rq_n[7:0], 2'd0} :
                                                   {rq_n[7:0], rq_pix_col};

    reg  [31:0] m_a, m_b;
    always @* begin
        case (rq_layer)
            2'd0:    begin m_a = ma0; m_b = mb0; end
            2'd1:    begin m_a = ma2; m_b = mb2; end
            default: begin m_a = mw4; m_b = mb4; end
        endcase
    end

    wire       u_start = (rstate == R_LAT);
    wire       u_valid;
    wire       u_busy;     // unused: the requant FSM tracks the unit through u_valid
    wire       _unused = u_busy;
    wire [7:0] u_q;
    wire       seq_clr = start_cmd | soft_rst;

    e2e_requant u_rq (
        .clk       (clk),
        .rst_n     (rst_n),
        .clear     (seq_clr),
        .start     (u_start),
        .mode_tanh (rq_layer == 2'd2),
        .acc       (dla_rd_data),
        .bias      (bias_buf[{rq_par, rrow}]),
        .m_a       (m_a),
        .m_b       (m_b),
        .busy      (u_busy),
        .valid     (u_valid),
        .q         (u_q)
    );

    assign dla_rd_en   = (rstate == R_RDC) | (dbg_rd_en & ~armed);
    assign dla_rd_addr = (rstate == R_RDC) ? {rrow, rq_col_in} : dbg_rd_addr;

    assign stash_rd_data = stash[stash_rd_addr];

    // ---------------------------------------------------------- pop logic
    wire dla_busy_any   = dla_active | dla_start;
    wire dec_needs_port = (dstate == D_Z) || (dstate == D_W);
    wire pop = armed && !f_empty &&
               ((dstate == D_BIAS) ||
                (dec_needs_port && !dla_busy_any && !rq_wr));

    wire start_ok = (dstate == D_WS) && !dla_busy_any && !rq_busy_tile && !dla_wr_en;

    assign hrdy = !armed || (!all_rcvd && (f_cnt <= 3'd1));

    // ---- storage arrays: plain (non-reset) flops, written only when valid ----
    wire fifo_push = st_valid && armed && !seq_clr && !all_rcvd && !(f_full && !pop);
    always @(posedge clk) begin
        if (fifo_push) fifo[f_wp] <= st_byte;
        if (!seq_clr && dstate == D_BIAS && pop) bias_buf[{wpar, drow}] <= f_head;
        if (!seq_clr && rq_wr && rq_to_stash) stash[rq_n[3:0]] <= rq_res;
    end

    reg wb_done_q;
    wire wb_rise = dla_wb_done & ~wb_done_q;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            f_wp <= 2'd0; f_rp <= 2'd0; f_cnt <= 3'd0;
            dstate <= D_IDLE; drow <= 2'd0; dk <= 8'd0; wpar <= 1'b0;
            rstate <= R_IDLE; rrow <= 2'd0; rq_layer <= 2'd0; rq_tile <= 8'd0;
            rq_par <= 1'b0; rq_res <= 8'h00;
            dla_start <= 1'b0; dla_k_last <= 8'hFF;
            dla_wr_en <= 1'b0; dla_wr_sel <= 1'b0; dla_wr_addr <= 10'd0; dla_wr_data <= 8'h00;
            dla_active <= 1'b0; wb_done_q <= 1'b0;
            armed <= 1'b0; done <= 1'b0; err_cmd <= 1'b0; err_ovf <= 1'b0;
            layer <= 2'd0; tile <= 8'd0; byte_cnt <= 19'd0;
        end else begin
            dla_start <= 1'b0;
            dla_wr_en <= 1'b0;
            wb_done_q <= dla_wb_done;

            // DLA activity tracking: never reset by START/soft reset, so a run
            // still in flight always completes before A/B are touched again.
            if (dla_start)    dla_active <= 1'b1;
            else if (wb_rise) dla_active <= 1'b0;

            if (err_cmd_in) err_cmd <= 1'b1;

            if (seq_clr) begin
                // START (or held soft reset): new image
                f_wp <= 2'd0; f_rp <= 2'd0; f_cnt <= 3'd0;
                dstate   <= start_cmd ? D_Z : D_IDLE;
                armed    <= start_cmd;
                done     <= 1'b0;
                err_cmd  <= 1'b0;
                err_ovf  <= 1'b0;
                drow <= 2'd0; dk <= 8'd0; wpar <= 1'b0;
                layer <= 2'd0; tile <= 8'd0; byte_cnt <= 19'd0;
                rstate <= R_IDLE; rrow <= 2'd0;
            end else begin
                // ---------------- FIFO push / pop ----------------
                if (st_valid && armed) begin
                    if (all_rcvd || (f_full && !pop)) begin
                        err_ovf <= 1'b1;               // byte dropped
                    end else begin
                        f_wp       <= f_wp + 2'd1;
                        byte_cnt   <= byte_cnt + 19'd1;
                    end
                end
                if (pop) f_rp <= f_rp + 2'd1;
                f_cnt <= f_cnt + (fifo_push ? 3'd1 : 3'd0)
                               - (pop ? 3'd1 : 3'd0);

                // ---------------- stream decoder ----------------
                case (dstate)
                    D_Z: if (pop) begin
                        dla_wr_en   <= 1'b1;
                        dla_wr_sel  <= 1'b1;                    // B col0, row k
                        dla_wr_addr <= {dk, 2'd0};
                        dla_wr_data <= f_head;
                        dk <= dk + 8'd1;
                        if (dk == 8'd63) begin
                            dk     <= 8'd0;
                            dstate <= D_BIAS;
                        end
                    end

                    D_BIAS: if (pop) begin
                        drow <= drow + 2'd1;
                        if (drow == 2'd3) dstate <= D_W;
                    end

                    D_W: if (pop) begin
                        dla_wr_en   <= 1'b1;
                        dla_wr_sel  <= 1'b0;                    // A row r, col k
                        dla_wr_addr <= {drow, dk};
                        dla_wr_data <= f_head;
                        dk <= dk + 8'd1;
                        if (dk == k_last_cur) begin
                            dk   <= 8'd0;
                            drow <= drow + 2'd1;
                            if (drow == 2'd3) dstate <= D_WS;
                        end
                    end

                    D_WS: if (start_ok) begin
                        dla_start  <= 1'b1;
                        dla_k_last <= k_last_cur;
                        rq_layer   <= layer;
                        rq_tile    <= tile;
                        rq_par     <= wpar;
                        rstate     <= R_PEND;
                        wpar       <= ~wpar;
                        if (tile == tile_last) begin
                            tile <= 8'd0;
                            if (layer == 2'd2) begin
                                dstate <= D_END;
                            end else begin
                                layer  <= layer + 2'd1;
                                dstate <= D_BIAS;
                            end
                        end else begin
                            tile   <= tile + 8'd1;
                            dstate <= D_BIAS;
                        end
                    end

                    D_END: if (!dla_active && !rq_busy_tile && !dla_start) begin
                        done   <= 1'b1;
                        armed  <= 1'b0;
                        dstate <= D_IDLE;
                    end

                    default: ;
                endcase

                // ---------------- requant of the finished tile ----------------
                case (rstate)
                    R_PEND: if (wb_rise) begin
                        rrow   <= 2'd0;
                        rstate <= R_RDC;
                    end
                    R_RDC:  rstate <= R_LAT;            // C read issued (1-clk latency)
                    R_LAT:  rstate <= R_WAIT;           // e2e_requant started with C data
                    R_WAIT: if (u_valid) begin
                        rq_res <= u_q;
                        rstate <= R_WR;
                    end
                    R_WR: begin
                        if (!rq_to_stash) begin
                            dla_wr_en   <= 1'b1;             // priority over the decoder
                            dla_wr_sel  <= 1'b1;
                            dla_wr_addr <= rq_b_addr;
                            dla_wr_data <= rq_res;
                        end
                        rrow <= rrow + 2'd1;
                        rstate <= (rrow == 2'd3) ? R_IDLE : R_RDC;
                    end
                    default: ;
                endcase
            end

            // ---------------- raw debug access (no image in flight) -------------
            if (!armed && !seq_clr) begin
                if (dbg_wr_en && !dla_busy_any) begin
                    dla_wr_en   <= 1'b1;
                    dla_wr_sel  <= dbg_wr_sel;
                    dla_wr_addr <= dbg_wr_addr;
                    dla_wr_data <= dbg_wr_data;
                end
                if (dbg_start && !dla_busy_any) begin
                    dla_start  <= 1'b1;
                    dla_k_last <= dbg_k_last;
                end
            end
        end
    end

endmodule
