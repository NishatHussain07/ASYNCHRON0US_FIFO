# Asynchronous FIFO Project

## 1. Project Overview
This project implements an asynchronous FIFO (First-In-First-Out) memory in Verilog. The FIFO is designed for a data width of 8 bits and a memory depth of 8 entries, with separate clock domains for write and read operations.

The design solves the major challenges of asynchronous FIFOs:
- clock-domain crossing (CDC)
- pointer synchronization
- full/empty flag generation
- gray-code pointer handling
- metastability control
- safe read/write operation without corrupted data

The architecture uses the standard asynchronous FIFO method:
- write operations are controlled by `wr_clk`
- read operations are controlled by `rd_clk`
- read and write pointers are synchronized across domains
- `full` and `empty` signals are generated based on synchronized gray pointers

---

## 2. Block Summary Table

| Block Name | Function | Clock Domain | Main Output |
|---|---|---|---|
| `FIFO_memory` | Stores the actual FIFO data | `wr_clk` and `rd_clk` | `rd_data` |
| `gray_converter_full` | Updates and converts write pointer to gray code | `wr_clk` | `gr_wr_ptr` |
| `gray_converter_empty` | Updates and converts read pointer to gray code | `rd_clk` | `gr_rd_ptr` |
| `ff_sync` | Synchronizes pointer from one clock domain to another | destination clock | synchronized pointer |
| `empty_checker` | Detects empty condition | `rd_clk` | `empty` |
| `full_checker` | Detects full condition | `wr_clk` | `full` |
| `async_fifo_top` | Top-level wrapper and connection of all submodules | both | complete FIFO interface |

---

## 3. System Architecture
The design has four main functional parts:

1. Memory storage block
2. Write/read pointer generation
3. Dual-clock synchronization logic
4. Full/empty detection logic

This is the top-level functional view of the project:

![Top-level asynchronous FIFO architecture](image%20copy%202.png)

The block diagram shows the interaction between:
- `FIFO_memory`
- `gray_converter_full`
- `gray_converter_empty`
- `ff_sync`
- `empty_checker`
- `full_checker`
- `async_fifo_top`

---

## 4. Why Gray Code Is Used
In an asynchronous FIFO, read and write pointers are generated in different clocks. If a regular binary pointer is used directly, multiple bits may change at the same time during pointer increments. That can cause invalid status detection and increase metastability risk.

Gray code solves this because only one bit changes at a time. This makes pointer synchronization much safer and helps the FIFO generate valid `full` and `empty` flags.

---

## 5. RTL Modules with Code and Comments

### 5.1 `FIFO_memory`
This module stores the actual FIFO data and provides read data from the memory array.

```verilog
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

    input [ADDR_SIZE-1:0]        b_wr_addr,
    input [ADDR_SIZE-1:0]        b_rd_addr,

    input  wire [DATA_SIZE-1:0]  wr_data,
    output reg  [DATA_SIZE-1:0]  rd_data
);

    localparam DEPTH = 1 << ADDR_SIZE;

    // Memory array for FIFO storage
    reg [DATA_SIZE-1:0] mem [0:DEPTH-1];

    // Write operation: write data into memory when enabled and FIFO is not full
    always @(posedge wr_clk) begin
        if (rest_n && wr_enb && !full) begin
            mem[b_wr_addr] <= wr_data;
        end
    end

    // Read operation: output data from the read address when valid read is requested
    always @(posedge rd_clk) begin
        if (!rest_n) begin
            rd_data <= 0;
        end
        else if (rd_enb && !empty) begin
            rd_data <= mem[b_rd_addr];
        end
    end

endmodule
```

### 5.2 `gray_converter_full`
This module tracks the write pointer and converts it into gray code for synchronization into the read domain.

