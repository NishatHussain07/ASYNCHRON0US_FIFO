`timescale 1ns/1ps

module async_fifo_top_tb;

    parameter DATA_SIZE = 8;
    parameter ADDR_SIZE = 3;

    // Inputs
    reg wr_clk;
    reg rd_clk;
    reg rest_n;
    reg wr_enb;
    reg rd_enb;
    reg [DATA_SIZE-1:0] wr_data;

    // Outputs
    wire [DATA_SIZE-1:0] rd_data;
    wire full;
    wire empty;

    //--------------------------------------------------
    // DUT Instantiation
    //--------------------------------------------------
    async_fifo_top #(
        .DATA_SIZE(DATA_SIZE),
        .ADDR_SIZE(ADDR_SIZE)
    ) DUT (
        .wr_clk(wr_clk),
        .rd_clk(rd_clk),
        .rest_n(rest_n),
        .wr_enb(wr_enb),
        .rd_enb(rd_enb),
        .wr_data(wr_data),
        .rd_data(rd_data),
        .full(full),
        .empty(empty)
    );

    // Write clock and read clock generation
    always #5 wr_clk = ~wr_clk;
    always #7 rd_clk = ~rd_clk;

    initial begin
        {wr_clk, rd_clk, rest_n, wr_enb, rd_enb} = 0;
    end

    initial begin
        // Reset the FIFO
        rest_n = 0;
        #10;
        rest_n = 1;

        // Write several values into FIFO
        wr_enb = 1;
        wr_data = 8'd5;
        #10;

        wr_data = 8'd6;
        #10;

        wr_data = 8'd7;
        #10;

        wr_data = 8'd8;
        #10;

        wr_data = 8'd9;
        #10;

        wr_data = 8'd10;
        #10;

        wr_data = 8'd11;
        #10;

        wr_data = 8'd12;
        #10;

        // Start read side after write burst
        rest_n = 1;
        rd_enb = 1;
        wr_enb = 0;

        #120;

        // Reset and perform another write burst
        rest_n = 0;
        #10;
        rest_n = 1;
        wr_enb = 1;
        rd_enb = 0;
        @(posedge wr_clk);

        wr_data = 8'd13;
        #10;

        wr_data = 8'd14;
        #10;

        wr_data = 8'd15;
        #10;

        wr_data = 8'd16;
        #10;

        wr_data = 8'd29;
        #10;

        wr_data = 8'd30;
        #10;

        wr_data = 8'd21;
        #10;

        wr_data = 8'd32;
        #10;

        @(posedge rd_clk);
        #10;
        wr_enb = 0;
        rd_enb = 1;

        #150;

        // Final reset and write burst
        rest_n = 0;
        #10;
        rest_n = 1;
        wr_enb = 1;
        wr_data = 8'd26;
        #10;

        wr_data = 8'd24;
        #10;

        wr_data = 8'd31;
        #10;

        wr_data = 8'd26;
        #10;

        wr_data = 8'd24;
        #10;

        wr_data = 8'd31;
        #10;

        wr_data = 8'd26;
        #10;

        wr_data = 8'd24;
        #10;

        wr_data = 8'd31;
        #10;

        wr_enb = 0;
        rd_enb = 1;

        #200;
        $stop;
    end

endmodule
