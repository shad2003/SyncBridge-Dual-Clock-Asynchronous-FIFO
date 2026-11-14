//-----------------------------------------------------------------------------
// Module: fifomem
// Description: Dual-port parameterized memory array for Asynchronous FIFO.
//              Synchronous write gated by write-enable and !wfull.
//              Combinatorial read based on raddr.
// Reference: Clifford E. Cummings, "Simulation and Synthesis Techniques for
//            Asynchronous FIFO Design", SNUG 2002.
//-----------------------------------------------------------------------------
`timescale 1ns / 1ps

module fifomem #(
    parameter int DATA_WIDTH = 32,
    parameter int ADDR_WIDTH = 4
)(
    input  logic                  wclk,
    input  logic                  winc,
    input  logic                  wfull,
    input  logic [ADDR_WIDTH-1:0] waddr,
    input  logic [DATA_WIDTH-1:0] wdata,
    input  logic [ADDR_WIDTH-1:0] raddr,
    output logic [DATA_WIDTH-1:0] rdata
);

    localparam int DEPTH = 1 << ADDR_WIDTH;

    // Memory array
    logic [DATA_WIDTH-1:0] mem [0:DEPTH-1];

    // Synchronous write port: gated by winc and !wfull
    always_ff @(posedge wclk) begin
        if (winc && !wfull) begin
            mem[waddr] <= wdata;
        end
    end

    // Combinatorial asynchronous read port
    assign rdata = mem[raddr];

endmodule