```verilog
module gray_converter_full #(
    parameter PTR_SIZE = 4
)(
    input  wire             wr_clk,
    input                  rest_n,
    input                  wr_enb,
    input                  full,
    output reg [PTR_SIZE-1:0] b_wr_ptr,
    output reg [PTR_SIZE-1:0] gr_wr_ptr
);

    wire [PTR_SIZE-1:0] b_wr_ptr_next;

    // Increment the binary write pointer only if a write is allowed
    assign b_wr_ptr_next = b_wr_ptr + (wr_enb && !full);

    always @(posedge wr_clk) begin
        if (!rest_n) begin
            b_wr_ptr <= 0;
            gr_wr_ptr <= 0;
        end
        else begin
            b_wr_ptr <= b_wr_ptr_next;
            // Gray conversion: binary -> gray
            gr_wr_ptr <= (b_wr_ptr_next >> 1) ^ b_wr_ptr_next;
        end
    end

endmodule
```

### 5.3 `gray_converter_empty`
This module tracks the read pointer and converts it into gray code for synchronization into the write domain.

```verilog
module gray_converter_empty #(
    parameter PTR_SIZE = 4
)(
    input  wire             rd_clk,
    input                  rest_n,
    input                  rd_enb,
    input                  empty,
    output reg [PTR_SIZE-1:0] b_rd_ptr,
    output reg [PTR_SIZE-1:0] gr_rd_ptr
);

    wire [PTR_SIZE-1:0] b_rd_ptr_next;

    // Increment the binary read pointer only when read is allowed
    assign b_rd_ptr_next = b_rd_ptr + (rd_enb && !empty);

    always @(posedge rd_clk) begin
        if (!rest_n) begin
            gr_rd_ptr <= 0;
            b_rd_ptr <= 0;
        end
        else begin
            b_rd_ptr <= b_rd_ptr_next;
            // Gray conversion: binary -> gray
            gr_rd_ptr <= (b_rd_ptr_next >> 1) ^ b_rd_ptr_next;
        end
    end

endmodule
```

### 5.4 `ff_sync`
This module performs a standard two-flop synchronizer, which reduces metastability when crossing clock domains.

```verilog
module ff_sync #(
    parameter size = 4
)(
    input clk,
    input rest_n,
    input [size-1:0] din,
    output reg [size-1:0] q2
);

    reg [size-1:0] q1;

    always @(posedge clk) begin
        if (!rest_n) begin
            q2 <= 0;
            q1 <= 0;
        end
        else begin
            q1 <= din;
            q2 <= q1;
        end
    end

endmodule
```

### 5.5 `empty_checker`
This module checks whether the FIFO is empty by comparing the synchronized write pointer with the read pointer.

```verilog
module empty_checker #(
    parameter addr_size = 4
)(
    input rd_clk,
    input rest_n,
    input [addr_size-1:0] syn_g_wr_ptr,
    input [addr_size-1:0] gr_rd_ptr,
    output reg empty
);

    always @(posedge rd_clk) begin
        if (!rest_n) begin
            empty <= 1;
        end
        else begin
            // Empty condition: synchronized write pointer equals read pointer
            empty <= (syn_g_wr_ptr == gr_rd_ptr);
        end
    end

endmodule
```

### 5.6 `full_checker`
This module checks whether the FIFO is full by comparing the synchronized read pointer with the write pointer using the gray pointer relationship.

```verilog
module full_checker #(
    parameter addr_size = 4
)(
    input wr_clk,
    input rest_n,
    input [addr_size-1:0] syn_g_rd_ptr,
    input [addr_size-1:0] gr_wr_ptr,
    output reg full
);

    always @(posedge wr_clk) begin
        if (!rest_n) begin
            full <= 0;
        end
        else begin
            // Full condition: write pointer meets the special gray-code full pattern
            full <= (gr_wr_ptr == {~syn_g_rd_ptr[addr_size-1:addr_size-2],
                                 syn_g_rd_ptr[addr_size-3:0]});
        end
    end

endmodule
```

### 5.7 `async_fifo_top`
This is the top-level wrapper that connects all FIFO submodules into one complete design.

