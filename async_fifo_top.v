`timescale 1ns/1ps

module FIFO_memory #(
    parameter DATA_SIZE = 8,
    parameter ADDR_SIZE = 3
)(
    input  wire                  wr_clk,
    input  wire                  rd_clk,
    input  wire                  rest_n,

    input  wire                  wr_enb,
    input  wire                  rd_enb,

    input  wire                  full,
    input  wire                  empty,

    input  wire [ADDR_SIZE-1:0]  b_wr_addr,
    input  wire [ADDR_SIZE-1:0]  b_rd_addr,

    input  wire [DATA_SIZE-1:0]  wr_data,
    output reg  [DATA_SIZE-1:0]  rd_data
);

    localparam DEPTH = 1 << ADDR_SIZE;

    // Register-based FIFO memory
    reg [DATA_SIZE-1:0] mem [0:DEPTH-1];

    // Write data into memory when write enable is asserted and FIFO is not full
    always @(posedge wr_clk) begin
        if (rest_n && wr_enb && !full) begin
            mem[b_wr_addr] <= wr_data;
        end
    end

    // Read data from memory when read enable is asserted and FIFO is not empty
    always @(posedge rd_clk) begin
        if (!rest_n) begin
            rd_data <= 0;
        end
        else if (rd_enb && !empty) begin
            rd_data <= mem[b_rd_addr];
        end
    end

endmodule

module gray_converter_full #(
    parameter PTR_SIZE = 4
)(
    input  wire                  wr_clk,
    input  wire                  rest_n,
    input  wire                  wr_enb,
    input  wire                  full,
    output reg [PTR_SIZE-1:0]    b_wr_ptr,
    output reg [PTR_SIZE-1:0]    gr_wr_ptr
);

    wire [PTR_SIZE-1:0] b_wr_ptr_next;

    // Binary pointer increment only when a write is accepted
    assign b_wr_ptr_next = b_wr_ptr + (wr_enb && !full);

    always @(posedge wr_clk) begin
        if (!rest_n) begin
            b_wr_ptr  <= 0;
            gr_wr_ptr <= 0;
        end
        else begin
            b_wr_ptr  <= b_wr_ptr_next;
            // Convert binary write pointer to Gray code
            gr_wr_ptr <= (b_wr_ptr_next >> 1) ^ b_wr_ptr_next;
        end
    end

endmodule

module gray_converter_empty #(
    parameter PTR_SIZE = 4
)(
    input  wire                  rd_clk,
    input  wire                  rest_n,
    input  wire                  rd_enb,
    input  wire                  empty,
    output reg [PTR_SIZE-1:0]    b_rd_ptr,
    output reg [PTR_SIZE-1:0]    gr_rd_ptr
);

    wire [PTR_SIZE-1:0] b_rd_ptr_next;

    // Binary pointer increment only when a read is accepted
    assign b_rd_ptr_next = b_rd_ptr + (rd_enb && !empty);

    always @(posedge rd_clk) begin
        if (!rest_n) begin
            b_rd_ptr  <= 0;
            gr_rd_ptr <= 0;
        end
        else begin
            b_rd_ptr  <= b_rd_ptr_next;
            // Convert binary read pointer to Gray code
            gr_rd_ptr <= (b_rd_ptr_next >> 1) ^ b_rd_ptr_next;
        end
    end

endmodule

module ff_sync #(
    parameter size = 4
)(
    input wire clk,
    input wire rest_n,
    input wire [size-1:0] din,
    output reg [size-1:0] q2
);

    reg [size-1:0] q1;

    always @(posedge clk) begin
        if (!rest_n) begin
            q1 <= 0;
            q2 <= 0;
        end
        else begin
            q1 <= din;
            q2 <= q1;
        end
    end

endmodule

module empty_checker #(
    parameter addr_size = 4
)(
    input  wire                     rd_clk,
    input  wire                     rest_n,
    input  wire [addr_size-1:0]    syn_g_wr_ptr,
    input  wire [addr_size-1:0]    gr_rd_ptr,
    output reg                      empty
);

    always @(posedge rd_clk) begin
        if (!rest_n) begin
            empty <= 1;
        end
        else begin
            // FIFO is empty when synchronized write pointer equals read pointer
            empty <= (syn_g_wr_ptr == gr_rd_ptr);
        end
    end

endmodule

module full_checker #(
    parameter addr_size = 4
)(
    input  wire                     wr_clk,
    input  wire                     rest_n,
    input  wire [addr_size-1:0]    syn_g_rd_ptr,
    input  wire [addr_size-1:0]    gr_wr_ptr,
    output reg                      full
);

    always @(posedge wr_clk) begin
        if (!rest_n) begin
            full <= 0;
        end
        else begin
            // Gray-code full condition check
            full <= (gr_wr_ptr == {~syn_g_rd_ptr[addr_size-1:addr_size-2],
                                  syn_g_rd_ptr[addr_size-3:0]});
        end
    end

endmodule

module async_fifo_top #(
    parameter DATA_SIZE = 8,
    parameter ADDR_SIZE = 3
)(
    input  wire                  wr_clk,
    input  wire                  rd_clk,
    input  wire                  rest_n,

    input  wire                  wr_enb,
    input  wire                  rd_enb,

    input  wire [DATA_SIZE-1:0]  wr_data,
    output wire [DATA_SIZE-1:0]  rd_data,

    output wire                  full,
    output wire                  empty
);

    wire [ADDR_SIZE:0] b_wr_ptr;
    wire [ADDR_SIZE:0] b_rd_ptr;
    wire [ADDR_SIZE:0] gr_wr_ptr;
    wire [ADDR_SIZE:0] gr_rd_ptr;
    wire [ADDR_SIZE:0] syn_g_wr_ptr;
    wire [ADDR_SIZE:0] syn_g_rd_ptr;

    // Memory block for FIFO storage
    FIFO_memory #(
        .DATA_SIZE(DATA_SIZE),
        .ADDR_SIZE(ADDR_SIZE)
    ) fifo_mem (
        .wr_clk(wr_clk),
        .rd_clk(rd_clk),
        .rest_n(rest_n),
        .wr_enb(wr_enb),
        .rd_enb(rd_enb),
        .full(full),
        .empty(empty),
        .wr_data(wr_data),
        .rd_data(rd_data),
        .b_wr_addr(b_wr_ptr[ADDR_SIZE-1:0]),
        .b_rd_addr(b_rd_ptr[ADDR_SIZE-1:0])
    );

    // Read pointer generation in read clock domain
    gray_converter_empty #(
        .PTR_SIZE(ADDR_SIZE+1)
    ) rd_pointer (
        .rd_clk(rd_clk),
        .rest_n(rest_n),
        .rd_enb(rd_enb),
        .empty(empty),
        .b_rd_ptr(b_rd_ptr),
        .gr_rd_ptr(gr_rd_ptr)
    );

    // Synchronize read pointer into write clock domain
    ff_sync #(
        .size(ADDR_SIZE+1)
    ) sync_rd (
        .clk(wr_clk),
        .rest_n(rest_n),
        .din(gr_rd_ptr),
        .q2(syn_g_rd_ptr)
    );

    // Write pointer generation in write clock domain
    gray_converter_full #(
        .PTR_SIZE(ADDR_SIZE+1)
    ) wr_pointer (
        .wr_clk(wr_clk),
        .rest_n(rest_n),
        .wr_enb(wr_enb),
        .full(full),
        .b_wr_ptr(b_wr_ptr),
        .gr_wr_ptr(gr_wr_ptr)
    );

    // Synchronize write pointer into read clock domain
    ff_sync #(
        .size(ADDR_SIZE+1)
    ) sync_wr (
        .clk(rd_clk),
        .rest_n(rest_n),
        .din(gr_wr_ptr),
        .q2(syn_g_wr_ptr)
    );

    // Empty flag generation in read clock domain
    empty_checker #(
        .addr_size(ADDR_SIZE+1)
    ) empty_check (
        .rd_clk(rd_clk),
        .rest_n(rest_n),
        .syn_g_wr_ptr(syn_g_wr_ptr),
        .gr_rd_ptr(gr_rd_ptr),
        .empty(empty)
    );

    // Full flag generation in write clock domain
    full_checker #(
        .addr_size(ADDR_SIZE + 1)
    ) status1 (
        .wr_clk(wr_clk),
        .rest_n(rest_n),
        .syn_g_rd_ptr(syn_g_rd_ptr),
        .gr_wr_ptr(gr_wr_ptr),
        .full(full)
    );

endmodule
