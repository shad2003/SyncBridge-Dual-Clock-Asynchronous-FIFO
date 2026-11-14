//-----------------------------------------------------------------------------
// Module: sync_w2r
// Description: Two-stage flip-flop synchronizer for Clock Domain Crossing (CDC)
//              of write Gray pointer into the read clock domain.
//              Active-low asynchronous reset rrst_n.
//-----------------------------------------------------------------------------
`timescale 1ns / 1ps

module sync_w2r #(
    parameter int ADDR_WIDTH = 4
)(
    input  logic                  rclk,
    input  logic                  rrst_n,
    input  logic [ADDR_WIDTH:0]   wptr,
    output logic [ADDR_WIDTH:0]   rq2_wptr
);

    logic [ADDR_WIDTH:0] rq1_wptr;

    always_ff @(posedge rclk or negedge rrst_n) begin
        if (!rrst_n) begin
            rq1_wptr <= '0;
            rq2_wptr <= '0;
        end else begin
            rq1_wptr <= wptr;
            rq2_wptr <= rq1_wptr;
        end
    end

endmodule