```verilog
module async_fifo_top #(
    parameter DATA_SIZE = 8,
    parameter ADDR_SIZE = 3
)(
    input wr_clk,
    input rd_clk,
    input rest_n,

    input wr_enb,
    input rd_enb,
    input [DATA_SIZE-1:0] wr_data,
    output [DATA_SIZE-1:0] rd_data,

    output full,
    output empty
);

    wire [ADDR_SIZE:0] b_wr_ptr;
    wire [ADDR_SIZE:0] b_rd_ptr;
    wire [ADDR_SIZE:0] gr_wr_ptr;
    wire [ADDR_SIZE:0] gr_rd_ptr;
    wire [ADDR_SIZE:0] syn_g_wr_ptr;
    wire [ADDR_SIZE:0] syn_g_rd_ptr;

    //----------------------------------------------------
    // FIFO Memory
    //----------------------------------------------------
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

    //----------------------------------------------------
    // Read pointer gray conversion
    //----------------------------------------------------
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

    //----------------------------------------------------
    // Synchronize read pointer into write clock domain
    //----------------------------------------------------
    ff_sync #(
        .size(ADDR_SIZE+1)
    ) sync_rd (
        .clk(wr_clk),
        .rest_n(rest_n),
        .din(gr_rd_ptr),
        .q2(syn_g_rd_ptr)
    );

    //----------------------------------------------------
    // Write pointer gray conversion
    //----------------------------------------------------
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

    //----------------------------------------------------
    // Synchronize write pointer into read clock domain
    //----------------------------------------------------
    ff_sync #(
        .size(ADDR_SIZE+1)
    ) sync_wr (
        .clk(rd_clk),
        .rest_n(rest_n),
        .din(gr_wr_ptr),
        .q2(syn_g_wr_ptr)
    );

    //----------------------------------------------------
    // Empty and Full status generation
    //----------------------------------------------------
    empty_checker #(
        .addr_size(ADDR_SIZE+1)
    ) empty_check (
        .rd_clk(rd_clk),
        .rest_n(rest_n),
        .syn_g_wr_ptr(syn_g_wr_ptr),
        .gr_rd_ptr(gr_rd_ptr),
        .empty(empty)
    );

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
```

---

## 6. Testbench (`async_fifo_top_tb`)

This testbench exercises the asynchronous FIFO with alternating write and read operations across two different clocks. It verifies the basic operation of the FIFO and helps observe `full`, `empty`, and `rd_data` behavior.

```verilog
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
    // DUT
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
```

---

## 7. Data Flow and Testbench Notes
- The write clock is generated with a 10 ns period.
- The read clock is generated with a 14 ns period.
- `rest_n` is used to reset the FIFO.
- `wr_enb` controls writing to the FIFO.
- `rd_enb` controls reading from the FIFO.
- `full` becomes high when the FIFO cannot accept more data.
- `empty` becomes high when no data is available to read.

This testbench is useful for checking:
- reset behavior
- write sequence operation
- read sequence operation
- pointer synchronization
- full and empty flag transitions

---

## 8. Project Summary
This project is a practical asynchronous FIFO design in Verilog. It demonstrates the real concepts of clock-domain crossing, gray-code pointer synchronization, and full/empty detection in a simple and understandable way.

The design is ideal for digital hardware learning because it combines:
- memory storage
- control logic
- pointer tracking
- cross-clock synchronization
- status generation

---

## 9. Final Note
This project can be extended by adding:
- a stronger verification testbench
- waveform analysis
- synthesis checks
- larger FIFO depth and width

The RTL and testbench together provide a complete and educational implementation of an asynchronous FIFO.


    always @(posedge rd_clk) begin
        if (!rest_n) begin
            empty <= 1;
        end
        else begin
            // Empty condition: synchronized write pointer equals read pointer
            empty <= (syn_g_wr_ptr == gr_rd_ptr);
        end
    end

endmodule
```

### 5.6 `full_checker`
This module checks whether the FIFO is full by comparing the synchronized read pointer with the write pointer using the gray pointer relationship.

```verilog
module full_checker #(
    parameter addr_size = 4
)(
    input wr_clk,
    input rest_n,
    input [addr_size-1:0] syn_g_rd_ptr,
    input [addr_size-1:0] gr_wr_ptr,
    output reg full
);

    always @(posedge wr_clk) begin
        if (!rest_n) begin
            full <= 0;
        end
        else begin
            // Full condition: write pointer meets the special gray-code full pattern
            full <= (gr_wr_ptr == {~syn_g_rd_ptr[addr_size-1:addr_size-2],
                                 syn_g_rd_ptr[addr_size-3:0]});
        end
    end

