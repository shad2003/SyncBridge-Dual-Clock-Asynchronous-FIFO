//-----------------------------------------------------------------------------
// Module: rptr_empty
// Description: Read-domain pointer handling and empty flag generation.
//              Generates binary read address for memory and Gray-code pointer
//              for CDC to the write domain. Empty flag is asserted when the
//              next read Gray pointer equals the synchronized write Gray pointer.
// Reference: Clifford E. Cummings, "Simulation and Synthesis Techniques for
//            Asynchronous FIFO Design", SNUG 2002.
//-----------------------------------------------------------------------------
`timescale 1ns / 1ps

module rptr_empty #(
    parameter int ADDR_WIDTH = 4
)(
    input  logic                  rclk,
    input  logic                  rrst_n,
    input  logic                  rinc,
    input  logic [ADDR_WIDTH:0]   rq2_wptr,
    output logic                  rempty,
    output logic [ADDR_WIDTH-1:0] raddr,
    output logic [ADDR_WIDTH:0]   rptr
);

    logic [ADDR_WIDTH:0] rbin;
    logic [ADDR_WIDTH:0] rbinnext;
    logic [ADDR_WIDTH:0] rgraynext;
    logic                rempty_val;

    // Memory read address is the lower ADDR_WIDTH bits of the binary counter
    assign raddr = rbin[ADDR_WIDTH-1:0];

    // Binary counter advancement (increment gated by !rempty)
    assign rbinnext  = rbin + (rinc & ~rempty);

    // Binary-to-Gray conversion for next state
    assign rgraynext = (rbinnext >> 1) ^ rbinnext;

    // Empty condition: Read pointer equals synchronized write pointer
    assign rempty_val = (rgraynext == rq2_wptr);

    // Sequential state updates on rclk with asynchronous active-low reset
    always_ff @(posedge rclk or negedge rrst_n) begin
        if (!rrst_n) begin
            rbin   <= '0;
            rptr   <= '0;
            rempty <= 1'b1; // FIFO is empty out of reset
        end else begin
            rbin   <= rbinnext;
            rptr   <= rgraynext;
            rempty <= rempty_val;
        end
    end

endmodule