endmodule
```

### 5.7 `async_fifo_top`
This is the top-level wrapper that connects all FIFO submodules into one complete design.

```verilog
module async_fifo_top #(
    parameter DATA_SIZE = 8,
    parameter ADDR_SIZE = 3
)(
    input wr_clk,
    input rd_clk,
    input rest_n,

    input wr_enb,
    input rd_enb,
    input [DATA_SIZE-1:0] wr_data,
    output [DATA_SIZE-1:0] rd_data,

    output full,
    output empty
);

    wire [ADDR_SIZE:0] b_wr_ptr;
    wire [ADDR_SIZE:0] b_rd_ptr;
    wire [ADDR_SIZE:0] gr_wr_ptr;
    wire [ADDR_SIZE:0] gr_rd_ptr;
    wire [ADDR_SIZE:0] syn_g_wr_ptr;
    wire [ADDR_SIZE:0] syn_g_rd_ptr;

    //----------------------------------------------------
    // FIFO Memory
    //----------------------------------------------------
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

    //----------------------------------------------------
    // Read pointer gray conversion
    //----------------------------------------------------
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

    //----------------------------------------------------
    // Synchronize read pointer into write clock domain
    //----------------------------------------------------
    ff_sync #(
        .size(ADDR_SIZE+1)
    ) sync_rd (
        .clk(wr_clk),
        .rest_n(rest_n),
        .din(gr_rd_ptr),
        .q2(syn_g_rd_ptr)
    );

    //----------------------------------------------------
    // Write pointer gray conversion
    //----------------------------------------------------
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

    //----------------------------------------------------
    // Synchronize write pointer into read clock domain
    //----------------------------------------------------
    ff_sync #(
        .size(ADDR_SIZE+1)
    ) sync_wr (
        .clk(rd_clk),
        .rest_n(rest_n),
        .din(gr_wr_ptr),
        .q2(syn_g_wr_ptr)
    );

    //----------------------------------------------------
    // Empty and Full status generation
    //----------------------------------------------------
    empty_checker #(
        .addr_size(ADDR_SIZE+1)
    ) empty_check (
        .rd_clk(rd_clk),
        .rest_n(rest_n),
        .syn_g_wr_ptr(syn_g_wr_ptr),
        .gr_rd_ptr(gr_rd_ptr),
        .empty(empty)
    );

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
```

---

## 6. Data Flow Explanation
The FIFO operates as follows:

1. A write occurs on the write clock domain.
2. The write pointer increments and is converted to gray code.
3. This write pointer is synchronized into the read clock domain.
4. The read side compares the synchronized write pointer with the read pointer.
5. The empty flag is asserted when both are equal.
6. A read occurs on the read clock domain.
7. The read pointer increments and is converted to gray code.
8. The read pointer is synchronized into the write clock domain.
9. The write side compares the synchronized read pointer with the write pointer.
10. The full flag is asserted when the pointer condition indicates a full buffer.

---

## 7. Uploaded Diagrams and Their Meaning

- [image.png](image.png) shows the waveform timing behavior of the FIFO.
- [image copy.png](image%20copy.png) shows the full system-level signal and port interaction.
- [image copy 2.png](image%20copy%202.png) shows the architecture of the FIFO with pointer generation and synchronizers.
- Additional images show the detailed sub-block structure and logic flow.

These diagrams help visualize how the FIFO memory, gray pointer logic, synchronized pointers, and status checkers are connected.

---

## 8. Project Summary
This asynchronous FIFO design is a strong example of practical digital system design because it uses:
- asynchronous write/read operations
- two-clock-domain communication
- gray-code pointer synchronization
- full and empty status detection
- memory-based data transfer

This project is especially useful for learning:
- CDC techniques
- metastability handling
- pointer-based FIFO designs
- Verilog RTL modeling

---

## 9. Final Note
This design is a good foundation for further enhancement with:
- a complete Verilog testbench
- simulation-based waveform verification
- synthesis for FPGA/ASIC targets
- parameterized depth scaling for larger FIFO systems

The current project gives a clear and educational view of how an asynchronous FIFO works in real hardware design.
